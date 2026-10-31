import 'package:flutter/material.dart';

/// Visual language shared with the AapdaSaathi mobile app: light surfaces,
/// emergency-red primary, rounded cards, high-contrast status colours.
abstract final class AppColors {
  static const primary = Color(0xFFE53935);
  static const primaryDark = Color(0xFFB71C1C);
  static const background = Color(0xFFF4F5F7);
  static const surface = Colors.white;
  static const border = Color(0xFFE3E5EA);
  static const text = Color(0xFF1B1D22);
  static const muted = Color(0xFF5F6673);

  // Delivery status colours (contract: SAFE green, HELP red, NO_REPLY amber, UNREACHABLE gray).
  static const safe = Color(0xFF2E7D32);
  static const help = Color(0xFFD32F2F);
  static const noReply = Color(0xFFF59E0B);
  static const unreachable = Color(0xFF6B7280);
  static const pending = Color(0xFF3B82F6);

  static const drill = Color(0xFF7C3AED);
  static const live = Color(0xFFB91C1C);
  static const info = Color(0xFF0369A1);
  static const warningBg = Color(0xFFFFF7E6);
  static const dangerBg = Color(0xFFFDECEC);
  static const okBg = Color(0xFFE9F6EC);

  static Color status(String status) {
    switch (status) {
      case 'SAFE':
        return safe;
      case 'HELP':
        return help;
      case 'NO_REPLY':
        return noReply;
      case 'UNREACHABLE':
        return unreachable;
      default:
        return pending;
    }
  }

  static Color taskStatus(String status) {
    switch (status) {
      case 'PENDING_APPROVAL':
        return noReply;
      case 'ASSIGNED':
        return info;
      case 'ACCEPTED':
        return pending;
      case 'REACHED':
      case 'COMPLETED':
        return safe;
      case 'CANT_GO':
      case 'REJECTED':
        return help;
      default:
        return unreachable;
    }
  }

  static Color severity(String s) {
    switch (s) {
      case 'Extreme':
        return const Color(0xFF7F1D1D);
      case 'Severe':
        return help;
      case 'Moderate':
        return const Color(0xFFEA580C);
      case 'Minor':
        return const Color(0xFFCA8A04);
      default:
        return unreachable;
    }
  }
}

String statusLabel(String status) => switch (status) {
      'SAFE' => 'Safe',
      'HELP' => 'Help',
      'NO_REPLY' => 'No reply',
      'UNREACHABLE' => 'Unreachable',
      'PENDING' => 'Pending',
      _ => status,
    };

IconData statusIcon(String status) => switch (status) {
      'SAFE' => Icons.check_circle,
      'HELP' => Icons.sos,
      'NO_REPLY' => Icons.hourglass_bottom,
      'UNREACHABLE' => Icons.phone_disabled,
      _ => Icons.schedule,
    };

IconData needIcon(String need) => switch (need) {
      'hearing' => Icons.hearing_disabled,
      'vision' => Icons.visibility_off,
      'mobility' => Icons.accessible,
      'bedridden' => Icons.bed,
      'cognitive' => Icons.psychology,
      'elderly_alone' => Icons.elderly,
      'speech' => Icons.voice_over_off,
      'feature_phone' => Icons.phone_android,
      _ => Icons.info_outline,
    };

String needLabel(String need) => switch (need) {
      'hearing' => 'Hearing',
      'vision' => 'Vision',
      'mobility' => 'Mobility',
      'bedridden' => 'Bedridden',
      'cognitive' => 'Cognitive',
      'elderly_alone' => 'Elderly alone',
      'speech' => 'Speech',
      'feature_phone' => 'Feature phone',
      _ => need,
    };

const allNeeds = ['hearing', 'vision', 'mobility', 'bedridden', 'cognitive', 'elderly_alone', 'speech', 'feature_phone'];

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    onPrimary: Colors.white,
    surface: AppColors.surface,
    brightness: Brightness.light,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF8F9FB),
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: const BorderSide(color: AppColors.border),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: Color(0xFFFDE2E1),
      selectedIconTheme: IconThemeData(color: AppColors.primary),
      selectedLabelTextStyle: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12),
      unselectedLabelTextStyle: TextStyle(color: AppColors.muted, fontSize: 12),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
