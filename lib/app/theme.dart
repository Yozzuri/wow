import 'package:flutter/material.dart';

ThemeData buildTheme(
  Brightness brightness,
  Color seedColor, {
  bool translucent = false,
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  );
  final surface = scheme.surface;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: translucent
        ? surface.withValues(alpha: 0.55)
        : surface,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: surface.withValues(alpha: translucent ? 0.6 : 1.0),
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface.withValues(alpha: translucent ? 0.7 : 1.0),
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerHigh.withValues(
        alpha: translucent ? 0.88 : 1.0,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh.withValues(
        alpha: translucent ? 0.96 : 1.0,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerHigh.withValues(
        alpha: translucent ? 0.96 : 1.0,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      isDense: true,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    ),
  );
}
