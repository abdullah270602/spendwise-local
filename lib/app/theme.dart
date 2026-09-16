import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ground.dart';
import 'palette.dart';

/// The palette is the one signed off in `design/shape.html`: three semantic
/// hues that each answer a single question -- did the money stay (keep), did
/// it leave (spend), or did it only move between accounts the user already
/// owns (mine). Nothing else in the app is allowed to carry colour.
///
/// What they are drawn on is a [Ground], and there are two: the graphite the
/// app was designed in and the warm paper it already exports to. Everything
/// below is that pair of choices -- palette and ground -- flattened into the
/// statics widgets read, because a screen asking "which ground am I on" at
/// every call site is a worse app than a screen that is simply repainted.
abstract final class SpendWiseColors {
  /// Ground. Everything sits on this; there is no second surface colour.
  ///
  /// Not const, and neither are the four below it. They were, for as long as
  /// the app had exactly one ground; a light mode gives it two, and a value
  /// baked into a `const` expression at every call site cannot be swapped at
  /// runtime.
  static Color bg = Ground.graphite.bg;

  /// Primary text and the only "solid block" fill.
  static Color fg = Ground.graphite.fg;

  /// Secondary text, axis labels, metadata.
  static Color dim = Ground.graphite.dim;

  /// Hairline between rows -- barely there on purpose.
  static Color line = Ground.graphite.line;

  /// Visible edge: borders that must read as a boundary.
  static Color edge = Ground.graphite.edge;

  /// Money that stayed: income, balances, the kept share of the month.
  static Color keep = SpendWisePalette.sage.keep;

  /// Money that left.
  static Color spend = SpendWisePalette.sage.spend;

  /// Money that moved between the user's own accounts.
  static Color mine = SpendWisePalette.sage.mine;

  /// The palette the user chose, always in its graphite form.
  ///
  /// The graphite form is the identity -- it is what the picker names and
  /// what is stored -- so this stays canonical whichever ground is in force,
  /// and [lit] is how a screen asks for the version actually being drawn.
  static SpendWisePalette palette = SpendWisePalette.sage;

  /// The ground in force.
  static Ground ground = Ground.graphite;

  /// What is currently being drawn with, as one comparable value.
  ///
  /// Derived rather than incremented, because [apply] runs on every
  /// `MaterialApp` rebuild and a counter would tell every painter in the app
  /// that its colours had moved several times a second. Ground and palette
  /// between them decide every colour on this class, so their two ids decide
  /// this.
  static int get stamp => Object.hash(ground.id, palette.id);

  /// [of] as it is drawn on the ground in force.
  static SpendWisePalette lit(SpendWisePalette of) =>
      ground.isLight ? of.onPaper : of;

  /// Repaint everything. Either argument may be left out to keep what is
  /// already in force, which is what lets the palette picker and the
  /// brightness picker call the same method without knowing about each other.
  static void apply(SpendWisePalette? next, {Ground? on}) {
    palette = next ?? palette;
    ground = on ?? ground;
    final drawn = lit(palette);
    keep = drawn.keep;
    spend = drawn.spend;
    mine = drawn.mine;
    categoryRamp = drawn.ramp;
    bg = ground.bg;
    fg = ground.fg;
    dim = ground.dim;
    line = ground.line;
    edge = ground.edge;
    surfaceRaised = ground.raised;
    accentMuted = ground.accentMuted;
    warning = ground.warning;
    _laps.clear();
  }

  /// Ordered ramp for spending categories. Read in order; index wraps.
  /// Deliberately low-chroma so a chart of eight categories still reads as one
  /// object rather than a bag of highlighter pens.
  static List<Color> categoryRamp = SpendWisePalette.sage.ramp;

  static final Map<int, Color> _laps = {};

