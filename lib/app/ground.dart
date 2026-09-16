import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG 2.1 relative luminance.
double relativeLuminance(Color colour) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(colour.r) +
      0.7152 * channel(colour.g) +
      0.0722 * channel(colour.b);
}

/// WCAG 2.1 contrast ratio, 1.0 (identical) to 21.0 (black on white).
double contrastRatio(Color a, Color b) {
  final first = relativeLuminance(a);
  final second = relativeLuminance(b);
  final lighter = math.max(first, second);
  final darker = math.min(first, second);
  return (lighter + 0.05) / (darker + 0.05);
}

/// The surface the whole app is drawn on, and every value the surface decides.
///
/// SpendWise had one ground for its entire life, so the ground's colours were
/// five constants and the numbers derived from them were literals scattered
/// across the widgets that used them. Two grounds turns each of those into a
/// question with two answers, and the ones that matter are not the obvious
/// ones: a translucent fill and an alpha floor both *reverse direction* when
/// the ground goes light, because partial alpha walks a tone toward whatever
/// is behind it. On graphite that is away from the text; on paper it is
/// straight at it.
///
/// Gathering them here is what keeps that honest. Everything on this class is
/// a property of the surface, so adding a third ground is a matter of
/// answering the same questions again rather than of hunting for literals.
@immutable
final class Ground {
  const Ground({
    required this.id,
    required this.brightness,
    required this.bg,
    required this.fg,
    required this.dim,
    required this.line,
    required this.edge,
    required this.raised,
    required this.accentMuted,
    required this.warning,
    required this.keptBranchAlpha,
    required this.spentBranchAlpha,
    required this.savedBranchAlpha,
    required this.seamAlpha,
  });

  final String id;
  final Brightness brightness;

  /// Everything sits on this; there is no second surface colour.
  final Color bg;

  /// Primary text and the only "solid block" fill.
  final Color fg;

  /// Secondary text, axis labels, metadata.
  final Color dim;

  /// Hairline between rows -- barely there on purpose.
  final Color line;

  /// Visible edge: borders that must read as a boundary.
  final Color edge;

  /// The one panel fill that is not the ground, used by Notification sources.
  final Color raised;

  /// A pale wash of the accent. Legacy; kept so the alias still resolves.
  final Color accentMuted;

  /// Amber. Not a palette tone: it means "this needs attention" and must not
  /// move when the user restyles what money did.
  final Color warning;

  /// How solid the Home ribbon's four fills are drawn.
  ///
  /// These invert. On graphite a partial alpha walks the tone toward
  /// near-black -- away from the pale text -- and the branch gains presence;
  /// the kept branch measures 1.81:1 against the ground at 0.30. On paper the
  /// same 0.30 walks the same branch toward the ground and it measures
  /// 1.48:1, a fifth of its separation gone. 0.44 and 0.51 are the alphas
  /// that put the kept and spent branches back at graphite's exact numbers,
  /// 1.82:1 and 2.20:1. The two `mine` branches barely move -- computed at
  /// 0.33 and 0.29 against graphite's 0.34 and 0.30 -- but they live here
  /// too, because "it happened not to matter for this tone" is not a reason
  /// to leave a literal somewhere a third ground would not find it.
  final double keptBranchAlpha;
  final double spentBranchAlpha;
  final double savedBranchAlpha;
  final double seamAlpha;

  bool get isLight => brightness == Brightness.light;

  /// The ground the app has always had: near-black, signed off in
  /// `design/shape.html`.
  static const graphite = Ground(
    id: 'graphite',
    brightness: Brightness.dark,
    bg: Color(0xFF0F1113),
    fg: Color(0xFFE9E7E2),
    dim: Color(0xFF7A8084),
    line: Color(0xFF1C2023),
    edge: Color(0xFF282D31),
    raised: Color(0xFF15181B),
    accentMuted: Color(0xFF1A2321),
    warning: Color(0xFFC9A45A),
    keptBranchAlpha: .30,
    spentBranchAlpha: .48,
    savedBranchAlpha: .34,
    seamAlpha: .30,
  );

  /// Warm paper: the ground the app already prints on.
  ///
  /// `0xFFFAF9F6` and `0xFF17191A` are `_paper` and `_ink` from
  /// `lib/features/reports/spending_report.dart`, byte for byte, and `dim` is
  /// its `_muted`. This is the whole argument for choosing it over a pure
  /// white or a cool grey: anybody who has opened a SpendWise PDF has already
  /// seen this ground carrying this typography, so a light screen is the app
  /// agreeing with its own export rather than becoming a second product.
  static const paper = Ground(
    id: 'paper',
    brightness: Brightness.light,
    bg: Color(0xFFFAF9F6),
    fg: Color(0xFF17191A),
    dim: Color(0xFF6B7176),
    line: Color(0xFFE8E6DF),
    edge: Color(0xFFD2CFC6),
    raised: Color(0xFFF2F0EA),
    accentMuted: Color(0xFFE5EBE6),
    // Relit like every other tone, then darkened until it clears 4.5:1: the
    // amber that reads as a warning on graphite is 2.2:1 on paper, which is
    // decoration rather than a warning.
    warning: Color(0xFF926C20),
    keptBranchAlpha: .44,
    spentBranchAlpha: .51,
    savedBranchAlpha: .33,
    seamAlpha: .29,
  );

  static const all = <Ground>[graphite, paper];

  static Ground of(Brightness brightness) =>
      brightness == Brightness.light ? paper : graphite;
}
