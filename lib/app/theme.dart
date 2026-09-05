import 'package:flutter/material.dart';

/// The palette is the one signed off in `design/shape.html`: a graphite ground
/// with three semantic hues that each answer a single question -- did the money
/// stay (keep), did it leave (spend), or did it only move between accounts the
/// user already owns (mine). Nothing else in the app is allowed to carry colour.
abstract final class SpendWiseColors {
  /// Ground. Everything sits on this; there is no second surface colour.
  static const bg = Color(0xFF0F1113);

  /// Primary text and the only "solid block" fill.
  static const fg = Color(0xFFE9E7E2);

  /// Secondary text, axis labels, metadata.
  static const dim = Color(0xFF767C80);

  /// Hairline between rows -- barely there on purpose.
  static const line = Color(0xFF1C2023);

  /// Visible edge: borders that must read as a boundary.
  static const edge = Color(0xFF282D31);

  /// Money that stayed: income, balances, the kept share of the month.
  static const keep = Color(0xFF9FB2AC);

  /// Money that left.
  static const spend = Color(0xFFC97A5A);

  /// Money that moved between the user's own accounts.
  static const mine = Color(0xFF6E8496);

  /// Ordered ramp for spending categories. Read in order; index wraps.
  /// Deliberately low-chroma so a chart of eight categories still reads as one
  /// object rather than a bag of highlighter pens.
  static const categoryRamp = <Color>[
    Color(0xFFC97A5A), // clay
    Color(0xFFA98D6B), // sand
    Color(0xFF6E8496), // slate
    Color(0xFF7E7A96), // mauve
    Color(0xFF9FB2AC), // sage
    Color(0xFFB08A7E), // rose clay
    Color(0xFF8A9A7B), // olive
    Color(0xFF4A5054), // graphite
  ];

  static Color category(int index) =>
      categoryRamp[index.abs() % categoryRamp.length];

  // ---- Legacy aliases -------------------------------------------------
  // Kept so screens still being migrated keep compiling; they resolve to the
  // new palette, so nothing renders in the old colours.
  static const background = bg;
  static const surface = bg;
  static const surfaceRaised = Color(0xFF15181B);
  static const border = edge;
  static const accent = keep;
  static const accentMuted = Color(0xFF1A2321);
  static const income = keep;
  static const expense = spend;
  static const warning = Color(0xFFC9A45A);
  static const textSecondary = dim;
}

/// Type is the other half of the identity: Archivo set tight and heavy for
/// figures, JetBrains Mono for anything the user reads as data rather than
/// prose (dates, evidence, account digits, axis ticks).
abstract final class SpendWiseType {
  static const sans = 'Archivo';
  static const mono = 'JetBrainsMono';

