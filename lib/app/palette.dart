import 'package:flutter/material.dart';

/// The one thing a user can restyle.
///
/// The graphite ground and the typography are the app's identity and never
/// change. What varies is the semantic trio — did the money stay, did it
/// leave, did it only move between your own accounts — plus the category ramp
/// derived from it. Every palette here is low-chroma on a dark ground and
/// tested against the same background, so none of them can make the app ugly:
/// this is a choice of temperament, not a theme engine.
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

  static const all = <SpendWisePalette>[sage, ink, brass, tide, slate];

  static SpendWisePalette byId(String? id) =>
      all.firstWhere((item) => item.id == id, orElse: () => sage);
}
