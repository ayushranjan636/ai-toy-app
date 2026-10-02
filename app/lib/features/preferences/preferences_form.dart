import 'package:material_ui/material_ui.dart';

import '../../core/design/tokens.dart';
import '../../core/models.dart';
import '../family/family_providers.dart';

const difficultyLabels = {'gentle': 'Gentle', 'steady': 'Steady', 'stretch': 'Stretch'};

/// Edits a preferences payload. Emits a full copy on every change.
class PreferencesForm extends StatefulWidget {
  const PreferencesForm({super.key, required this.initial, required this.onChanged, this.compact = false});

  final Map<String, dynamic> initial;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool compact;

  @override
  State<PreferencesForm> createState() => _PreferencesFormState();
}

class _PreferencesFormState extends State<PreferencesForm> {
  late final Map<String, dynamic> _p = deepCopyPrefs(widget.initial);

  Map<String, dynamic> _act(String key) => ((_p['activities'] as Map)[key] as Map).cast<String, dynamic>();

  void _update(void Function() f) {
    setState(f);
    widget.onChanged(deepCopyPrefs(_p));
  }

  @override
  Widget build(BuildContext context) {
    final limit = (_p['daily_limit_minutes'] as num).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final key in activityTitles.keys)
          MergeSemantics(
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(activityTitles[key]!, style: ZType.bodyStrong),
              value: _act(key)['enabled'] as bool,
              onChanged: (v) => _update(() => _act(key)['enabled'] = v),
            ),
          ),
        const SizedBox(height: ZSpace.md),
        Text('Daily play limit', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: ZSpace.xxs),
        Text(
          'Zivoo says goodbye for the day after $limit minutes of activities.',
          style: ZType.caption.copyWith(color: ZColors.muted),
        ),
        Slider.adaptive(
          value: limit.toDouble(),
          min: 10,
          max: 120,
          divisions: 22,
          label: '$limit min',
          semanticFormatterCallback: (v) => '${v.round()} minutes a day',
          onChanged: (v) => _update(() => _p['daily_limit_minutes'] = v.round()),
        ),
      ],
    );
  }
}

/// Difficulty + session length for one activity.
class ActivityLevelControls extends StatelessWidget {
  const ActivityLevelControls({super.key, required this.prefs, required this.onChanged});

  final Map<String, dynamic> prefs; // the activity sub-map
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  Widget build(BuildContext context) {
    final difficulty = prefs['difficulty'] as String? ?? 'gentle';
    final minutes = (prefs['session_minutes'] as num?)?.toInt() ?? 10;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Difficulty', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: ZSpace.xs),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final e in difficultyLabels.entries) ButtonSegment(value: e.key, label: Text(e.value)),
            ],
            selected: {difficulty},
            onSelectionChanged: (s) => onChanged({...prefs, 'difficulty': s.first}),
          ),
        ),
        const SizedBox(height: ZSpace.lg),
        Text('Session length', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: ZSpace.xxs),
        Text('About $minutes minutes', style: ZType.caption.copyWith(color: ZColors.muted)),
        Slider.adaptive(
          value: minutes.toDouble(),
          min: 5,
          max: 20,
          divisions: 3,
          label: '$minutes min',
          semanticFormatterCallback: (v) => 'About ${v.round()} minutes',
          onChanged: (v) => onChanged({...prefs, 'session_minutes': v.round()}),
        ),
      ],
    );
  }
}