  /// A tone for the nth category, distinct past the end of the ramp.
  ///
  /// The ramp is eight colours. Home only ever draws six, so wrapping was
  /// unreachable there -- but Insights now draws every category a person has,
  /// and a ledger with nine reached the ninth by handing it the first colour
  /// again. Two categories drawn identically, distinguished only by their
  /// position in a list, is the chart disagreeing with itself.
  ///
  /// Each lap past the ramp steps the tone down, so the ninth is the first at
  /// reduced weight rather than the first over again -- and never so far down
  /// that it fades into the ground it is drawn on. *How* you stop it fading
  /// is the part that inverts, and [_recede] is where that lives.
  static Color category(int index) {
    final i = index.abs();
    final lap = i ~/ categoryRamp.length;
    final base = categoryRamp[i % categoryRamp.length];
    if (lap == 0) return base;
    return _laps[i] ??= _recede(base, lap);
  }

  /// One lap's worth of "the same tone, carrying less".
  ///
  /// Hue rotates on both grounds and never clamps, which is what keeps sixty
  /// four categories distinct: fading alone hit a floor, and slot 32 came out
  /// byte-identical to slot 24 -- the exact collision the lap was added to
  /// prevent, moved eight places along rather than removed.
  ///
  /// The receding is the half that inverts. On graphite the tone is drawn at
  /// reducing alpha, floored at 0.48 "so a very long list never fades into
  /// the ground it is drawn on", and that holds: lap 4 still measures 3.31:1.
  /// On paper the identical code does the thing its own comment forbids,
  /// because 0.48 of a dark tone on a light ground is 52% of the ground --
  /// lap 4 measures 1.50:1, and every lap past it is a wash. The floor was
  /// never really about alpha; it was about contrast, and alpha was only how
  /// you spent it on a ground whose luminance is near zero.
  ///
  /// So on paper the tone recedes by lightening instead, and stops at the
  /// last step that still clears 3:1 against the ground -- which is what
  /// graphite's alpha floor actually delivers. Measured across all five
  /// palettes and all sixty-four slots, the worst paper tone is 3.00:1.
  static Color _recede(Color base, int lap) {
    final hsl = HSLColor.fromColor(base);
    final rotated = hsl.withHue((hsl.hue + lap * 10.8) % 360);
    if (!ground.isLight) {
      return rotated.toColor().withValues(
        alpha: math.max(0.48, 1 - lap * 0.16),
      );
    }
    var lightness = math.min(1.0, rotated.lightness + lap * 0.04);
    while (lightness > 0 &&
        contrastRatio(rotated.withLightness(lightness).toColor(), ground.bg) <
            _paperLapFloor) {
      lightness = math.max(0, lightness - 0.005);
    }
    return rotated.withLightness(lightness).toColor();
  }

  /// The contrast a receded category tone keeps on paper. Not
  /// [paperBodyFloor]: a lap-4 tone is the thirty-third category in a ledger,
  /// drawn as a fill with its name beside it, and graphite's own floor
  /// delivers 3.31:1 there -- so this is parity with the ground that shipped,
  /// not a new standard invented for the new one.
  static const _paperLapFloor = 3.0;

  // ---- Legacy aliases -------------------------------------------------
  // Kept so screens still being migrated keep compiling; they resolve to the
  // new palette, so nothing renders in the old colours.
  static Color get background => bg;
  static Color get surface => bg;
  static Color surfaceRaised = Ground.graphite.raised;
  static Color get border => edge;
  static Color get accent => keep;
  static Color accentMuted = Ground.graphite.accentMuted;
  static Color get income => keep;
  static Color get expense => spend;
  static Color warning = Ground.graphite.warning;
  static Color get textSecondary => dim;
}

