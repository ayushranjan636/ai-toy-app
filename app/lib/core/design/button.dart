import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

enum ZButtonKind { primary, secondary, quiet, destructive }

/// Button with a subtle press-scale, a busy state, and a 52pt minimum height.
class ZButton extends StatefulWidget {
  const ZButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = ZButtonKind.primary,
    this.busy = false,
    this.icon,
    this.semanticsHint,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final ZButtonKind kind;
  final bool busy;
  final IconData? icon;
  final String? semanticsHint;
  final bool expand;

  @override
  State<ZButton> createState() => _ZButtonState();
}

class _ZButtonState extends State<ZButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final (bg, fg, side) = switch (widget.kind) {
      ZButtonKind.primary => (ZColors.teal, ZColors.onTeal, BorderSide.none),
      ZButtonKind.secondary => (
        Colors.transparent,
        ZColors.teal,
        const BorderSide(color: ZColors.teal, width: 1.5),
      ),
      ZButtonKind.quiet => (Colors.transparent, ZColors.teal, BorderSide.none),
      ZButtonKind.destructive => (
        Colors.transparent,
        ZColors.error,
        const BorderSide(color: ZColors.error, width: 1.5),
      ),
    };
    final pressedBg = widget.kind == ZButtonKind.primary ? ZColors.pressedTeal : ZColors.mintSurface;

    final child = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.busy)
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        else if (widget.icon != null)
          Icon(widget.icon, size: 20, color: fg),
        if (widget.busy || widget.icon != null) const SizedBox(width: ZSpace.xs),
        Flexible(
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: ZType.label.copyWith(color: fg, fontSize: 16),
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      hint: widget.semanticsHint,
      label: widget.busy ? '${widget.label}, in progress' : null,
      excludeSemantics: widget.busy,
      child: AnimatedScale(
        scale: _down && !ZMotion.reduced(context) ? 0.98 : 1,
        duration: ZMotion.quick,
        child: Opacity(
          opacity: enabled || widget.busy ? 1 : 0.45,
          child: Material(
            color: _down ? pressedBg : bg,
            shape: RoundedRectangleBorder(borderRadius: ZRadius.medium, side: side),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? widget.onPressed : null,
              onHighlightChanged: (v) => setState(() => _down = v),
              splashColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52, minWidth: kMinTouchTarget),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: ZSpace.lg, vertical: 14),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
