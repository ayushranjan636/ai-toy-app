import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config.dart';
import '../../../core/design/button.dart';
import '../../../core/design/illustrations.dart';
import '../../../core/design/layout.dart';
import '../../../core/design/tokens.dart';
import '../application/auth_controller.dart';
import '../domain/auth.dart';

String _authError(Object e) => e is AuthException ? e.message : "We couldn't complete that. Try again.";

// ------------------------------------------------------------------ Welcome

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final expired = auth is SignedOut && auth.expired;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: ZSpace.page),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: ZSpace.xl),
                    const ZivooWordmark(size: 26),
                    const Spacer(),
                    const _WelcomeArt(),
                    const SizedBox(height: ZSpace.xl),
                    Semantics(
                      header: true,
                      child: Text(
                        'Learning that talks back, gently.',
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                    ),
                    const SizedBox(height: ZSpace.sm),
                    Text(
                      'Set up your Zivoo, choose what your child practises, '
                      'and see how each session went.',
                      style: ZType.body.copyWith(color: ZColors.muted),
                    ),
                    if (expired) ...[
                      const SizedBox(height: ZSpace.md),
                      const InlineNotice(message: 'You were signed out. Please sign in again.'),
                    ],
                    const Spacer(),
                    const SizedBox(height: ZSpace.lg),
                    ZButton(label: 'Create account', onPressed: () => context.push('/sign-up')),
                    const SizedBox(height: ZSpace.xs),
                    ZButton(
                      label: 'I already have an account',
                      kind: ZButtonKind.quiet,
                      onPressed: () => context.push('/sign-in'),
                    ),
                    if (AppConfig.useDevAuth)
                      Padding(
                        padding: const EdgeInsets.only(top: ZSpace.xs),
                        child: Text(
                          'Development sign-in. Test account: demo@example.com / zivoo-test-123. '
                          'Verification code: 123456',
                          textAlign: TextAlign.center,
                          style: ZType.caption.copyWith(color: ZColors.muted),
                        ),
                      ),
                    const SizedBox(height: ZSpace.md),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeArt extends StatelessWidget {
  const _WelcomeArt();

  @override
  Widget build(BuildContext context) {
    // Placeholder composition from leaf shapes; replace with the supplied
    // product image (assets/brand/product.png) without altering it.
    return ExcludeSemantics(
      child: Container(
        height: 180,
        width: double.infinity,
        decoration: const BoxDecoration(color: ZColors.mintSurface, borderRadius: ZRadius.large),
        child: const Stack(
          alignment: Alignment.center,
          children: [
            Positioned(left: 28, bottom: 20, child: LeafMark(size: 54)),
            Positioned(right: 36, top: 22, child: LeafMark(size: 38)),
            LeafMark(size: 96),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ Sign up

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  bool _agreed = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_agreed) {
      setState(() => _error = 'Please agree to the terms and privacy notice to continue.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).signUp(_email.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = _authError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      title: 'Create your account',
      subtitle: "You'll manage Zivoo from here. Your child doesn't need an account.",
      primary: ZButton(label: 'Create account', busy: _busy, onPressed: _submit),
      secondary: ZButton(
        label: 'I already have an account',
        kind: ZButtonKind.quiet,
        onPressed: () => context.pushReplacement('/sign-in'),
      ),
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              children: [
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  validator: validateEmail,
                ),
                const SizedBox(height: ZSpace.md),
                TextFormField(
                  controller: _password,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    helperText: 'At least 10 characters.',
                    suffixIcon: _ObscureToggle(
                      obscured: _obscure,
                      onTap: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: validateNewPassword,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: ZSpace.md),
        _CheckRow(
          value: _agreed,
          onChanged: (v) => setState(() => _agreed = v),
          label: 'I agree to the Terms and the Privacy Notice.',
        ),
        if (_error != null) ...[
          const SizedBox(height: ZSpace.md),
          InlineNotice(message: _error!, kind: NoticeKind.error),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------------ Verify email

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;

  String get _email {
    final s = ref.read(authControllerProvider);
    return s is AwaitingVerification ? s.email : '';
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_code.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6-digit code from the email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).verify(_email, _code.text);
    } catch (e) {
      if (mounted) setState(() => _error = _authError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(authControllerProvider.notifier).resendVerification(_email);
      setState(() => _info = 'We sent a new code.');
    } catch (e) {
      setState(() => _error = _authError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(authControllerProvider) is AwaitingVerification ? _email : '';
    return StepScaffold(
      title: 'Check your email',
      subtitle: 'We sent a 6-digit code to $email.',
      onBack: () => ref.read(authControllerProvider.notifier).abandonVerification(),
      primary: ZButton(label: 'Verify email', busy: _busy, onPressed: _verify),
      secondary: ZButton(label: 'Send a new code', kind: ZButtonKind.quiet, onPressed: _resend),
      children: [
        TextField(
          controller: _code,
          decoration: const InputDecoration(labelText: 'Verification code'),
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          style: ZType.title.copyWith(letterSpacing: 6, color: ZColors.charcoal),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: ZSpace.sm),
        Text("Can't find it? Check your spam folder.", style: ZType.caption.copyWith(color: ZColors.muted)),
        if (_info != null) ...[
          const SizedBox(height: ZSpace.md),
          InlineNotice(message: _info!, kind: NoticeKind.success),
        ],
        if (_error != null) ...[
          const SizedBox(height: ZSpace.md),
          InlineNotice(message: _error!, kind: NoticeKind.error),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------------ Sign in

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).signIn(_email.text, _password.text);
      TextInput.finishAutofillContext();
    } catch (e) {
      if (mounted) setState(() => _error = _authError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      title: 'Welcome back',
      primary: ZButton(label: 'Sign in', busy: _busy, onPressed: _submit),
      secondary: ZButton(
        label: 'Forgot password?',
        kind: ZButtonKind.quiet,
        onPressed: () => context.push('/forgot'),
      ),
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              children: [
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email, AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  validator: validateEmail,
                ),
                const SizedBox(height: ZSpace.md),
                TextFormField(
                  controller: _password,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: _ObscureToggle(
                      obscured: _obscure,
                      onTap: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) => (v ?? '').isEmpty ? 'Enter your password.' : null,
                ),
              ],
            ),
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

// ------------------------------------------------------------------ Forgot / reset

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).requestReset(_email.text);
      if (mounted) {
        context.pushReplacement('/reset?email=${Uri.encodeQueryComponent(_email.text.trim())}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = _authError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      title: 'Reset your password',
      subtitle: "Enter your email and we'll send you a code.",
      primary: ZButton(label: 'Send code', busy: _busy, onPressed: _submit),
      children: [
        Form(
          key: _form,
          child: TextFormField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email'),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            validator: validateEmail,
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

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).resetPassword(widget.email, _code.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = _authError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      title: 'Choose a new password',
      subtitle: 'Enter the code we sent to ${widget.email}.',
      primary: ZButton(label: 'Save password', busy: _busy, onPressed: _submit),
      children: [
        Form(
          key: _form,
          child: Column(
            children: [
              TextFormField(
                controller: _code,
                decoration: const InputDecoration(labelText: 'Code from email'),
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                textInputAction: TextInputAction.next,
                validator: (v) => (v ?? '').length == 6 ? null : 'Enter the 6-digit code.',
              ),
              const SizedBox(height: ZSpace.md),
              TextFormField(
                controller: _password,
                decoration: InputDecoration(
                  labelText: 'New password',
                  helperText: 'At least 10 characters.',
                  suffixIcon: _ObscureToggle(
                    obscured: _obscure,
                    onTap: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: validateNewPassword,
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

// ------------------------------------------------------------------ shared bits

class _ObscureToggle extends StatelessWidget {
  const _ObscureToggle({required this.obscured, required this.onTap});

  final bool obscured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: obscured ? 'Show password' : 'Hide password',
    icon: Icon(obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: ZColors.muted),
    onPressed: onTap,
  );
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.value, required this.onChanged, required this.label});

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: InkWell(
      borderRadius: ZRadius.small,
      onTap: () => onChanged(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinTouchTarget),
        child: Row(
          children: [
            Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
            Expanded(child: Text(label, style: ZType.body)),
          ],
        ),
      ),
    ),
  );
}

/// Exposed for tests.
final authErrorText = _authError;