/// A painter that notices the ground moving under it.
///
/// A `CustomPainter` repaints when `shouldRepaint` says so, and every painter
/// in this app was written against the only ground there was -- so not one of
/// them compared a colour, and five of them returned `false` outright. That
/// was correct while the colours could not change mid-frame. It stopped being
/// correct the moment a person could flip the phone to light mode with Home
/// on screen: the widgets around the ribbon would relight and the ribbon
/// itself would sit there in graphite, which reads as a rendering bug rather
/// than as a setting.
///
/// Mixing this in adds the one comparison every one of them was missing. It
/// covers a palette change too, which was the same latent fault with a rarer
/// trigger.
mixin GroundAware on CustomPainter {
  final int groundStamp = SpendWiseColors.stamp;

  /// True when [old] was painted with colours that are no longer in force.
  bool groundMoved(CustomPainter old) =>
      old is! GroundAware || old.groundStamp != groundStamp;
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

  static TextStyle get body => TextStyle(
    fontFamily: sans,
    fontSize: 14,
    height: 1.45,
    color: SpendWiseColors.dim,
  );

  /// Uppercase tracked eyebrow, e.g. SEPTEMBER / WHAT HAPPENED TO IT.
  static TextStyle get eyebrow => TextStyle(
    fontFamily: sans,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 2.0,
    height: 1.3,
    color: SpendWiseColors.dim,
  );

  /// Data, not prose: day headers, account digits, evidence text.
  static TextStyle get meta => TextStyle(
    fontFamily: mono,
    fontSize: 11,
    letterSpacing: .5,
    height: 1.4,
    color: SpendWiseColors.dim,
  );

  static TextStyle get metaTight => TextStyle(
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

  /// The app on graphite.
  ///
  /// Still called `dark` rather than `graphite` or `onGround`: it is named at
  /// around a hundred call sites across forty-nine test files, and a rename
  /// would be a hundred edits that leave every one of them saying exactly
  /// what it says now.
  static ThemeData get dark => _themeFor(Ground.graphite);

  /// The app on warm paper.
  static ThemeData get light => _themeFor(Ground.paper);

  /// Building a theme applies its ground first, deliberately.
  ///
  /// A `ThemeData` is only half of how this app is coloured -- the other half
  /// is the `SpendWiseColors` statics that widgets and painters read directly,
  /// and the two disagreeing is a screen with paper text on a graphite ground
  /// or the reverse. Tying them together here means there is no order to get
  /// right: whoever asks for a theme gets the statics that go with it, and
  /// `MaterialApp` asking again on every rebuild is idempotent.
  static ThemeData _themeFor(Ground on) {
    SpendWiseColors.apply(null, on: on);
    final scheme = ColorScheme(
      brightness: on.brightness,
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
      brightness: on.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: SpendWiseColors.bg,
      fontFamily: SpendWiseType.sans,
      useMaterial3: true,
    );

    return base.copyWith(
      dividerColor: SpendWiseColors.line,
      dividerTheme: DividerThemeData(
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
      appBarTheme: AppBarTheme(
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
      cardTheme: CardThemeData(
        color: SpendWiseColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: SpendWiseColors.edge),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: SpendWiseColors.dim,
        titleTextStyle: SpendWiseType.row,
        subtitleTextStyle: SpendWiseType.meta,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      inputDecorationTheme: InputDecorationTheme(
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
          side: BorderSide(color: SpendWiseColors.edge),
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
        side: BorderSide(color: SpendWiseColors.edge),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        labelStyle: const TextStyle(
          fontFamily: SpendWiseType.sans,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: SpendWiseType.sans,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: SpendWiseColors.bg,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: SpendWiseColors.bg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: SpendWiseColors.edge),
        ),
        titleTextStyle: SpendWiseType.lead,
        contentTextStyle: SpendWiseType.body,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: SpendWiseColors.bg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        dragHandleColor: SpendWiseColors.edge,
      ),
      snackBarTheme: SnackBarThemeData(
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
        trackOutlineColor: WidgetStatePropertyAll(SpendWiseColors.edge),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: SpendWiseColors.keep,
        linearTrackColor: SpendWiseColors.line,
      ),
    );
  }
}
