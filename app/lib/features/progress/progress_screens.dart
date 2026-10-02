import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_error.dart';
import '../../core/design/layout.dart';
import '../../core/design/tokens.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../family/family_providers.dart';

String _err(Object e) => e is ApiException ? e.message : 'Something went wrong.';

/// One line per session in grouped lists.
class SessionRow extends StatelessWidget {
  const SessionRow({super.key, required this.session});

  final SessionSummary session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final parts = <String>[
      relativeTime(s.startedAt),
      if (s.total > 0) '${s.total} practised',
      if (s.status == 'ended_early') 'ended early',
      if (s.status == 'in_progress') 'in progress',
    ];
    return ZRow(
      title: activityTitles[s.activityKey] ?? s.activityKey,
      subtitle: parts.join(' · '),
      icon: _activityIcon(s.activityKey),
      trailing: s.needsPractice > 0
          ? StatusLabel(label: '${s.needsPractice} to revisit', tone: StatusTone.attention)
          : null,
      onTap: () => context.go('/progress/${s.id}'),
    );
  }
}

IconData _activityIcon(String key) => switch (key) {
  'phonics' => Icons.record_voice_over_outlined,
  'vocabulary' => Icons.chat_bubble_outline_rounded,
  'spelling' => Icons.spellcheck_rounded,
  'maths' => Icons.calculate_outlined,
  'stories' => Icons.menu_book_outlined,
  _ => Icons.extension_outlined,
};

IconData activityIcon(String key) => _activityIcon(key);

// ------------------------------------------------------------------ list with pagination

