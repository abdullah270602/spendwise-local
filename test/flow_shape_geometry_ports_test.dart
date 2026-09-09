import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `SpendWiseHomeWidgetRenderer.kt` draws the Home-screen widget's shape by
/// re-implementing the static case of `_buildFlowGeometry` in Kotlin --
/// `reveal` fixed at 1, no wobble -- because the widget's process cannot
/// reach the ledger, let alone a live Flutter render of it. That is a second
/// implementation of one geometry, and the two are free to drift the moment
/// someone tunes a curve here without knowing the other file exists.
///
/// This test is what makes keeping two copies survivable: it reads both
/// files back as plain text, pulls the seven constants each one names, and
/// fails the build the moment they stop agreeing -- turning a silent visual
/// drift into a loud, specific failure naming exactly which constant moved.
/// It cannot run the Kotlin code (this suite has no JVM), so it is not a
/// substitute for looking at the widget on a device; it only guarantees that
/// if the numbers disagree, nobody finds out from a screenshot six months
/// from now.
void main() {
  test('the widget renderer\'s constants match shape_kit.dart\'s, name for name', () {
    final dartFile = File('lib/widgets/shape_kit.dart');
    final kotlinFile = File(
      'android/app/src/main/kotlin/com/spendwise/app/'
      'SpendWiseHomeWidgetRenderer.kt',
    );
    expect(dartFile.existsSync(), isTrue, reason: dartFile.path);
    expect(kotlinFile.existsSync(), isTrue, reason: kotlinFile.path);

    final dartSource = dartFile.readAsStringSync();
    final kotlinSource = kotlinFile.readAsStringSync();

    double dartConst(String name) {
      final match = RegExp('const $name = ([\\d.]+);').firstMatch(dartSource);
      expect(
        match,
        isNotNull,
        reason: 'expected `const $name = ...;` in ${dartFile.path}',
      );
      return double.parse(match!.group(1)!);
    }

    double kotlinConst(String name) {
      final match = RegExp('$name = ([\\d.]+)f').firstMatch(kotlinSource);
      expect(
        match,
        isNotNull,
        reason: 'expected `$name = ...f` in ${kotlinFile.path}',
      );
      return double.parse(match!.group(1)!);
    }

    // (Dart name, Kotlin name) pairs -- see the comment above
    // `_buildFlowGeometry` in shape_kit.dart and the class comment on
    // SpendWiseHomeWidgetRenderer for why these seven, and only these
    // seven, are the geometry's whole contract. `siblingGapDp` joined the
    // other six when the widget took on drawing the "siblings" style's
    // third branch -- the gap between the kept and saved footings is as
    // much a part of "the same shape" as the curve itself.
    const pairs = {
      'barH': 'BAR_HEIGHT_DP',
      'topY': 'TOP_Y_DP',
      'topWidthFraction': 'TOP_WIDTH_FRACTION',
      'marginFraction': 'MARGIN_FRACTION',
      'control1Fraction': 'CONTROL_1_FRACTION',
      'control2Fraction': 'CONTROL_2_FRACTION',
      'siblingGapDp': 'SIBLING_GAP_DP',
    };

    for (final entry in pairs.entries) {
      expect(
        kotlinConst(entry.value),
        dartConst(entry.key),
        reason:
            'shape_kit.dart\'s `${entry.key}` and SpendWiseHomeWidgetRenderer.kt\'s '
            '`${entry.value}` have to be the same number -- one is the '
            'geometry Home actually draws, the other is the widget\'s copy '
            'of it.',
      );
    }
  });
}
