import 'package:flutter/material.dart';

/// "Machined graphite" with a periwinkle signal accent.
abstract final class Palette {
  static const background = Color(0xFF0B0D12);
  static const backgroundTop = Color(0xFF1A2033);
  static const surface = Color(0xFF131722);
  static const raised = Color(0xFF1B2030);
  static const raisedHi = Color(0xFF252B3D);
  static const line = Color(0x12FFFFFF);
  static const text = Color(0xFFEEF1F7);
  static const muted = Color(0xFF8B93A7);
  static const accent = Color(0xFF8EA2FF);
  static const accentHi = Color(0xFFA9B7FF);
  static const accentLo = Color(0xFF7D93FF);
  static const accentInk = Color(0xFF0B0D12);
  static const power = Color(0xFFFF5C5C);
  static const ok = Color(0xFF3DDC97);
  static const red = Color(0xFFFF5C5C);
  static const green = Color(0xFF3DDC97);
  static const yellow = Color(0xFFFFCF4A);
  static const blue = Color(0xFF5B8CFF);
  static const warning = Color(0xFFFFB224);

  // Older names still used by a few screens.
  static const panel = surface;
  static const key = raised;
  static const keyPressed = raisedHi;
  static const keyBorder = Color(0xFF262C3B);
}

const String kFontFamily = 'Manrope';

/// Section label: small, bold, spaced capitals.
const TextStyle kSectionStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w800,
  letterSpacing: 1.3,
  color: Palette.muted,
);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.accent,
    brightness: Brightness.dark,
  ).copyWith(
    surface: Palette.surface,
    primary: Palette.accent,
    onPrimary: Palette.accentInk,
    error: Palette.red,
  );
  final base = Typography.whiteMountainView.apply(
    bodyColor: Palette.text,
    displayColor: Palette.text,
    fontFamily: kFontFamily,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: kFontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.background,
    textTheme: base,
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.background,
      foregroundColor: Palette.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: kFontFamily,
        fontSize: 19,
        fontWeight: FontWeight.w800,
        color: Palette.text,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.raised,
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
        backgroundColor: Palette.accent,
        foregroundColor: Palette.accentInk,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontFamily: kFontFamily, fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Palette.accent,
        textStyle: const TextStyle(fontFamily: kFontFamily, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Palette.raisedHi,
      contentTextStyle: TextStyle(fontFamily: kFontFamily, color: Palette.text, fontSize: 14),
      actionTextColor: Palette.accent,
      behavior: SnackBarBehavior.floating,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Palette.raised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontFamily: kFontFamily, color: Palette.text, fontSize: 14.5),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Palette.surface,
      showDragHandle: true,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: Palette.surface),
  );
}

/// The raised, slightly glossy key surface used across the remote.
BoxDecoration keyDecoration({required bool pressed, double radius = 15, Color? tint}) {
  final top = tint ?? Palette.raisedHi;
  final bottom = tint == null ? Palette.raised : Color.lerp(tint, Colors.black, 0.18)!;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: pressed ? [bottom, bottom] : [top, bottom],
    ),
    border: Border.all(color: Palette.line),
    boxShadow: pressed
        ? const []
        : const [BoxShadow(color: Color(0xCC000000), blurRadius: 14, offset: Offset(0, 6), spreadRadius: -8)],
  );
}