  /// The one big number on a screen (total tracked, a rule's count).
  static const figure = TextStyle(
    fontFamily: sans,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.2,
    height: 1.05,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Screen-opening statement ("14 alerts, 2 decisions.").
  static const statement = TextStyle(
    fontFamily: sans,
    fontSize: 27,
    fontWeight: FontWeight.w700,
    letterSpacing: -.7,
    height: 1.2,
  );

  /// A month name, a screen title.
  static const title = TextStyle(
    fontFamily: sans,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -.6,
    height: 1.15,
  );

  /// Legend values on Home, balances in a block.
  static const amount = TextStyle(
    fontFamily: sans,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -.5,
    height: 1.15,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Lead line inside a card or rule.
  static const lead = TextStyle(
    fontFamily: sans,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -.2,
    height: 1.35,
  );

  /// Register rows, block names -- the densest readable size.
  static const row = TextStyle(fontFamily: sans, fontSize: 15, height: 1.25);

  static const rowStrong = TextStyle(
    fontFamily: sans,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.25,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const body = TextStyle(
    fontFamily: sans,
    fontSize: 14,
    height: 1.45,
    color: SpendWiseColors.dim,
  );

  /// Uppercase tracked eyebrow, e.g. SEPTEMBER / WHAT HAPPENED TO IT.
  static const eyebrow = TextStyle(
    fontFamily: sans,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 2.0,
    height: 1.3,
    color: SpendWiseColors.dim,
  );

  /// Data, not prose: day headers, account digits, evidence text.
  static const meta = TextStyle(
    fontFamily: mono,
    fontSize: 11,
    letterSpacing: .5,
    height: 1.4,
    color: SpendWiseColors.dim,
  );

  static const metaTight = TextStyle(
    fontFamily: mono,
    fontSize: 10,
    letterSpacing: 1.4,
    height: 1.3,
    color: SpendWiseColors.dim,
  );
}

abstract final class SpendWiseTheme {
  /// Horizontal page gutter. Every screen uses this and only this.
  static const gutter = 22.0;

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: SpendWiseColors.fg,
      onPrimary: SpendWiseColors.bg,
      secondary: SpendWiseColors.keep,
      onSecondary: SpendWiseColors.bg,
      surface: SpendWiseColors.bg,
      onSurface: SpendWiseColors.fg,
      error: SpendWiseColors.spend,
      onError: SpendWiseColors.bg,
      outline: SpendWiseColors.edge,
      outlineVariant: SpendWiseColors.line,
    );

    final base = ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: SpendWiseColors.bg,
      fontFamily: SpendWiseType.sans,
      useMaterial3: true,
    );

    return base.copyWith(
      dividerColor: SpendWiseColors.line,
      dividerTheme: const DividerThemeData(
        color: SpendWiseColors.line,
        thickness: 1,
        space: 1,
      ),
      textTheme: base.textTheme.copyWith(
        displaySmall: SpendWiseType.figure,
        headlineMedium: SpendWiseType.statement,
        headlineSmall: SpendWiseType.title,
        titleLarge: SpendWiseType.title,
        titleMedium: SpendWiseType.lead,
        bodyLarge: SpendWiseType.row,
        bodyMedium: SpendWiseType.body.copyWith(color: SpendWiseColors.fg),
        bodySmall: SpendWiseType.body,
        labelLarge: const TextStyle(
          fontFamily: SpendWiseType.sans,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        labelSmall: SpendWiseType.metaTight,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: SpendWiseColors.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: SpendWiseColors.fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: gutter,
        titleTextStyle: TextStyle(
          fontFamily: SpendWiseType.sans,
          color: SpendWiseColors.fg,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -.4,
        ),
      ),
      // Cards are square-cornered outlines, never raised panels: the design
      // reads as printed matter, and a rounded radius on every block is what
      // made the old build read as a generic app.
      cardTheme: const CardThemeData(
        color: SpendWiseColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: SpendWiseColors.edge),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: SpendWiseColors.dim,
        titleTextStyle: SpendWiseType.row,
        subtitleTextStyle: SpendWiseType.meta,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: false,
        hintStyle: TextStyle(color: SpendWiseColors.dim),
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: SpendWiseColors.edge),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: SpendWiseColors.edge),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: SpendWiseColors.fg, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: SpendWiseColors.bg,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: 62,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 21,
            color: states.contains(WidgetState.selected)
                ? SpendWiseColors.fg
                : SpendWiseColors.dim,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: SpendWiseType.sans,
            fontSize: 10,
            letterSpacing: .3,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? SpendWiseColors.fg
                : SpendWiseColors.dim,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SpendWiseColors.fg,
          foregroundColor: SpendWiseColors.bg,
          minimumSize: const Size(48, 48),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle: const TextStyle(
            fontFamily: SpendWiseType.sans,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SpendWiseColors.fg,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: SpendWiseColors.edge),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle: const TextStyle(
            fontFamily: SpendWiseType.sans,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SpendWiseColors.keep,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle: const TextStyle(
            fontFamily: SpendWiseType.sans,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: SpendWiseColors.bg,
        selectedColor: SpendWiseColors.fg,
        checkmarkColor: SpendWiseColors.bg,
        side: const BorderSide(color: SpendWiseColors.edge),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        labelStyle: const TextStyle(
          fontFamily: SpendWiseType.sans,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          fontFamily: SpendWiseType.sans,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: SpendWiseColors.bg,
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: SpendWiseColors.bg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: SpendWiseColors.edge),
        ),
        titleTextStyle: SpendWiseType.lead,
        contentTextStyle: SpendWiseType.body,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: SpendWiseColors.bg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        dragHandleColor: SpendWiseColors.edge,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: SpendWiseColors.fg,
        contentTextStyle: TextStyle(
          fontFamily: SpendWiseType.sans,
          color: SpendWiseColors.bg,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? SpendWiseColors.bg
              : SpendWiseColors.dim,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? SpendWiseColors.keep
              : Colors.transparent,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(SpendWiseColors.edge),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: SpendWiseColors.keep,
        linearTrackColor: SpendWiseColors.line,
      ),
    );
  }
}
