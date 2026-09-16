import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ground.dart';

/// The lowest contrast a tone a person reads as text may have against the
/// paper ground: WCAG AA for body copy.
///
/// It is a floor on the *light* palettes only. The graphite ones shipped
/// years ago with two tones under it (Slate's `mine` at 3.90:1, Brass's
/// `spend` at 4.35:1) and relighting is not the moment to restyle them
/// without being asked.
const paperBodyFloor = 4.5;

/// A dark-ground tone, capped for paper.
///
/// This is `paperTone` from `lib/features/reports/spending_report.dart`, line
/// for line, minus the conversion to a `PdfColor`. It is repeated rather than
/// shared because the exporter is correct as it stands and is not a file this
/// change is allowed to edit; `paper_relight_matches_the_exporter_test.dart`
/// reads both and fails if they ever stop agreeing.
Color paperCap(Color source) {
  final hsl = HSLColor.fromColor(source);
  final lightness = math.min(hsl.lightness, 0.40);
  final saturation = (hsl.saturation * 1.25).clamp(0.0, 1.0);
  return hsl.withLightness(lightness).withSaturation(saturation).toColor();
}

/// A dark-ground tone, re-lit for paper and then made legible on it.
///
/// The cap alone leaves five of the fifty-five tones short of AA against
/// `Ground.paper.bg`: Brass's `keep` at 4.11:1, its ramp's fifth and seventh
/// at 3.88 and 4.08, and Tide's `keep` and second ramp slot at 3.74 and 4.47.
/// Each of those could be hand-picked, and the design note that chose this
/// ground proposes exactly that. Walking the lightness down until the tone
/// clears the floor lands on the same five tones and no others, costs six
/// lines, and means the sixth palette somebody adds cannot arrive under AA
/// without anyone noticing -- which is the whole failure this is guarding.
Color relitForPaper(Color source) {
  var hsl = HSLColor.fromColor(paperCap(source));
  while (hsl.lightness > 0 &&
      contrastRatio(hsl.toColor(), Ground.paper.bg) < paperBodyFloor) {
    hsl = hsl.withLightness(math.max(0, hsl.lightness - 0.005));
  }
  return hsl.toColor();
}

/// The one thing a user can restyle.
///
/// The graphite ground and the typography are the app's identity and never
/// change. What varies is the semantic trio — did the money stay, did it
/// leave, did it only move between your own accounts — plus the category ramp
/// derived from it. Every palette here is low-chroma on a dark ground and
/// tested against the same background, so none of them can make the app ugly:
/// this is a choice of temperament, not a theme engine.
///
/// "The same background" is what a light mode takes away, so each palette now
/// has a twin: [onPaper], relit through [relitForPaper]. The twin is derived
/// rather than declared, except for Slate, which the derivation destroys --
/// see [slateOnPaper].
@immutable
final class SpendWisePalette {
  const SpendWisePalette({
    required this.id,
    required this.name,
    required this.blurb,
    required this.keep,
    required this.spend,
    required this.mine,
    required this.ramp,
  });

  final String id;
  final String name;

  /// One line in the picker, so the choice reads as a mood rather than a swatch.
  final String blurb;

  final Color keep;
  final Color spend;
  final Color mine;
  final List<Color> ramp;

  /// The default. Sage and clay on graphite — the palette the app was drawn in.
  static const sage = SpendWisePalette(
    id: 'sage',
    name: 'Sage & clay',
    blurb: 'The original. Quiet green, warm terracotta.',
    keep: Color(0xFF9FB2AC),
    spend: Color(0xFFC97A5A),
    mine: Color(0xFF6E8496),
    ramp: [
      Color(0xFFC97A5A),
      Color(0xFFA98D6B),
      Color(0xFF6E8496),
      Color(0xFF7E7A96),
      Color(0xFF9FB2AC),
      Color(0xFFB08A7E),
      Color(0xFF8A9A7B),
      Color(0xFF4A5054),
    ],
  );

  /// Cool and clinical: paper-white kept, cold red spent.
  static const ink = SpendWisePalette(
    id: 'ink',
    name: 'Ink & vermilion',
    blurb: 'Near-monochrome, with one red that only means money leaving.',
    keep: Color(0xFFCBD2D6),
    spend: Color(0xFFC85A4F),
    mine: Color(0xFF7C8894),
    ramp: [
      Color(0xFFC85A4F),
      Color(0xFF9A7A72),
      Color(0xFF7C8894),
      Color(0xFF8E8296),
      Color(0xFFCBD2D6),
      Color(0xFFB0645C),
      Color(0xFF7F8A80),
      Color(0xFF4A5054),
    ],
  );

