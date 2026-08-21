import 'package:flutter/material.dart';

abstract final class SpendWiseColors {
  static const background = Color(0xFF070B0E);
  static const surface = Color(0xFF0D1317);
  static const surfaceRaised = Color(0xFF121A1F);
  static const border = Color(0xFF223039);
  static const accent = Color(0xFF60D394);
  static const accentMuted = Color(0xFF173728);
  static const income = Color(0xFF71D99B);
  static const expense = Color(0xFFFF7B72);
  static const warning = Color(0xFFF2C96D);
  static const textSecondary = Color(0xFF8E9CA5);
}

abstract final class SpendWiseTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: SpendWiseColors.accent,
      onPrimary: Color(0xFF052014),
      secondary: Color(0xFF9CE6BA),
      surface: SpendWiseColors.surface,
      onSurface: Color(0xFFEAF2EE),
      error: SpendWiseColors.expense,
    );

    final base = ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: SpendWiseColors.background,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      dividerColor: SpendWiseColors.border,
      textTheme: base.textTheme.copyWith(
        displaySmall: const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.2,
        ),
        headlineSmall: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -.5,
        ),
        titleLarge: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        titleMedium: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        bodyMedium: const TextStyle(fontSize: 14, height: 1.35),
        bodySmall: const TextStyle(
          fontSize: 12,
          height: 1.35,
          color: SpendWiseColors.textSecondary,
        ),
        labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: SpendWiseColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 20,
        titleTextStyle: TextStyle(
          color: Color(0xFFEAF2EE),
          fontSize: 21,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: const CardThemeData(
        color: SpendWiseColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          side: BorderSide(color: SpendWiseColors.border),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: SpendWiseColors.surface,
        hintStyle: TextStyle(color: SpendWiseColors.textSecondary),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: SpendWiseColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: SpendWiseColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: SpendWiseColors.accent, width: 1.5),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xFF0A1014),
        indicatorColor: SpendWiseColors.accentMuted,
        height: 72,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 50),
          side: const BorderSide(color: SpendWiseColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: SpendWiseColors.surface,
        selectedColor: SpendWiseColors.accentMuted,
        side: const BorderSide(color: SpendWiseColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