class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key});

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  final List<SessionSummary> _items = [];
  String? _cursor;
  bool _loading = false;
  bool _done = false;
  Object? _error;
  String? _childId;

  Future<void> _load({bool reset = false}) async {
    final child = ref.read(activeChildProvider);
    if (child == null || _loading) return;
    if (reset) {
      _items.clear();
      _cursor = null;
      _done = false;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(apiProvider).sessions(childId: child.id, cursor: _cursor);
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _done = page.nextCursor == null;
      });
    } catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = ref.watch(activeChildProvider);
    if (child != null && child.id != _childId) {
      _childId = child.id;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
    }
    return Scaffold(
      appBar: AppBar(title: Text(child == null ? 'Progress' : "${child.displayName}'s progress")),
      body: child == null
          ? const StateView.empty(
              title: 'No child profile yet',
              message: 'Add a child in Settings to see progress.',
            )
          : RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.extentAfter < 300 && !_done && !_loading && _error == null) _load();
                  return false;
                },
                child: ListView(
                  padding: const EdgeInsets.only(bottom: ZSpace.xl),
                  children: [
                    if (_items.isEmpty && _loading)
                      const StateView.loading()
                    else if (_items.isEmpty && _error != null)
                      StateView.error(message: _err(_error!), onAction: () => _load(reset: true))
                    else if (_items.isEmpty)
                      StateView.empty(
                        title: 'No sessions yet',
                        message: "Sessions appear here after ${child.displayName} plays with Zivoo.",
                      )
                    else ...[
                      ..._grouped(),
                      if (_loading) const StateView.loading(),
                      if (_error != null && _items.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(ZSpace.page),
                          child: InlineNotice(
                            kind: NoticeKind.error,
                            message: _err(_error!),
                            action: TextButton(onPressed: _load, child: const Text('Try again')),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  List<Widget> _grouped() {
    final byDay = <String, List<SessionSummary>>{};
    for (final s in _items) {
      byDay.putIfAbsent(DateFormat.yMMMMEEEEd().format(s.startedAt.toLocal()), () => []).add(s);
    }
    return [
      for (final e in byDay.entries)
        ZSection(
          title: e.key,
          children: [for (final s in e.value) SessionRow(session: s)],
        ),
    ];
  }
}

// ------------------------------------------------------------------ detail

class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  Future<void> _delete(BuildContext context, WidgetRef ref, SessionSummary s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this session?'),
        content: const Text('Its results and any transcript will be removed. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: ZColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).deleteSession(sessionId);
      ref.invalidate(recentSessionsProvider(s.childId));
      if (context.mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session deleted')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_err(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(sessionDetailProvider(sessionId));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          detail.value == null ? 'Session' : activityTitles[detail.value!.summary.activityKey] ?? 'Session',
        ),
        actions: [
          if (detail.value != null)
            IconButton(
              tooltip: 'Delete session',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _delete(context, ref, detail.value!.summary),
            ),
        ],
      ),
      body: detail.when(
        loading: () => const StateView.loading(),
        error: (e, _) => StateView.error(
          message: _err(e),
          onAction: () => ref.invalidate(sessionDetailProvider(sessionId)),
        ),
        data: (d) => _DetailBody(detail: d),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail});

  final SessionDetail detail;

  @override
  Widget build(BuildContext context) {
    final s = detail.summary;
    final items = finalPerItem(detail.items);
    final revisit = items.where((a) => a.outcome == Outcome.needsPractice).toList();
    final unsure = items.where((a) => a.outcome == Outcome.uncertain).toList();
    final correct = items.where((a) => a.outcome == Outcome.correct).toList();
    final duration = s.endedAt?.difference(s.startedAt);

    return ListView(
      padding: const EdgeInsets.only(bottom: ZSpace.xl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.md, ZSpace.page, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat.yMMMMEEEEd().add_jm().format(s.startedAt.toLocal()),
                style: ZType.caption.copyWith(color: ZColors.muted),
              ),
              const SizedBox(height: ZSpace.xs),
              if (s.summary != null) Text(s.summary!, style: ZType.body),
              if (duration != null) ...[
                const SizedBox(height: ZSpace.xxs),
                Text(durationLabel(duration), style: ZType.caption.copyWith(color: ZColors.muted)),
              ],
            ],
          ),
        ),
        if (items.isEmpty)
          const StateView.empty(
            title: 'Nothing was practised',
            message: 'This session ended before the first question.',
          ),
        if (revisit.isNotEmpty)
          ZSection(
            title: 'To revisit',
            children: [for (final a in revisit) _ItemRow(item: a)],
          ),
        if (unsure.isNotEmpty)
          ZSection(
            title: "Zivoo wasn't sure",
            footer: "Zivoo couldn't hear clearly or couldn't assess these, so they weren't marked right or wrong.",
            children: [for (final a in unsure) _ItemRow(item: a)],
          ),
        if (correct.isNotEmpty)
          ZSection(
            title: 'Got it',
            children: [for (final a in correct) _ItemRow(item: a)],
          ),
        if (detail.transcriptsAvailable)
          ZSection(
            title: 'Transcript',
            children: [
              for (final t in detail.turns)
                Padding(
                  padding: const EdgeInsets.all(ZSpace.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 56,
                        child: Text(
                          t.speaker == 'toy' ? 'Zivoo' : 'Child',
                          style: ZType.caption.copyWith(fontWeight: FontWeight.w600, color: ZColors.teal),
                        ),
                      ),
                      Expanded(child: Text(t.text ?? '', style: ZType.body)),
                    ],
                  ),
                ),
            ],
          )
        else
          Padding(
            padding: const EdgeInsets.all(ZSpace.page),
            child: Text(
              'Transcripts are off. You can turn them on in Settings > Data and privacy.',
              style: ZType.caption.copyWith(color: ZColors.muted),
            ),
          ),
      ],
    );
  }
}

/// The final outcome per item is its last recorded attempt (ordered by seq).
List<AssessmentItem> finalPerItem(List<AssessmentItem> all) {
  final byIndex = <int, AssessmentItem>{};
  for (final a in [...all]..sort((x, y) => x.seq.compareTo(y.seq))) {
    byIndex[a.itemIndex] = a;
  }
  return byIndex.values.toList();
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final AssessmentItem item;

  @override
  Widget build(BuildContext context) {
    final a = item;
    final detail = [
      if (a.expected != null && a.outcome != Outcome.correct) 'Answer: ${a.expected}',
      if (a.response != null) 'Heard: "${a.response}"',
      if (a.source.startsWith('pronunciation')) 'Practice only, not scored',
    ].join(' · ');
    final (icon, label) = switch (a.outcome) {
      Outcome.correct => (Icons.check_rounded, 'Correct'),
      Outcome.needsPractice => (Icons.refresh_rounded, 'Needs practice'),
      Outcome.uncertain => (Icons.help_outline_rounded, 'Not assessed'),
    };
    return Semantics(
      label: '$label. ${a.prompt}. $detail',
      excludeSemantics: true,
      child: ZRow(title: a.prompt, subtitle: detail.isEmpty ? null : detail, icon: icon),
    );
  }
}
