import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_error.dart';
import '../../core/design/button.dart';
import '../../core/design/layout.dart';
import '../../core/design/tokens.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../auth/application/auth_controller.dart';
import '../family/family_providers.dart';
import '../preferences/preferences_form.dart';

export 'device_settings.dart';

String _err(Object e) => e is ApiException ? e.message : 'Something went wrong.';

void _toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider).value?.value ?? const <Device>[];
    final children = ref.watch(childrenProvider).value?.value ?? const <Child>[];
    final me = ref.watch(meProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: ZSpace.xl),
        children: [
          ZSection(
            title: 'Family',
            children: [
              ZRow(
                title: 'Children',
                subtitle: children.isEmpty ? 'None yet' : children.map((c) => c.displayName).join(', '),
                icon: Icons.face_outlined,
                onTap: () => context.go('/settings/children'),
              ),
              ZRow(
                title: 'Learning limits',
                subtitle: 'Daily play time',
                icon: Icons.timer_outlined,
                onTap: () => context.go('/settings/limits'),
              ),
            ],
          ),
          ZSection(
            title: 'Zivoo',
            children: [
              for (final d in devices)
                ZRow(
                  title: d.name,
                  subtitle: d.online ? 'Online' : 'Offline',
                  icon: Icons.speaker_outlined,
                  onTap: () => context.go('/settings/device/${d.id}'),
                ),
              if (devices.isEmpty)
                ZRow(
                  title: 'Set up Zivoo',
                  icon: Icons.add_rounded,
                  onTap: () => context.push('/setup?from=settings'),
                ),
            ],
          ),
          ZSection(
            title: 'App',
            children: [
              ZRow(
                title: 'Notifications',
                icon: Icons.notifications_none_rounded,
                onTap: () => context.go('/settings/notifications'),
              ),
              ZRow(
                title: 'Data and privacy',
                icon: Icons.lock_outline_rounded,
                onTap: () => context.go('/settings/data'),
              ),
              ZRow(
                title: 'Help',
                icon: Icons.help_outline_rounded,
                onTap: () => context.go('/settings/help'),
              ),
            ],
          ),
          ZSection(
            title: 'Account',
            children: [
              ZRow(
                title: me?.email ?? 'Account',
                icon: Icons.person_outline_rounded,
                onTap: () => context.go('/settings/account'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ children

class ChildrenSettingsScreen extends ConsumerWidget {
  const ChildrenSettingsScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [Child? child]) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => _ChildSheet(child: child),
    );
    if (result == null) return;
    try {
      if (child == null) {
        await ref.read(apiProvider).createChild(name: result);
      } else {
        await ref.read(apiProvider).updateChild(child.id, {'display_name': result});
      }
      ref.invalidate(childrenProvider);
      ref.invalidate(devicesProvider);
    } catch (e) {
      if (context.mounted) _toast(context, _err(e));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Child child) async {
    final ok = await confirmDestructive(
      context,
      title: 'Delete ${child.displayName}\u2019s profile?',
      body: 'Their settings and all session history will be deleted. This cannot be undone.',
      action: 'Delete profile',
    );
    if (!ok) return;
    try {
      await ref.read(apiProvider).deleteChild(child.id);
      ref.invalidate(childrenProvider);
      ref.invalidate(devicesProvider);
    } catch (e) {
      if (context.mounted) _toast(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(childrenProvider);
    final devices = ref.watch(devicesProvider).value?.value ?? const <Device>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Children')),
      body: children.when(
        loading: () => const StateView.loading(),
        error: (e, _) => StateView.error(message: _err(e), onAction: () => ref.invalidate(childrenProvider)),
        data: (d) => ListView(
          children: [
            if (d.value.isNotEmpty)
              ZSection(
                footer: 'Zivoo talks with one child at a time. Choose who is playing in device settings.',
                children: [
                  for (final c in d.value)
                    ZRow(
                      title: c.displayName,
                      subtitle: devices.any((x) => x.activeChildId == c.id) ? 'Playing with Zivoo now' : null,
                      icon: Icons.face_outlined,
                      onTap: () => _edit(context, ref, c),
                      trailing: IconButton(
                        tooltip: 'Delete ${c.displayName}',
                        icon: const Icon(Icons.delete_outline_rounded, color: ZColors.muted),
                        onPressed: () => _delete(context, ref, c),
                      ),
                    ),
                ],
              )
            else
              const StateView.empty(
                title: 'No children yet',
                message: 'Add a profile so Zivoo knows who it is talking to.',
              ),
            Padding(
              padding: const EdgeInsets.all(ZSpace.page),
              child: ZButton(
                label: 'Add a child',
                kind: ZButtonKind.secondary,
                icon: Icons.add_rounded,
                onPressed: () => _edit(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChildSheet extends StatefulWidget {
  const _ChildSheet({this.child});

  final Child? child;

  @override
  State<_ChildSheet> createState() => _ChildSheetState();
}

class _ChildSheetState extends State<_ChildSheet> {
  late final _name = TextEditingController(text: widget.child?.displayName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    final v = _name.text.trim();
    if (v.isNotEmpty) Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      ZSpace.page,
      0,
      ZSpace.page,
      MediaQuery.viewInsetsOf(context).bottom + ZSpace.lg,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.child == null ? 'Add a child' : 'Edit name',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: ZSpace.md),
        TextField(
          controller: _name,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'First name or nickname'),
          onSubmitted: (_) => _done(),
        ),
        const SizedBox(height: ZSpace.sm),
        ZButton(label: 'Save', onPressed: _done),
      ],
    ),
  );
}

// ------------------------------------------------------------------ limits

class LimitsSettingsScreen extends ConsumerStatefulWidget {
  const LimitsSettingsScreen({super.key});

  @override
  ConsumerState<LimitsSettingsScreen> createState() => _LimitsSettingsScreenState();
}

class _LimitsSettingsScreenState extends ConsumerState<LimitsSettingsScreen> {
  Map<String, dynamic>? _draft;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final child = ref.watch(activeChildProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Learning limits')),
      body: child == null
          ? const StateView.empty(title: 'No child profile yet', message: 'Add a child first.')
          : ref
                .watch(preferencesProvider(child.id))
                .when(
                  loading: () => const StateView.loading(),
                  error: (e, _) => StateView.error(message: _err(e)),
                  data: (p) => ListView(
                    padding: const EdgeInsets.all(ZSpace.page),
                    children: [
                      Text('For ${child.displayName}', style: ZType.caption.copyWith(color: ZColors.muted)),
                      const SizedBox(height: ZSpace.sm),
                      PreferencesForm(
                        initial: _draft ?? p.draft,
                        onChanged: (d) => setState(() => _draft = d),
                      ),
                      if (p.pendingUpload) ...[
                        const SizedBox(height: ZSpace.md),
                        const InlineNotice(
                          kind: NoticeKind.warning,
                          message: "Saved on this phone. We'll send it when you're back online.",
                        ),
                      ],
                      const SizedBox(height: ZSpace.lg),
                      ZButton(
                        label: 'Save changes',
                        busy: _busy,
                        onPressed: _draft == null
                            ? null
                            : () async {
                                setState(() => _busy = true);
                                await ref.read(preferencesProvider(child.id).notifier).save(_draft!);
                                if (mounted) {
                                  setState(() {
                                    _busy = false;
                                    _draft = null;
                                  });
                                }
                              },
                      ),
                    ],
                  ),
                ),
    );
  }
}

// ------------------------------------------------------------------ notifications & data

class _ProfileToggles extends ConsumerWidget {
  const _ProfileToggles({required this.title, required this.items, this.footer});

  final String title;
  final List<(String field, String label, String? help)> items;
  final String? footer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: me.when(
        loading: () => const StateView.loading(),
        error: (e, _) => StateView.error(message: _err(e), onAction: () => ref.invalidate(meProvider)),
        data: (p) {
          final values = {
            'notify_session_summaries': p.notifySessionSummaries,
            'notify_device_offline': p.notifyDeviceOffline,
            'store_transcripts': p.storeTranscripts,
            'product_analytics': p.productAnalytics,
            'marketing_opt_in': p.marketingOptIn,
          };
          return ListView(
            children: [
              ZSection(
                footer: footer,
                children: [
                  for (final (field, label, help) in items)
                    MergeSemantics(
                      child: SwitchListTile.adaptive(
                        title: Text(label),
                        subtitle: help == null
                            ? null
                            : Text(help, style: ZType.caption.copyWith(color: ZColors.muted)),
                        value: values[field] ?? false,
                        onChanged: (v) async {
                          try {
                            await ref.read(apiProvider).updateMe({field: v});
                            ref.invalidate(meProvider);
                          } catch (e) {
                            if (context.mounted) _toast(context, _err(e));
                          }
                        },
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const _ProfileToggles(
    title: 'Notifications',
    footer: 'Push delivery is not set up in this build yet. These choices are saved for when it is.',
    items: [
      ('notify_session_summaries', 'Session summaries', 'After each session ends'),
      ('notify_device_offline', 'Zivoo goes offline', 'If Zivoo is offline for a day'),
    ],
  );
}

class DataSettingsScreen extends StatelessWidget {
  const DataSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const _ProfileToggles(
    title: 'Data and privacy',
    footer:
        "Zivoo doesn't keep voice recordings. Turning transcripts off stops saving them for new "
        'sessions. You can delete any session from Progress, or delete your account to remove everything.',
    items: [
      ('store_transcripts', 'Save session transcripts', 'Lets you read what was said'),
      ('product_analytics', 'Share app usage', 'Anonymous performance and setup success'),
      ('marketing_opt_in', 'Product news by email', null),
    ],
  );
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Help')),
    body: ListView(
      padding: const EdgeInsets.only(bottom: ZSpace.xl),
      children: const [
        _Faq(
          'Zivoo is offline',
          'Check Zivoo is switched on and near your router. If your Wi-Fi changed, use Change Wi-Fi in device settings.',
        ),
        _Faq(
          'My network is missing during setup',
          'Zivoo uses 2.4 GHz Wi-Fi. Many routers have both bands under one name; check 2.4 GHz is on.',
        ),
        _Faq(
          'Zivoo says it didn\u2019t hear clearly',
          'Background noise or speaking far away can make it hard to hear. Zivoo never marks an answer wrong when it isn\u2019t sure what was said.',
        ),
        _Faq(
          'How is pronunciation checked?',
          'It isn\u2019t yet. Sound practice is recorded as practice only until a dedicated pronunciation check is available.',
        ),
        _Faq(
          'Giving Zivoo to someone else',
          'Remove it from your account in device settings, then factory reset it so the new owner can set it up.',
        ),
      ],
    ),
  );
}

class _Faq extends StatelessWidget {
  const _Faq(this.q, this.a);

  final String q;
  final String a;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(q, style: ZType.bodyStrong),
    childrenPadding: const EdgeInsets.fromLTRB(ZSpace.md, 0, ZSpace.md, ZSpace.md),
    children: [Text(a, style: ZType.body.copyWith(color: ZColors.muted))],
  );
}

// ------------------------------------------------------------------ account

class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => const _DeleteAccountDialog());
    if (ok != true) return;
    try {
      await ref.read(apiProvider).deleteAccount();
      await ref.read(authControllerProvider.notifier).signOut();
    } catch (e) {
      if (context.mounted) _toast(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        children: [
          ZSection(
            children: [ZRow(title: 'Email', subtitle: me?.email, icon: Icons.mail_outline_rounded)],
          ),
          ZSection(
            children: [
              ZRow(
                title: 'Sign out',
                icon: Icons.logout_rounded,
                onTap: () => ref.read(authControllerProvider.notifier).signOut(),
              ),
            ],
          ),
          ZSection(
            footer:
                'Deletes your children\u2019s profiles, all sessions and settings, and removes your Zivoo '
                'from this account.',
            children: [
              ZRow(
                title: 'Delete account',
                icon: Icons.delete_forever_outlined,
                destructive: true,
                onTap: () => _deleteAccount(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Delete your account?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('This permanently deletes your family\u2019s data. Type DELETE to confirm.'),
        const SizedBox(height: ZSpace.md),
        TextField(
          controller: _c,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => setState(() {}),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      TextButton(
        onPressed: _c.text.trim() == 'DELETE' ? () => Navigator.pop(context, true) : null,
        style: TextButton.styleFrom(foregroundColor: ZColors.error),
        child: const Text('Delete account'),
      ),
    ],
  );
}

Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          style: TextButton.styleFrom(foregroundColor: ZColors.error),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok == true;
}

String lastSeenLabel(Device d) => d.online
    ? 'Online now'
    : (d.lastSeenAt == null ? 'Not seen yet' : 'Last seen ${relativeTime(d.lastSeenAt!).toLowerCase()}');
