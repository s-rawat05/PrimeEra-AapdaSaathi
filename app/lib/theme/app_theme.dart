import 'package:flutter/material.dart';

/// Visual language: white / light-gray surfaces, emergency red, high contrast, rounded cards,
/// big touch targets.
abstract final class AppColors {
  static const red = Color(0xFFE53935);
  static const redDark = Color(0xFFB71C1C);
  static const redSoft = Color(0xFFFFEBEE);
  static const green = Color(0xFF1B873F);
  static const greenSoft = Color(0xFFE6F4EA);
  static const amber = Color(0xFFB26A00);
  static const amberSoft = Color(0xFFFFF4E0);
  static const gray = Color(0xFF5F6368);
  static const background = Color(0xFFF4F5F7);
  static const surface = Colors.white;
  static const ink = Color(0xFF1A1C1E);
  static const outline = Color(0xFFE0E2E6);
  static const official = Color(0xFF0B57D0);
  static const officialSoft = Color(0xFFE8F0FE);

  static Color forStatus(String status) => switch (status) {
        'SAFE' => green,
        'HELP' => red,
        'NO_REPLY' || 'PENDING' => amber,
        _ => gray,
      };

  static Color softForStatus(String status) => switch (status) {
        'SAFE' => greenSoft,
        'HELP' => redSoft,
        'NO_REPLY' || 'PENDING' => amberSoft,
        _ => const Color(0xFFEEEEEE),
      };
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.red,
    primary: AppColors.red,
    onPrimary: Colors.white,
    surface: AppColors.surface,
    error: AppColors.redDark,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, scaffoldBackgroundColor: AppColors.background);
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.red,
      foregroundColor: Colors.white,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.outline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.redSoft,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 13,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? AppColors.red : AppColors.gray,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.red : AppColors.gray),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
  );
}
