import 'package:material_ui/material_ui.dart';

import 'button.dart';
import 'illustrations.dart';
import 'tokens.dart';

/// Onboarding page: optional step indicator, title, body, and exactly one
/// primary action pinned above the keyboard. Scrolls on small phones and
/// with large text.
class StepScaffold extends StatelessWidget {
  const StepScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    required this.primary,
    this.secondary,
    this.step,
    this.totalSteps,
    this.showBack = true,
    this.onBack,
    this.leading,
    this.topAction,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final ZButton primary;
  final Widget? secondary;
  final int? step;
  final int? totalSteps;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? leading;
  final Widget? topAction;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: showBack && (canPop || onBack != null)
            ? IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              )
            : null,
        title: step != null && totalSteps != null
            ? Semantics(
                label: 'Step $step of $totalSteps',
                excludeSemantics: true,
                child: _StepDots(step: step!, total: totalSteps!),
              )
            : null,
        centerTitle: true,
        actions: [?topAction],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.md, ZSpace.page, ZSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (leading != null) ...[leading!, const SizedBox(height: ZSpace.lg)],
                    Semantics(
                      header: true,
                      child: Text(title, style: Theme.of(context).textTheme.displaySmall),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: ZSpace.sm),
                      Text(subtitle!, style: ZType.body.copyWith(color: ZColors.muted)),
                    ],
                    const SizedBox(height: ZSpace.lg),
                    ...children,
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.xs, ZSpace.page, ZSpace.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  primary,
                  if (secondary != null) ...[const SizedBox(height: ZSpace.xs), secondary!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final active = i < step;
        return AnimatedContainer(
          duration: ZMotion.of(context, ZMotion.standard),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: i == step - 1 ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? ZColors.teal : ZColors.mint,
            borderRadius: BorderRadius.circular(ZRadius.pill),
          ),
        );
      }),
    );
  }
}

/// Inline status message. Uses icon + text, never colour alone.
class InlineNotice extends StatelessWidget {
  const InlineNotice({super.key, required this.message, this.kind = NoticeKind.info, this.action});

  final String message;
  final NoticeKind kind;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (kind) {
      NoticeKind.info => (Icons.info_outline_rounded, ZColors.teal),
      NoticeKind.warning => (Icons.wifi_off_rounded, ZColors.charcoal),
      NoticeKind.error => (Icons.error_outline_rounded, ZColors.error),
      NoticeKind.success => (Icons.check_circle_outline_rounded, ZColors.teal),
    };
    return Semantics(
      liveRegion: kind == NoticeKind.error,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(ZSpace.md),
        decoration: BoxDecoration(
          color: kind == NoticeKind.error ? const Color(0xFFFBEAE5) : ZColors.mintSurface,
          borderRadius: ZRadius.medium,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: ZSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message, style: ZType.body.copyWith(color: ZColors.charcoal)),
                  if (action != null) ...[const SizedBox(height: ZSpace.xs), action!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum NoticeKind { info, warning, error, success }

/// Loading / empty / error states with honest, short copy.
class StateView extends StatelessWidget {
  const StateView.loading({super.key, this.message = 'Loading'})
    : title = null,
      actionLabel = null,
      onAction = null,
      _kind = _StateKind.loading;

  const StateView.empty({
    super.key,
    required String this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  }) : _kind = _StateKind.empty;

  const StateView.error({
    super.key,
    this.title = 'Something went wrong',
    required this.message,
    this.actionLabel = 'Try again',
    this.onAction,
  }) : _kind = _StateKind.error;

  final String? title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final _StateKind _kind;

  @override
  Widget build(BuildContext context) {
    if (_kind == _StateKind.loading) {
      return Semantics(
        label: message,
        liveRegion: true,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(ZSpace.xl),
            child: SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ZSpace.page, vertical: ZSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _kind == _StateKind.error
              ? const Icon(Icons.cloud_off_rounded, size: 40, color: ZColors.muted)
              : const LeafMark(size: 48),
          const SizedBox(height: ZSpace.md),
          Text(title!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: ZSpace.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: ZType.body.copyWith(color: ZColors.muted),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: ZSpace.lg),
            ZButton(label: actionLabel!, onPressed: onAction, kind: ZButtonKind.secondary, expand: false),
          ],
        ],
      ),
    );
  }
}

enum _StateKind { loading, empty, error }

/// Grouped list section used in Settings and details (not a card per item).
class ZSection extends StatelessWidget {
  const ZSection({super.key, this.title, required this.children, this.footer});

  final String? title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.lg, ZSpace.page, ZSpace.xs),
            child: Semantics(
              header: true,
              child: Text(
                title!.toUpperCase(),
                style: ZType.caption.copyWith(
                  color: ZColors.muted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: ZSpace.md),
          decoration: const BoxDecoration(color: ZColors.surface, borderRadius: ZRadius.medium),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(indent: ZSpace.md),
                children[i],
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.xs, ZSpace.page, 0),
            child: Text(footer!, style: ZType.caption.copyWith(color: ZColors.muted)),
          ),
      ],
    );
  }
}

class ZRow extends StatelessWidget {
  const ZRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? ZColors.error : ZColors.charcoal;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: ZSpace.md, vertical: ZSpace.sm),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 22, color: destructive ? ZColors.error : ZColors.teal),
                const SizedBox(width: ZSpace.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: ZType.body.copyWith(color: color)),
                    if (subtitle != null)
                      Text(subtitle!, style: ZType.caption.copyWith(color: ZColors.muted)),
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (onTap != null)
                const Icon(Icons.chevron_right_rounded, color: ZColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Status label with dot + text (colour is never the only signal).
class StatusLabel extends StatelessWidget {
  const StatusLabel({super.key, required this.label, required this.tone});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (dot, bg) = switch (tone) {
      StatusTone.good => (ZColors.teal, ZColors.mintSurface),
      StatusTone.waiting => (ZColors.muted, const Color(0xFFF1ECE2)),
      StatusTone.attention => (ZColors.coral, const Color(0xFFFCE9E3)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(ZRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: ZType.caption.copyWith(color: ZColors.charcoal, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

enum StatusTone { good, waiting, attention }
