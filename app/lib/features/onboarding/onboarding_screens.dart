import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_error.dart';
import '../../core/design/button.dart';
import '../../core/design/illustrations.dart';
import '../../core/design/layout.dart';
import '../../core/design/tokens.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../family/family_providers.dart';
import '../preferences/preferences_form.dart';
import 'setup_progress.dart';

String _msg(Object e) => e is ApiException ? e.message : "Something went wrong. Try again.";

/// Persist the confirmed step on the server so another phone resumes here.
Future<void> advanceOnboarding(WidgetRef ref, OnboardingStep step) async {
  await ref.read(apiProvider).updateMe({'onboarding_step': step.wire});
  ref.invalidate(meProvider);
  await ref.read(meProvider.future);
}

// ------------------------------------------------------------------ Parent intro + data choices

class ParentIntroScreen extends ConsumerStatefulWidget {
  const ParentIntroScreen({super.key});

  @override
  ConsumerState<ParentIntroScreen> createState() => _ParentIntroScreenState();
}

class _ParentIntroScreenState extends ConsumerState<ParentIntroScreen> {
  final _name = TextEditingController();
  bool _transcripts = false;
  bool _analytics = false;
  bool _marketing = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final me = ref.read(meProvider).value;
    if (me != null) {
      _name.text = me.displayName ?? '';
      _transcripts = me.storeTranscripts;
      _analytics = me.productAnalytics;
      _marketing = me.marketingOptIn;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).updateMe({
        if (_name.text.trim().isNotEmpty) 'display_name': _name.text.trim(),
        'store_transcripts': _transcripts,
        'product_analytics': _analytics,
        'marketing_opt_in': _marketing,
        'data_choices_confirmed': true,
      });
      await advanceOnboarding(ref, OnboardingStep.connectToy);
      if (mounted) context.go('/setup');
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      title: 'A few choices first',
      subtitle: 'You can change any of these later in Settings.',
      step: 1,
      totalSteps: 4,
      showBack: false,
      primary: ZButton(label: 'Continue', busy: _busy, onPressed: _continue),
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: 'Your first name (optional)',
            helperText: 'Shown only to you in the app.',
          ),
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.givenName],
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: ZSpace.lg),
        Text('What Zivoo keeps', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: ZSpace.xs),
        Text(
          "Zivoo saves which questions were practised and how they went. "
          "It doesn't keep recordings of your child's voice.",
          style: ZType.body.copyWith(color: ZColors.muted),
        ),
        const SizedBox(height: ZSpace.md),
        _ChoiceTile(
          title: 'Save session transcripts',
          subtitle: 'Lets you read what was said in each session. Off by default.',
          value: _transcripts,
          onChanged: (v) => setState(() => _transcripts = v),
        ),
        _ChoiceTile(
          title: 'Share app usage to improve Zivoo',
          subtitle: 'Anonymous app performance and setup success. No session content.',
          value: _analytics,
          onChanged: (v) => setState(() => _analytics = v),
        ),
        const LeafDivider(),
        _ChoiceTile(
          title: 'Product news by email',
          subtitle: 'Occasional updates. Not needed to use Zivoo.',
          value: _marketing,
          onChanged: (v) => setState(() => _marketing = v),
        ),
        if (_error != null) ...[
          const SizedBox(height: ZSpace.md),
          InlineNotice(message: _error!, kind: NoticeKind.error),
        ],
      ],
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: ZType.bodyStrong),
      subtitle: Text(subtitle, style: ZType.caption.copyWith(color: ZColors.muted)),
      value: value,
      onChanged: onChanged,
    ),
  );
}

// ------------------------------------------------------------------ Child profile

class ChildProfileScreen extends ConsumerStatefulWidget {
  const ChildProfileScreen({super.key});

  @override
  ConsumerState<ChildProfileScreen> createState() => _ChildProfileScreenState();
}

