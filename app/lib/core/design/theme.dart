import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

ThemeData buildZivooTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: ZColors.teal,
    onPrimary: ZColors.onTeal,
    secondary: ZColors.mint,
    onSecondary: ZColors.charcoal,
    tertiary: ZColors.coral,
    onTertiary: ZColors.charcoal,
    error: ZColors.error,
    onError: ZColors.onTeal,
    surface: ZColors.cream,
    onSurface: ZColors.charcoal,
    onSurfaceVariant: ZColors.muted,
    surfaceContainerLowest: ZColors.surface,
    surfaceContainerLow: ZColors.surface,
    surfaceContainer: ZColors.mintSurface,
    surfaceContainerHigh: ZColors.mintSurface,
    outline: ZColors.outline,
    outlineVariant: ZColors.divider,
  );

  final text = TextTheme(
    displaySmall: ZType.display.copyWith(color: ZColors.teal),
    headlineSmall: ZType.title.copyWith(color: ZColors.teal),
    titleLarge: ZType.title.copyWith(color: ZColors.teal),
    titleMedium: ZType.heading.copyWith(color: ZColors.charcoal),
    bodyLarge: ZType.body.copyWith(color: ZColors.charcoal),
    bodyMedium: ZType.body.copyWith(color: ZColors.charcoal),
    bodySmall: ZType.caption.copyWith(color: ZColors.muted),
    labelLarge: ZType.label.copyWith(color: ZColors.charcoal),
    labelMedium: ZType.caption.copyWith(color: ZColors.muted, fontWeight: FontWeight.w600),
  );

  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: ZRadius.medium,
    borderSide: BorderSide(color: c, width: w),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: ZColors.cream,
    textTheme: text,
    splashFactory: InkSparkle.constantTurbulenceSeedSplashFactory,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    appBarTheme: const AppBarTheme(
      backgroundColor: ZColors.cream,
      foregroundColor: ZColors.teal,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: ZColors.teal),
    ),
    dividerTheme: const DividerThemeData(color: ZColors.divider, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ZColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(ZColors.outline),
      enabledBorder: border(ZColors.outline),
      focusedBorder: border(ZColors.teal, 2),
      errorBorder: border(ZColors.error),
      focusedErrorBorder: border(ZColors.error, 2),
      labelStyle: ZType.body.copyWith(color: ZColors.muted),
      floatingLabelStyle: ZType.caption.copyWith(color: ZColors.teal),
      errorStyle: ZType.caption.copyWith(color: ZColors.error),
      helperStyle: ZType.caption.copyWith(color: ZColors.muted),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: ZColors.surface,
      indicatorColor: ZColors.mintSurface,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => ZType.caption.copyWith(
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
          color: s.contains(WidgetState.selected) ? ZColors.teal : ZColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) =>
            IconThemeData(color: s.contains(WidgetState.selected) ? ZColors.teal : ZColors.muted, size: 24),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? ZColors.onTeal : ZColors.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? ZColors.teal : ZColors.surface,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? ZColors.teal : ZColors.outline,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ZColors.charcoal,
      contentTextStyle: ZType.body.copyWith(color: ZColors.cream),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: ZRadius.medium),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: ZColors.surface,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ZRadius.lg))),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: ZColors.surface,
      shape: RoundedRectangleBorder(borderRadius: ZRadius.large),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: ZColors.teal,
      linearTrackColor: ZColors.mintSurface,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
