import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// Small illustrations from simple leaf shapes. Placeholder art until the
/// supplied logo/product images are added to assets/brand (see README there).
/// These do not depict the product.
class LeafMark extends StatelessWidget {
  const LeafMark({super.key, this.size = 56, this.semanticLabel});

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final art = CustomPaint(size: Size.square(size), painter: _LeafPairPainter());
    return semanticLabel == null
        ? ExcludeSemantics(child: art)
        : Semantics(label: semanticLabel, image: true, child: art);
  }
}

class _LeafPairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    _leaf(canvas, Offset(s * 0.5, s * 0.92), s * 0.62, -0.42, ZColors.teal);
    _leaf(canvas, Offset(s * 0.5, s * 0.92), s * 0.5, 0.5, ZColors.mint);
    final dot = Paint()..color = ZColors.coral;
    canvas.drawCircle(Offset(s * 0.74, s * 0.2), s * 0.06, dot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void _leaf(Canvas canvas, Offset base, double length, double angle, Color color) {
  canvas.save();
  canvas.translate(base.dx, base.dy);
  canvas.rotate(angle);
  final w = length * 0.42;
  final path = Path()
    ..moveTo(0, 0)
    ..quadraticBezierTo(w, -length * 0.45, 0, -length)
    ..quadraticBezierTo(-w, -length * 0.45, 0, 0)
    ..close();
  canvas.drawPath(path, Paint()..color = color);
  canvas.restore();
}

/// Text wordmark used until the supplied logo file is added.
class ZivooWordmark extends StatelessWidget {
  const ZivooWordmark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Zivoo',
      header: true,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LeafMark(size: size * 1.1),
          SizedBox(width: size * 0.25),
          // The wordmark is a logo: it should not grow with body text scaling.
          Text(
            'zivoo',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: ZColors.teal,
            ),
          ),
        ],
      ),
    );
  }
}

/// Connection-state ring: slow pulse while searching, steady when connected.
/// Static (no animation) when reduced motion is on.
class ConnectionPulse extends StatefulWidget {
  const ConnectionPulse({super.key, required this.active, this.connected = false, this.size = 132});

  final bool active;
  final bool connected;
  final double size;

  @override
  State<ConnectionPulse> createState() => _ConnectionPulseState();
}

class _ConnectionPulseState extends State<ConnectionPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ConnectionPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate = widget.active && !widget.connected && !ZMotion.reduced(context);
    if (animate && !_c.isAnimating) {
      _c.repeat();
    } else if (!animate && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _PulsePainter(_c.value, widget.connected, widget.active),
            child: Center(
              child: AnimatedSwitcher(
                duration: ZMotion.of(context, ZMotion.standard),
                child: widget.connected
                    ? const Icon(Icons.check_rounded, key: ValueKey('ok'), size: 40, color: ZColors.teal)
                    : LeafMark(key: const ValueKey('leaf'), size: widget.size * 0.36),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.t, this.connected, this.active);

  final double t;
  final bool connected;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r * 0.5, Paint()..color = ZColors.mintSurface);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (connected) {
      canvas.drawCircle(c, r * 0.5, ring..color = ZColors.teal);
      return;
    }
    if (!active) {
      canvas.drawCircle(c, r * 0.5, ring..color = ZColors.mint);
      return;
    }
    for (var i = 0; i < 2; i++) {
      final p = (t + i / 2) % 1;
      final radius = r * (0.5 + 0.5 * Curves.easeOut.transform(p));
      final alpha = (1 - p) * 0.7;
      canvas.drawCircle(c, radius, ring..color = ZColors.mint.withValues(alpha: alpha));
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.t != t || old.connected != connected || old.active != active;
}

/// Thin decorative leaf vine used as a section ornament.
class LeafDivider extends StatelessWidget {
  const LeafDivider({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 20,
      child: CustomPaint(painter: _VinePainter(), size: const Size(double.infinity, 20)),
    ),
  );
}

class _VinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width * 0.4, y),
      Paint()
        ..color = ZColors.divider
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(size.width * 0.6, y),
      Offset(size.width, y),
      Paint()
        ..color = ZColors.divider
        ..strokeWidth = 1,
    );
    _leaf(canvas, Offset(size.width / 2, y + 6), 14, -math.pi / 4, ZColors.mint);
    _leaf(canvas, Offset(size.width / 2, y + 6), 14, math.pi / 4, ZColors.teal);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