class _ChildProfileScreenState extends ConsumerState<ChildProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  int? _birthYear;
  String _language = 'en-GB';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final existing = ref.read(childrenProvider).value?.value ?? const [];
      if (existing.isEmpty) {
        await ref
            .read(apiProvider)
            .createChild(name: _name.text.trim(), birthYear: _birthYear, language: _language);
      }
      ref.invalidate(childrenProvider);
      ref.invalidate(devicesProvider);
      await advanceOnboarding(ref, OnboardingStep.preferences);
      if (mounted) context.go('/onboarding/preferences');
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = [for (var y = DateTime.now().year - 3; y >= DateTime.now().year - 11; y--) y];
    return StepScaffold(
      title: 'Who will play with Zivoo?',
      subtitle: 'Zivoo uses this name when it talks. A first name or nickname is enough.',
      step: 3,
      totalSteps: 4,
      showBack: false,
      primary: ZButton(label: 'Continue', busy: _busy, onPressed: _save),
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: "Child's first name or nickname"),
                textCapitalization: TextCapitalization.words,
                maxLength: 40,
                textInputAction: TextInputAction.done,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name.' : null,
              ),
              const SizedBox(height: ZSpace.sm),
              DropdownButtonFormField<int?>(
                isExpanded: true,
                initialValue: _birthYear,
                decoration: const InputDecoration(
                  labelText: 'Year of birth (optional)',
                  helperText: 'Helps pick the right level. We never ask for a full birthday.',
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Prefer not to say')),
                  for (final y in years) DropdownMenuItem(value: y, child: Text('$y')),
                ],
                onChanged: (v) => setState(() => _birthYear = v),
              ),
              const SizedBox(height: ZSpace.md),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _language,
                decoration: const InputDecoration(labelText: 'Language Zivoo speaks'),
                items: const [
                  DropdownMenuItem(value: 'en-GB', child: Text('English (UK)')),
                  DropdownMenuItem(value: 'en-US', child: Text('English (US)')),
                  DropdownMenuItem(value: 'en-IN', child: Text('English (India)')),
                ],
                onChanged: (v) => setState(() => _language = v ?? 'en-GB'),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: ZSpace.md),
          InlineNotice(message: _error!, kind: NoticeKind.error),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------------ Learning preferences

class OnboardingPreferencesScreen extends ConsumerStatefulWidget {
  const OnboardingPreferencesScreen({super.key});

  @override
  ConsumerState<OnboardingPreferencesScreen> createState() => _OnboardingPreferencesScreenState();
}

class _OnboardingPreferencesScreenState extends ConsumerState<OnboardingPreferencesScreen> {
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _draft;

  Future<void> _finish(String childId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_draft != null) await ref.read(preferencesProvider(childId).notifier).save(_draft!);
      await advanceOnboarding(ref, OnboardingStep.done);
      await SetupProgressStore().setToySetupSkipped(false);
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = ref.watch(activeChildProvider);
    if (child == null) {
      return const Scaffold(body: StateView.loading());
    }
    final prefs = ref.watch(preferencesProvider(child.id));
    return StepScaffold(
      title: "What should ${child.displayName} practise?",
      subtitle: 'Start gently. You can adjust these any time.',
      step: 4,
      totalSteps: 4,
      showBack: false,
      primary: ZButton(label: 'Finish', busy: _busy, onPressed: () => _finish(child.id)),
      children: [
        prefs.when(
          loading: () => const StateView.loading(),
          error: (e, _) => StateView.error(
            message: _msg(e),
            onAction: () => ref.invalidate(preferencesProvider(child.id)),
          ),
          data: (p) =>
              PreferencesForm(initial: _draft ?? p.draft, onChanged: (d) => _draft = d, compact: true),
        ),
        if (_error != null) ...[
          const SizedBox(height: ZSpace.md),
          InlineNotice(message: _error!, kind: NoticeKind.error),
        ],
      ],
    );
  }
}
