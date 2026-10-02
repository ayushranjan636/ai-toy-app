import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../core/api/api_error.dart';
import '../../core/config.dart';
import '../../core/design/button.dart';
import '../../core/design/layout.dart';
import '../../core/design/tokens.dart';
import '../../core/models.dart';
import '../../core/util.dart';
import '../family/family_providers.dart';
import '../provisioning/application/setup_controller.dart';
import '../progress/progress_screens.dart';

String _err(Object e) => e is ApiException ? e.message : 'Something went wrong.';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).value;
    final children = ref.watch(childrenProvider);
    final devices = ref.watch(devicesProvider);
    final child = ref.watch(activeChildProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            refreshFamily(ref);
            await ref.read(devicesProvider.future).catchError((_) => const Fresh(<Device>[]));
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: ZSpace.xl),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.lg, ZSpace.page, ZSpace.xs),
                child: Semantics(
                  header: true,
                  child: Text(
                    me?.displayName?.isNotEmpty == true ? 'Hello, ${me!.displayName}' : 'Hello',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                ),
              ),
              if (children.value?.offline == true || devices.value?.offline == true)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: ZSpace.page, vertical: ZSpace.xs),
                  child: InlineNotice(
                    kind: NoticeKind.warning,
                    message:
                        "You're offline. Showing what we saved "
                        "${relativeTime(devices.value?.cachedAt ?? children.value!.cachedAt!).toLowerCase()}.",
                  ),
                ),
              _ChildSwitcher(child: child),
              const SizedBox(height: ZSpace.md),
              devices.when(
                loading: () => const StateView.loading(message: 'Checking your Zivoo'),
                error: (e, _) =>
                    StateView.error(message: _err(e), onAction: () => ref.invalidate(devicesProvider)),
                data: (d) => d.value.isEmpty
                    ? const _NoToyPanel()
                    : _DevicePanel(device: d.value.first, stale: d.offline),
              ),
              if (child != null) ...[
                const SizedBox(height: ZSpace.lg),
                _Suggestion(child: child),
                _Recent(child: child),
              ] else if (children.hasValue)
                Padding(
                  padding: const EdgeInsets.all(ZSpace.page),
                  child: StateView.empty(
                    title: 'Add your child',
                    message: 'Zivoo needs a child profile before it can start activities.',
                    actionLabel: 'Add child',
                    onAction: () => context.go('/settings/children'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChildSwitcher extends ConsumerWidget {
  const _ChildSwitcher({required this.child});

  final Child? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(childrenProvider).value?.value ?? const [];
    if (child == null || all.length < 2) {
      return child == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: ZSpace.page),
              child: Text(
                "Here's how things are going for ${child!.displayName}.",
                style: ZType.body.copyWith(color: ZColors.muted),
              ),
            );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: ZSpace.page),
      child: Row(
        children: [
          for (final c in all)
            Padding(
              padding: const EdgeInsets.only(right: ZSpace.xs),
              child: ChoiceChip(
                label: Text(c.displayName),
                selected: c.id == child!.id,
                onSelected: (_) => ref.read(selectedChildIdProvider.notifier).select(c.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoToyPanel extends StatelessWidget {
  const _NoToyPanel();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: ZSpace.md),
    child: Container(
      padding: const EdgeInsets.all(ZSpace.lg),
      decoration: const BoxDecoration(color: ZColors.mintSurface, borderRadius: ZRadius.large),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Connect your Zivoo', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: ZSpace.xs),
          const Text('It takes a few minutes. Have your Wi-Fi password ready.'),
          const SizedBox(height: ZSpace.md),
          ZButton(label: 'Set up Zivoo', expand: false, onPressed: () => context.push('/setup?from=home')),
        ],
      ),
    ),
  );
}

class _DevicePanel extends ConsumerWidget {
  const _DevicePanel({required this.device, required this.stale});

  final Device device;
  final bool stale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = device.online && !stale;
    final seen = device.lastSeenAt == null
        ? 'Not seen yet'
        : 'Last seen ${relativeTime(device.lastSeenAt!).toLowerCase()}';
    final simToy = ref.watch(simulatedToyProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ZSpace.md),
      child: Material(
        color: ZColors.surface,
        borderRadius: ZRadius.large,
        child: InkWell(
          borderRadius: ZRadius.large,
          onTap: () => context.go('/settings/device/${device.id}'),
          child: Padding(
            padding: const EdgeInsets.all(ZSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(device.name, style: Theme.of(context).textTheme.titleLarge)),
                    StatusLabel(
                      label: online ? 'Online' : 'Offline',
                      tone: online ? StatusTone.good : StatusTone.waiting,
                    ),
                  ],
                ),
                const SizedBox(height: ZSpace.xxs),
                Text(
                  online ? 'Connected to ${device.wifiSsid ?? 'Wi-Fi'}' : seen,
                  style: ZType.caption.copyWith(color: ZColors.muted),
                ),
                if (device.configSync == ConfigSync.pending) ...[
                  const SizedBox(height: ZSpace.sm),
                  const InlineNotice(message: 'Your changes will sync when Zivoo reconnects.'),
                ],
                if (device.configSync == ConfigSync.failed) ...[
                  const SizedBox(height: ZSpace.sm),
                  const InlineNotice(
                    kind: NoticeKind.error,
                    message: "Zivoo couldn't apply your latest changes.",
                  ),
                ],
                if (device.isSimulated && AppConfig.simulatorEnabled && simToy != null) ...[
                  const SizedBox(height: ZSpace.md),
                  ZButton(
                    label: 'Simulate a maths session',
                    kind: ZButtonKind.secondary,
                    icon: Icons.science_outlined,
                    onPressed: () async {
                      await simToy.playDemoSession();
                      refreshFamily(ref);
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Suggestion extends ConsumerWidget {
  const _Suggestion({required this.child});

  final Child child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentSessionsProvider(child.id)).value?.value;
    final prefs = ref.watch(preferencesProvider(child.id)).value;
    if (recent == null || prefs == null) return const SizedBox.shrink();
    final s = suggestNext(recent, prefs.server);
    if (s == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(ZSpace.md, 0, ZSpace.md, ZSpace.lg),
      child: Container(
        padding: const EdgeInsets.all(ZSpace.lg),
        decoration: const BoxDecoration(color: ZColors.mintSurface, borderRadius: ZRadius.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SUGGESTED NEXT',
              style: ZType.caption.copyWith(fontWeight: FontWeight.w600, color: ZColors.teal),
            ),
            const SizedBox(height: ZSpace.xs),
            Text(activityTitles[s.key] ?? s.key, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: ZSpace.xxs),
            Text(s.reason),
            const SizedBox(height: ZSpace.md),
            ZButton(
              label: 'View activity',
              kind: ZButtonKind.secondary,
              expand: false,
              onPressed: () => context.go('/activities/${s.key}'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Deterministic suggestion based only on real session data.
({String key, String reason})? suggestNext(List<SessionSummary> recent, LearningPreferences prefs) {
  final enabled = [
    for (final k in activityTitles.keys)
      if (prefs.activity(k)['enabled'] == true) k,
  ];
  if (enabled.isEmpty) return null;
  final revisit = recent.where((s) => s.needsPractice > 0 && enabled.contains(s.activityKey)).firstOrNull;
  if (revisit != null) {
    return (
      key: revisit.activityKey,
      reason:
          '${revisit.needsPractice} ${revisit.needsPractice == 1 ? 'item' : 'items'} '
          'from the last session could use another go.',
    );
  }
  final played = recent.map((s) => s.activityKey).toSet();
  final fresh = enabled.where((k) => !played.contains(k)).firstOrNull;
  if (fresh != null) {
    return (key: fresh, reason: recent.isEmpty ? 'A good place to start.' : 'Not tried recently.');
  }
  return null;
}

class _Recent extends ConsumerWidget {
  const _Recent({required this.child});

  final Child child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(recentSessionsProvider(child.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(ZSpace.page, 0, ZSpace.page, ZSpace.xs),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Recent activity', style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              if ((sessions.value?.value ?? const []).isNotEmpty)
                TextButton(onPressed: () => context.go('/progress'), child: const Text('See all')),
            ],
          ),
        ),
        sessions.when(
          loading: () => const StateView.loading(),
          error: (e, _) => StateView.error(
            message: _err(e),
            onAction: () => ref.invalidate(recentSessionsProvider(child.id)),
          ),
          data: (d) => d.value.isEmpty
              ? StateView.empty(
                  title: 'No sessions yet',
                  message: "When ${child.displayName} plays with Zivoo, sessions will appear here.",
                )
              : ZSection(children: [for (final s in d.value.take(3)) SessionRow(session: s)]),
        ),
      ],
    );
  }
}
