import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/ground.dart';
import 'package:spendwise/app/palette.dart';

/// The palette that exists for one job the other four cannot do.
///
/// Sage, Ink, Brass and Tide are moods, and each draws its ramp from a narrow
/// slice of the wheel — right for a shape with two branches in it, wrong the
/// moment a category breakdown asks the eye to hold eight tones at once and
/// match each one to a row beneath it. Orchard's argument is hue spread, so
/// that is what is asserted here rather than that it looks nice.
///
/// The shared guards in `contrast_floor_test.dart`, `category_tones_test.dart`
/// and `paper_relight_matches_the_exporter_test.dart` already walk every
/// palette including this one; this file only holds the claim that makes
/// this one worth shipping.
void main() {
  double hueOf(Color color) => HSLColor.fromColor(color).hue;

  /// Degrees between two hues the short way round the wheel.
  double apart(double a, double b) {
    final gap = (a - b).abs() % 360;
    return gap > 180 ? 360 - gap : gap;
  }

  test('no two tones in the ramp are neighbours on the wheel', () {
    final hues = SpendWisePalette.orchard.ramp.map(hueOf).toList();
    // The last rung is a near-grey by design — the "everything else" tone —
    // so its hue carries no meaning and is excluded from the spread claim.
    final coloured = hues.take(7).toList();
    for (var i = 0; i < coloured.length; i++) {
      for (var j = i + 1; j < coloured.length; j++) {
        expect(
          apart(coloured[i], coloured[j]),
          greaterThan(18),
          reason:
              'ramp[$i] and ramp[$j] sit within 18° of each other, which at '
              'the width of a bar is one colour',
        );
      }
    }
  });

  test('it spreads further than the palette it was added beside', () {
    double spread(SpendWisePalette palette) {
      final hues = palette.ramp.take(7).map(hueOf).toList();
      var widest = 0.0;
      for (var i = 0; i < hues.length; i++) {
        for (var j = i + 1; j < hues.length; j++) {
          final gap = apart(hues[i], hues[j]);
          if (gap > widest) widest = gap;
        }
      }
      return widest;
    }

    expect(
      spread(SpendWisePalette.orchard),
      greaterThan(spread(SpendWisePalette.tide)),
      reason:
          'Tide was already the most colourful; this has to beat it or '
          'it is a fifth mood rather than an answer',
    );
  });

  test('money in and money out stay the two most separable tones', () {
    // Everything else in the ramp is a name. These two are a direction, and
    // a reader who cannot tell them apart cannot read the shape at all.
    final palette = SpendWisePalette.orchard;
    expect(
      apart(hueOf(palette.keep), hueOf(palette.spend)),
      greaterThan(60),
      reason: 'kept and spent carry the only meaning in the shape',
    );
  });

  test('it is offered, and it survives being relit for paper', () {
    expect(SpendWisePalette.all, contains(SpendWisePalette.orchard));
    expect(SpendWisePalette.byId('orchard'), SpendWisePalette.orchard);

    final paper = SpendWisePalette.orchard.onPaper;
    expect(paper.id, 'orchard');
    for (final tone in [paper.keep, paper.spend, paper.mine, ...paper.ramp]) {
      expect(
        Ground.paper.bg.computeLuminance() - tone.computeLuminance(),
        greaterThan(0),
        reason: 'a tone at least as light as paper is a tone nobody can see',
      );
    }
  });
}
