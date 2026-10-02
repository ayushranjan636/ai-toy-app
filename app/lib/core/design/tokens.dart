import 'package:flutter/widgets.dart';

/// Brand palette and derived roles. Contrast ratios (WCAG 2.x) were measured;
/// see docs/DESIGN.md. Coral (2.2:1 on cream) is never used for text.
abstract final class ZColors {
  static const cream = Color(0xFFFFF8EE); // main background
  static const teal = Color(0xFF214E47); // primary actions, headings (8.9:1 on cream)
  static const mint = Color(0xFFA8CEC3); // subtle surfaces, never text-bearing alone
  static const coral = Color(0xFFF28F79); // sparing emphasis (fills/marks only)
  static const charcoal = Color(0xFF293B36); // body text (11.2:1 on cream)

  // Derived roles
  static const mintSurface = Color(0xFFE6F1EC); // panels; teal text 8.1:1
  static const surface = Color(0xFFFFFDF8); // raised surface on cream
  static const muted = Color(0xFF5A6B66); // secondary text (5.3:1 cream, 4.9:1 mintSurface)
  static const outline = Color(0xFF5A6B66); // input borders (>= 3:1 non-text contrast)
  static const divider = Color(0xFFE3DDD2); // decorative separators only
  static const error = Color(0xFFA63A2A); // 6.1:1 on cream
  static const coralText = Color(0xFFB4472F); // if coral-family text is ever needed (5.1:1)
  static const onTeal = Color(0xFFFFFFFF); // 9.4:1
  static const pressedTeal = Color(0xFF173A35);
}

abstract final class ZSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Horizontal page margin.
  static const double page = 24;
}

abstract final class ZRadius {
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 20;
  static const double pill = 999;

  static const BorderRadius small = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius medium = BorderRadius.all(Radius.circular(md));
  static const BorderRadius large = BorderRadius.all(Radius.circular(lg));
}

abstract final class ZElevation {
  static const double none = 0;

  /// The only shadow in the system: used for bottom sheets and the toy card.
  static const List<BoxShadow> soft = [
    BoxShadow(color: Color(0x14293B36), blurRadius: 16, offset: Offset(0, 4)),
  ];
}

abstract final class ZMotion {
  static const Duration quick = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration gentle = Duration(milliseconds: 360);
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;

  /// Honour the platform "reduce motion" setting.
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration of(BuildContext context, Duration d) => reduced(context) ? Duration.zero : d;
}

/// Minimum touch target (Apple HIG 44pt, Material 48dp).
const double kMinTouchTarget = 48;

abstract final class ZType {
  static const display = TextStyle(
    fontSize: 30,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
  );
  static const title = TextStyle(
    fontSize: 22,
    height: 1.27,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );
  static const heading = TextStyle(fontSize: 18, height: 1.33, fontWeight: FontWeight.w600);
  static const body = TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w400);
  static const bodyStrong = TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w600);
  static const label = TextStyle(fontSize: 15, height: 1.33, fontWeight: FontWeight.w600, letterSpacing: 0.1);
  static const caption = TextStyle(fontSize: 13, height: 1.38, fontWeight: FontWeight.w400);
}