  /// Warm and analogue: brass kept, rust spent.
  static const brass = SpendWisePalette(
    id: 'brass',
    name: 'Brass & rust',
    blurb: 'Warm throughout. Reads like an old ledger under a lamp.',
    keep: Color(0xFFC2A878),
    spend: Color(0xFFB4643C),
    mine: Color(0xFF8A7F6B),
    ramp: [
      Color(0xFFB4643C),
      Color(0xFFC2A878),
      Color(0xFF8A7F6B),
      Color(0xFF9C7B5C),
      Color(0xFFD3BE93),
      Color(0xFFA5563A),
      Color(0xFF8F8455),
      Color(0xFF544E45),
    ],
  );

  /// Deep water: teal kept, coral spent.
  static const tide = SpendWisePalette(
    id: 'tide',
    name: 'Tide',
    blurb: 'Cool teal against coral. The most colour of the four.',
    keep: Color(0xFF6FB2A8),
    spend: Color(0xFFD2775F),
    mine: Color(0xFF6E8DA8),
    ramp: [
      Color(0xFFD2775F),
      Color(0xFFC2996B),
      Color(0xFF6E8DA8),
      Color(0xFF8B85A8),
      Color(0xFF6FB2A8),
      Color(0xFFBE8074),
      Color(0xFF7FA184),
      Color(0xFF46565C),
    ],
  );

  /// One hue, two ends: nothing but slate and the absence of it.
  static const slate = SpendWisePalette(
    id: 'slate',
    name: 'Slate',
    blurb: 'Almost no colour at all. Direction reads from weight, not hue.',
    keep: Color(0xFFB9C2C6),
    spend: Color(0xFF8C949A),
    mine: Color(0xFF69737A),
    ramp: [
      Color(0xFFB9C2C6),
      Color(0xFF9AA4AA),
      Color(0xFF8C949A),
      Color(0xFF7B848A),
      Color(0xFF69737A),
      Color(0xFFA6B0B5),
      Color(0xFF5C666C),
      Color(0xFF454D52),
    ],
  );

  /// Slate, hand-built for paper rather than derived.
  ///
  /// Slate's entire identity is lightness spread: its blurb says direction
  /// reads from weight, not hue, and its three tones sit 0.306 apart in
  /// lightness on graphite. [paperCap] holds lightness to 0.40, and all three
  /// of Slate's tones are above that, so all three land on 0.40 -- a spread
  /// of 0.000 and three greys nobody can tell apart. The one palette whose
  /// argument is weight is the one palette the relight has nothing to say
  /// about.
  ///
  /// So it is built by hand, and built inverted: on graphite `keep` is the
  /// lightest of the three because light is what separates a tone from a
  /// near-black ground, and on paper it is the darkest for the same reason.
  /// The ladder runs from lightness 0.23 to 0.44 -- narrower than graphite's
  /// 0.306 because paper allows less room before a tone stops clearing AA,
  /// but a real ladder, and in the same order. The ramp mirrors the dark
  /// ramp's own rungs onto that range, so the sixth slot still jumps back
  /// toward the heavy end exactly as it does on graphite.
  static const slateOnPaper = SpendWisePalette(
    id: 'slate',
    name: 'Slate',
    blurb: 'Almost no colour at all. Direction reads from weight, not hue.',
    keep: Color(0xFF333D42),
    spend: Color(0xFF4E595F),
    mine: Color(0xFF677379),
    ramp: [
      Color(0xFF333D42),
      Color(0xFF404B51),
      Color(0xFF475259),
      Color(0xFF4E5A61),
      Color(0xFF566269),
      Color(0xFF3B464B),
      Color(0xFF5D696F),
      Color(0xFF68747B),
    ],
  );

  static const all = <SpendWisePalette>[sage, ink, brass, tide, slate];

  static SpendWisePalette byId(String? id) =>
      all.firstWhere((item) => item.id == id, orElse: () => sage);

  /// This palette as it is drawn on [Ground.paper].
  ///
  /// Cached, because it is asked for on every repaint and the relight walks
  /// a lightness loop per tone.
  SpendWisePalette get onPaper => _paperTwins[id] ??= SpendWisePalette(
    id: id,
    name: name,
    blurb: blurb,
    keep: relitForPaper(keep),
    spend: relitForPaper(spend),
    mine: relitForPaper(mine),
    ramp: [for (final tone in ramp) relitForPaper(tone)],
  );

  static final Map<String, SpendWisePalette> _paperTwins = {
    slate.id: slateOnPaper,
  };
}
