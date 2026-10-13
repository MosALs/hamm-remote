import 'package:flutter/material.dart';

/// Colours of the remote. Dark like the physical remote, with the same
/// white D-pad ring.
abstract final class Palette {
  static const background = Color(0xFF0E1014);
  static const panel = Color(0xFF171A21);
  static const key = Color(0xFF242832);
  static const keyPressed = Color(0xFF323846);
  static const keyBorder = Color(0xFF2E3340);
  static const text = Color(0xFFE9ECF2);
  static const muted = Color(0xFF8A93A6);
  static const accent = Color(0xFF4FD1C5);
  static const ring = Color(0xFFECEEF2);
  static const ringPressed = Color(0xFFD3D7DF);
  static const ringIcon = Color(0xFF2A2E37);
  static const okKey = Color(0xFF1B1E25);
  static const power = Color(0xFFE5484D);
  static const red = Color(0xFFE5484D);
  static const green = Color(0xFF30A46C);
  static const yellow = Color(0xFFFFC53D);
  static const blue = Color(0xFF3E8BFF);
  static const warning = Color(0xFFFFB224);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.accent,
    brightness: Brightness.dark,
  ).copyWith(
    surface: Palette.panel,
    primary: Palette.accent,
    onPrimary: Palette.background,
    error: Palette.red,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.background,
      foregroundColor: Palette.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    textTheme: Typography.whiteMountainView.apply(
      bodyColor: Palette.text,
      displayColor: Palette.text,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.key,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.accent, width: 1.5),
      ),
      hintStyle: const TextStyle(color: Palette.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Palette.panel,
      showDragHandle: true,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: Palette.panel),
  );
}
