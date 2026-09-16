import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/ground.dart';
import 'package:spendwise/app/palette.dart';
import 'package:spendwise/app/theme.dart';

/// Fifty-five colours per ground, and no one looking at all of them.
///
/// Every palette in this app was written against one background, and the doc
/// comment on `palette.dart` said so: low-chroma on a dark ground, "tested
/// against the same background, so none of them can make the app ugly". A
/// second ground voids that guarantee for every tone at once, and the failure
/// it produces is not a crash or a wrong number — it is a category label that
/// is merely hard to read, on a palette the author does not use, in a month
/// with enough categories to reach it. Nobody reports that. They just stop
/// using the palette.
///
/// So the ratios are computed here, from the WCAG formula written out below
/// rather than borrowed from the code being checked, and asserted against
/// floors rather than against remembered hexes. The point is the floor: a
/// sixth palette added in a year cannot land under it without this failing and
/// naming the tone.
///
/// The floors differ by ground, and deliberately. Paper is new and is held to
/// AA for body text throughout, which its relight guarantees by construction.
/// Graphite shipped years ago carrying two semantic tones under 4.5:1 — Slate's
/// `mine` at 3.90 and Brass's `spend` at 4.35 — and one ramp slot per palette
/// that is a deliberate near-ground grey for "everything else". Relighting is
/// not the moment to restyle the ground that already works without being
/// asked, so graphite is held to the large-text floor and its last ramp slot
/// is named as the exception rather than quietly skipped.
void main() {
  tearDown(() => SpendWiseColors.apply(SpendWisePalette.sage, on: Ground.graphite));

  /// WCAG 2.1, written out rather than imported: a contrast test that shares
  /// its arithmetic with the thing it is testing proves only that the code
  /// agrees with itself.
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();

  double luminance(Color colour) =>
      0.2126 * channel(colour.r) +
      0.7152 * channel(colour.g) +
      0.0722 * channel(colour.b);

  double ratio(Color a, Color b) {
    final first = luminance(a), second = luminance(b);
    return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
  }

  /// Every tone a palette carries, named, as that ground actually draws it.
  Map<String, Color> tonesOn(Ground ground, SpendWisePalette palette) {
    final drawn = ground.isLight ? palette.onPaper : palette;
    return {
      'keep': drawn.keep,
      'spend': drawn.spend,
      'mine': drawn.mine,
      for (var i = 0; i < drawn.ramp.length; i++) 'ramp ${i + 1}': drawn.ramp[i],
    };
  }

  test('body text clears AA on both grounds', () {
    for (final ground in Ground.all) {
      expect(
        ratio(ground.fg, ground.bg),
        greaterThanOrEqualTo(4.5),
        reason: '${ground.id}: primary text',
      );
      expect(
        ratio(ground.dim, ground.bg),
        greaterThanOrEqualTo(4.5),
        reason:
            '${ground.id}: secondary text — this is what every date, account '
            'number and axis label in the app is drawn in',
      );
      expect(
        ratio(ground.warning, ground.bg),
        greaterThanOrEqualTo(4.5),
        reason:
            '${ground.id}: the amber that means "this needs attention" has to '
            'be readable to mean it',
      );
    }
  });

  test('on paper, every tone in every palette clears the 4.5:1 body floor', () {
    final failures = <String>[];
    for (final palette in SpendWisePalette.all) {
      tonesOn(Ground.paper, palette).forEach((name, tone) {
        final measured = ratio(tone, Ground.paper.bg);
        if (measured < 4.5) {
          failures.add(
            '${palette.name} $name ${_hex(tone)} at '
            '${measured.toStringAsFixed(2)}:1',
          );
        }
      });
    }
    expect(
      failures,
      isEmpty,
      reason:
          'the relight is supposed to make this impossible, so a tone here '
          'means the floor was bypassed or a hand-built palette was added '
          'without one: ${failures.join(' · ')}',
    );
  });

  test('on graphite, every tone clears the 3:1 large floor bar the last ramp slot', () {
    final failures = <String>[];
    for (final palette in SpendWisePalette.all) {
      tonesOn(Ground.graphite, palette).forEach((name, tone) {
        // Slot 8 is the ramp's deliberate near-ground grey — "and the rest".
        // It measures 2.20 to 2.47 across the five palettes and has done since
        // the palettes were drawn. It is recorded here at its own floor rather
        // than excluded, so that it cannot get quietly worse either.
        final floor = name == 'ramp 8' ? 2.0 : 3.0;
        final measured = ratio(tone, Ground.graphite.bg);
        if (measured < floor) {
          failures.add(
            '${palette.name} $name ${_hex(tone)} at '
            '${measured.toStringAsFixed(2)}:1, under $floor',
          );
        }
      });
    }
    expect(failures, isEmpty, reason: failures.join(' · '));
  });

  test('a category past the end of the ramp never fades into paper', () {
    // The fault this is named after: `category()`'s alpha floor is written to
    // stop a long list fading into its ground, and on paper the identical code
    // caused that exact fade — slot 33 fell from 3.31:1 on graphite to 1.50:1.
    // Sixty-four slots is eight laps, well past any plausible ledger.
    SpendWiseColors.apply(SpendWisePalette.sage, on: Ground.paper);
    for (final palette in SpendWisePalette.all) {
      SpendWiseColors.apply(palette, on: Ground.paper);
      for (var slot = 0; slot < 64; slot++) {
        expect(
          ratio(SpendWiseColors.category(slot), Ground.paper.bg),
          greaterThanOrEqualTo(3.0),
          reason:
              '${palette.name} category $slot is ${_hex(SpendWiseColors.category(slot))}, '
              'which is a wash on paper',
        );
      }
    }
  });

  test('the Home ribbon keeps its separation when the ground goes light', () {
    // The second inversion, and the one a person would call "washed out"
    // without being able to say why. `FlowShape` fills the kept branch at 0.30
    // and the spent branch at 0.48, and a partial alpha walks a tone toward
    // whatever is behind it -- on graphite that is away from the text, on
    // paper it is straight at it. Same numbers, opposite direction: the kept
    // branch falls from 1.81:1 to 1.48:1, a fifth of its presence.
    //
    // The alphas therefore belong to the ground, and paper's are the ones that
    // put both branches back where graphite has them. Neither pair clears
    // WCAG 1.4.11 and neither is meant to: the legend states both figures in
    // words and the opaque feet carry the picture. These are shading. What
    // matters is that the shading is the same amount of shading on both
    // grounds, which is what this computes.
    Color composited(Color tone, double alpha, Ground ground) =>
        Color.alphaBlend(tone.withValues(alpha: alpha), ground.bg);

    final sage = SpendWisePalette.sage;
    final paperSage = sage.onPaper;

    final branches = <String, List<double>>{
      'kept': [
        ratio(
          composited(sage.keep, Ground.graphite.keptBranchAlpha, Ground.graphite),
          Ground.graphite.bg,
        ),
        ratio(
          composited(paperSage.keep, Ground.paper.keptBranchAlpha, Ground.paper),
          Ground.paper.bg,
        ),
      ],
      'spent': [
        ratio(
          composited(sage.spend, Ground.graphite.spentBranchAlpha, Ground.graphite),
          Ground.graphite.bg,
        ),
        ratio(
          composited(paperSage.spend, Ground.paper.spentBranchAlpha, Ground.paper),
          Ground.paper.bg,
        ),
      ],
    };

    branches.forEach((branch, measured) {
      expect(
        measured[1],
        closeTo(measured[0], 0.05),
        reason:
            'the $branch branch reads at ${measured[0].toStringAsFixed(2)}:1 '
            'on graphite and ${measured[1].toStringAsFixed(2)}:1 on paper — '
            'the ground changed how much of the shape you can see',
      );
    });

    // And the alphas really are per-ground rather than one number used twice,
    // which is the fault this replaced.
    expect(
      Ground.paper.keptBranchAlpha,
      isNot(Ground.graphite.keptBranchAlpha),
    );
    expect(
      Ground.paper.spentBranchAlpha,
      isNot(Ground.graphite.spentBranchAlpha),
    );
  });

  test('Slate still reads from weight rather than hue once it is on paper', () {
    // Slate's blurb is the specification: "Direction reads from weight, not
    // hue." Its three graphite tones sit 0.306 apart in lightness, and the
    // relight's 0.40 cap — which every one of them is above — flattens that to
    // 0.000, leaving three greys a person cannot tell apart. The hex values
    // are not the assertion; the spread is, because the spread is the palette.
    double spread(SpendWisePalette palette) {
      final lightnesses = [palette.keep, palette.spend, palette.mine]
          .map((tone) => HSLColor.fromColor(tone).lightness)
          .toList();
      return lightnesses.reduce(math.max) - lightnesses.reduce(math.min);
    }

    final graphite = spread(SpendWisePalette.slate);
    final paper = spread(SpendWisePalette.slate.onPaper);
    expect(graphite, greaterThan(0.25), reason: 'the graphite ladder');
    expect(
      paper,
      greaterThan(0.15),
      reason:
          'paper allows less room than graphite before a tone stops clearing '
          'AA, so the ladder is shorter — but it is still a ladder, and '
          '0.000 would mean the palette had stopped existing',
    );

    // And it runs the other way, for the same reason it runs the way it does
    // on graphite: the tone that carries the most has to be furthest from the
    // ground, and the ground has moved to the opposite end.
    final light = SpendWisePalette.slate.onPaper;
    expect(
      HSLColor.fromColor(light.keep).lightness,
      lessThan(HSLColor.fromColor(light.mine).lightness),
      reason: 'on paper `keep` has to be the darkest of the three',
    );
    expect(
      HSLColor.fromColor(SpendWisePalette.slate.keep).lightness,
      greaterThan(HSLColor.fromColor(SpendWisePalette.slate.mine).lightness),
      reason: 'on graphite it is the lightest',
    );
  });

  test('no palette loses its whole identity to the relight', () {
    // Slate is the one the cap destroys, and it is hand-built because of it.
    // The other four are derived, and this is what says the derivation has not
    // quietly flattened one of them too.
    for (final palette in SpendWisePalette.all) {
      final drawn = palette.onPaper;
      expect(
        {drawn.keep, drawn.spend, drawn.mine}.length,
        3,
        reason:
            '${palette.name}: two of the three semantic tones came out of the '
            'relight identical, so the app can no longer say which happened',
      );
    }
  });
}

String _hex(Color colour) =>
    '#${(colour.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
