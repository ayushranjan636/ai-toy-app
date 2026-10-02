import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_error.dart';
import '../../core/design/button.dart';
import '../../core/design/layout.dart';
import '../../core/design/tokens.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../family/family_providers.dart';
import '../preferences/preferences_form.dart';
import '../progress/progress_screens.dart';

String _err(Object e) => e is ApiException ? e.message : 'Something went wrong.';

class ActivitiesScreen extends ConsumerWidget {
  const ActivitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(activitiesProvider);
    final child = ref.watch(activeChildProvider);
    final prefs = child == null ? null : ref.watch(preferencesProvider(child.id)).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Activities')),
      body: activities.when(
        loading: () => const StateView.loading(),
        error: (e, _) =>
            StateView.error(message: _err(e), onAction: () => ref.invalidate(activitiesProvider)),
        data: (list) => ListView(
          padding: const EdgeInsets.only(bottom: ZSpace.xl),
          children: [
            if (child != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(ZSpace.page, 0, ZSpace.page, ZSpace.xs),
                child: Text(
                  'Choose what ${child.displayName} practises with Zivoo.',
                  style: ZType.body.copyWith(color: ZColors.muted),
                ),
              ),
            ZSection(
              children: [
                for (final a in list)
                  ZRow(
                    title: a.title,
                    subtitle: _subtitle(prefs?.server, a.key),
                    icon: activityIcon(a.key),
                    onTap: () => context.go('/activities/${a.key}'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _subtitle(LearningPreferences? p, String key) {
    if (p == null) return null;
    final a = p.activity(key);
    if (a['enabled'] != true) return 'Off';
    return '${difficultyLabels[a['difficulty']] ?? 'Gentle'} · about ${a['session_minutes']} min';
  }
}

class ActivityDetailScreen extends ConsumerStatefulWidget {
  const ActivityDetailScreen({super.key, required this.activityKey});

  final String activityKey;

  @override
  ConsumerState<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends ConsumerState<ActivityDetailScreen> {
  Map<String, dynamic>? _draft;
  bool _saving = false;

  String get _key => widget.activityKey;

  Future<void> _save(String childId) async {
    if (_draft == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(preferencesProvider(childId).notifier).save(_draft!);
      _draft = null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activity = ref.watch(activitiesProvider).value?.where((a) => a.key == _key).firstOrNull;
    final child = ref.watch(activeChildProvider);
    final title = activity?.title ?? activityTitles[_key] ?? 'Activity';
    if (child == null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const StateView.empty(title: 'No child profile yet', message: 'Add a child in Settings first.'),
      );
    }
    final prefsAsync = ref.watch(preferencesProvider(child.id));
    final device = ref
        .watch(devicesProvider)
        .value
        ?.value
        .where((d) => d.activeChildId == child.id)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: prefsAsync.when(
        loading: () => const StateView.loading(),
        error: (e, _) =>
            StateView.error(message: _err(e), onAction: () => ref.invalidate(preferencesProvider(child.id))),
        data: (p) {
          final draft = _draft ?? deepCopyPrefs(p.draft);
          final act = ((draft['activities'] as Map)[_key] as Map).cast<String, dynamic>();
          void edit(void Function(Map<String, dynamic>) f) => setState(() {
            final d = deepCopyPrefs(draft);
            f(d);
            _draft = d;
          });
          return SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(ZSpace.page),
                    children: [
                      if (activity != null) Text(activity.summary, style: ZType.body),
                      if (activity?.assessmentNote != null) ...[
                        const SizedBox(height: ZSpace.md),
                        InlineNotice(message: activity!.assessmentNote!),
                      ],
                      const SizedBox(height: ZSpace.md),
                      MergeSemantics(
                        child: SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Available on Zivoo', style: ZType.bodyStrong),
                          value: act['enabled'] as bool,
                          onChanged: (v) => edit((d) => (d['activities'][_key] as Map)['enabled'] = v),
                        ),
                      ),
                      const SizedBox(height: ZSpace.md),
                      ActivityLevelControls(
                        prefs: act,
                        onChanged: (m) => edit((d) => (d['activities'] as Map)[_key] = m),
                      ),
                      const SizedBox(height: ZSpace.lg),
                      ActivityOptions(activityKey: _key, draft: draft, onEdit: edit),
                      const SizedBox(height: ZSpace.lg),
                      _SyncStatus(prefs: p, device: device, dirty: _draft != null),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.xs, ZSpace.page, ZSpace.md),
                  child: ZButton(
                    label: 'Save changes',
                    busy: _saving,
                    onPressed: _draft == null ? null : () => _save(child.id),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Phone outbox state + toy acknowledgment state, kept distinct.
class _SyncStatus extends ConsumerWidget {
  const _SyncStatus({required this.prefs, required this.device, required this.dirty});

  final PrefsState prefs;
  final Device? device;
  final bool dirty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (prefs.conflict) {
      return const InlineNotice(
        kind: NoticeKind.error,
        message: 'These settings were changed on another phone. We loaded the latest version.',
      );
    }
    if (dirty) return const SizedBox.shrink();
    if (prefs.pendingUpload) {
      return const InlineNotice(
        kind: NoticeKind.warning,
        message: "Saved on this phone. We'll send it when you're back online.",
      );
    }
    final d = device;
    if (d == null) {
      return const InlineNotice(message: 'Saved. Zivoo will use these after it is set up.');
    }
    return switch (d.configSync) {
      ConfigSync.applied => const InlineNotice(
        kind: NoticeKind.success,
        message: 'Saved and applied on Zivoo.',
      ),
      ConfigSync.pending => const InlineNotice(message: 'Your changes will sync when Zivoo reconnects.'),
      ConfigSync.failed => InlineNotice(
        kind: NoticeKind.error,
        message: "Zivoo couldn't apply these changes.",
        action: TextButton(
          onPressed: () async {
            await ref.read(apiProvider).resendConfig(d.id);
            ref.invalidate(devicesProvider);
          },
          child: const Text('Send again'),
        ),
      ),
      ConfigSync.none => const SizedBox.shrink(),
    };
  }
}

/// Activity-specific curated options.
class ActivityOptions extends StatelessWidget {
  const ActivityOptions({super.key, required this.activityKey, required this.draft, required this.onEdit});

  final String activityKey;
  final Map<String, dynamic> draft;
  final void Function(void Function(Map<String, dynamic>)) onEdit;

  @override
  Widget build(BuildContext context) {
    final h = Theme.of(context).textTheme.titleMedium;
    switch (activityKey) {
      case 'maths':
        final m = (draft['maths'] as Map).cast<String, dynamic>();
        final ops = (m['operations'] as List).cast<String>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Questions', style: h),
            const SizedBox(height: ZSpace.xs),
            Wrap(
              spacing: ZSpace.xs,
              children: [
                for (final o in const ['addition', 'subtraction'])
                  FilterChip(
                    label: Text(o == 'addition' ? 'Adding' : 'Taking away'),
                    selected: ops.contains(o),
                    onSelected: (v) => onEdit((d) {
                      final list = ((d['maths'] as Map)['operations'] as List).cast<String>().toSet();
                      v ? list.add(o) : list.remove(o);
                      if (list.isNotEmpty) (d['maths'] as Map)['operations'] = list.toList()..sort();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: ZSpace.md),
            Text('Numbers up to', style: h),
            const SizedBox(height: ZSpace.xs),
            Wrap(
              spacing: ZSpace.xs,
              children: [
                for (final n in const [5, 10, 20, 50, 100])
                  ChoiceChip(
                    label: Text('$n'),
                    selected: m['max_number'] == n,
                    onSelected: (_) => onEdit((d) => (d['maths'] as Map)['max_number'] = n),
                  ),
              ],
            ),
          ],
        );
      case 'spelling':
        final words = ((draft['spelling'] as Map)['words'] as List).cast<String>();
        return _WordListEditor(
          words: words,
          onChanged: (w) => onEdit((d) => (d['spelling'] as Map)['words'] = w),
        );
      case 'phonics':
        return _MultiChoice(
          title: 'Sounds to practise',
          options: const ['s', 'a', 't', 'p', 'i', 'n', 'm', 'd', 'sh', 'ch', 'th', 'ng', 'ai', 'ee'],
          selected: ((draft['phonics'] as Map)['sounds'] as List).cast<String>(),
          onChanged: (v) => onEdit((d) => (d['phonics'] as Map)['sounds'] = v),
        );
      case 'vocabulary':
        return _MultiChoice(
          title: 'Topics',
          options: const ['animals', 'food', 'home', 'nature', 'feelings', 'transport'],
          selected: ((draft['vocabulary'] as Map)['themes'] as List).cast<String>(),
          onChanged: (v) => onEdit((d) => (d['vocabulary'] as Map)['themes'] = v),
          labelOf: (s) => s[0].toUpperCase() + s.substring(1),
        );
      case 'stories':
        const titles = {
          'the-lost-acorn': 'The Lost Acorn',
          'moon-garden': 'The Moon Garden',
          'river-boat': 'The River Boat',
        };
        return _MultiChoice(
          title: 'Stories',
          options: titles.keys.toList(),
          selected: ((draft['stories'] as Map)['stories'] as List).cast<String>(),
          onChanged: (v) => onEdit((d) => (d['stories'] as Map)['stories'] = v),
          labelOf: (k) => titles[k]!,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _MultiChoice extends StatelessWidget {
  const _MultiChoice({
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.labelOf,
  });

  final String title;
  final List<String> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final String Function(String)? labelOf;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: ZSpace.xs),
      Wrap(
        spacing: ZSpace.xs,
        runSpacing: ZSpace.xs,
        children: [
          for (final o in options)
            FilterChip(
              label: Text(labelOf?.call(o) ?? o),
              selected: selected.contains(o),
              onSelected: (v) {
                final next = [...selected];
                v ? next.add(o) : next.remove(o);
                if (next.isNotEmpty) onChanged(next);
              },
            ),
        ],
      ),
    ],
  );
}

class _WordListEditor extends StatefulWidget {
  const _WordListEditor({required this.words, required this.onChanged});

  final List<String> words;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_WordListEditor> createState() => _WordListEditorState();
}

class _WordListEditorState extends State<_WordListEditor> {
  final _input = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final w = _input.text.trim().toLowerCase();
    if (!RegExp(r'^[a-z]{2,12}$').hasMatch(w)) {
      setState(() => _error = 'Use one word, 2 to 12 letters.');
      return;
    }
    if (widget.words.length >= 20) {
      setState(() => _error = 'You can add up to 20 words.');
      return;
    }
    _input.clear();
    setState(() => _error = null);
    widget.onChanged({...widget.words, w}.toList());
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Your word list', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: ZSpace.xxs),
      Text(
        widget.words.isEmpty
            ? 'Zivoo will use its own words for the chosen difficulty.'
            : 'Zivoo will practise these words.',
        style: ZType.caption.copyWith(color: ZColors.muted),
      ),
      const SizedBox(height: ZSpace.sm),
      Wrap(
        spacing: ZSpace.xs,
        runSpacing: ZSpace.xs,
        children: [
          for (final w in widget.words)
            InputChip(
              label: Text(w),
              onDeleted: () => widget.onChanged([...widget.words]..remove(w)),
              deleteButtonTooltipMessage: 'Remove $w',
            ),
        ],
      ),
      const SizedBox(height: ZSpace.sm),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              decoration: InputDecoration(labelText: 'Add a word', errorText: _error),
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _add(),
            ),
          ),
          const SizedBox(width: ZSpace.xs),
          IconButton.filledTonal(tooltip: 'Add word', onPressed: _add, icon: const Icon(Icons.add_rounded)),
        ],
      ),
    ],
  );
}
