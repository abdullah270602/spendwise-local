import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/ground.dart';
import 'package:spendwise/app/palette.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/widgets/shape_kit.dart';
import 'package:spendwise/widgets/spendwise_components.dart';

/// What a light mode breaks that nothing else in the app does.
///
/// A `CustomPainter` repaints only when its `shouldRepaint` says to, and every
/// painter here was written when there was exactly one ground and one set of
/// colours to draw on it. So not one of them compared a colour, and five
/// returned `false` outright — correct, for as long as the colours could not
/// change while a screen was on it.
///
/// Flipping the phone to light mode with Home open changes that. Every widget
/// around the ribbon relights and the ribbon itself keeps painting graphite
/// onto paper, because nothing it was given has changed. A user reads that as
/// a broken app, not as a setting, and it is close to impossible to attribute:
/// the setting worked, the theme worked, one layer of one screen did not.
///
/// These three tests are the whole guard. The first says the mechanism works,
/// the second says it is wired into the painters that exist, and the third
/// says a painter added later cannot quietly skip it.
void main() {
  tearDown(
    () => SpendWiseColors.apply(SpendWisePalette.sage, on: Ground.graphite),
  );

  testWidgets(
    'a painter built on one ground repaints when it is asked to draw on another',
    (tester) async {
      // Three real painters, reached through the three widgets that are public:
      // the Home ribbon, the balance line, and the app's own mark.
      Future<List<CustomPainter>> pump(Ground on) async {
        SpendWiseColors.apply(SpendWisePalette.sage, on: on);
        await tester.pumpWidget(
          MaterialApp(
            theme: on.isLight ? SpendWiseTheme.light : SpendWiseTheme.dark,
            home: Scaffold(
              body: Column(
                children: [
                  FlowShape(
                    receivedMinor: 400000,
                    keptMinor: 250000,
                    spentMinor: 150000,
                    animate: false,
                  ),
                  BalanceLine(points: const [10, 40, 30, 90, 70]),
                  SpendWiseMark(size: 24),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((paint) => paint.painter)
            .whereType<CustomPainter>()
            .toList();
      }

      final onGraphite = await pump(Ground.graphite);
      final onPaper = await pump(Ground.paper);

      expect(
        onGraphite.length,
        onPaper.length,
        reason:
            'the same widgets were pumped twice, so the same painters should '
            'have been built — pair them by position below',
      );
      expect(onGraphite, isNotEmpty);

      for (var i = 0; i < onGraphite.length; i++) {
        final before = onGraphite[i];
        final after = onPaper[i];
        expect(
          after.runtimeType,
          before.runtimeType,
          reason: 'painter $i changed type between the two pumps',
        );
        expect(
          after.shouldRepaint(before),
          isTrue,
          reason:
              '${after.runtimeType} was built on paper, was handed the painter '
              'that drew it on graphite, and said nothing needed redrawing — '
              'which leaves the old pixels on screen',
        );
      }
    },
  );

  test('a painter that has not moved is still left alone', () {
    // The other half of the contract, and the one a blunt `=> true` would
    // break: repainting every painter on every frame is not a fix, it is a
    // different bug with no visible symptom.
    SpendWiseColors.apply(SpendWisePalette.sage, on: Ground.graphite);
    final first = _Probe();
    final second = _Probe();
    expect(second.shouldRepaint(first), isFalse);

    SpendWiseColors.apply(SpendWisePalette.tide, on: Ground.graphite);
    expect(
      _Probe().shouldRepaint(first),
      isTrue,
      reason:
          'the palette moved without the ground moving, which is the same '
          'fault with a rarer trigger',
    );
  });

  test('every CustomPainter in the app is ground-aware', () {
    // Read as source rather than by reflection: the painters are private to
    // their files, most of them are unreachable without pumping the screen
    // that owns them, and the thing worth asserting is a property of the
    // codebase — that nobody writes the thirteenth painter without this.
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in RegExp(
        r'class\s+(\w+)\s+extends\s+CustomPainter\b([^{]*)\{',
      ).allMatches(source)) {
        if (!match.group(2)!.contains('GroundAware')) {
          offenders.add('${match.group(1)} in ${file.path}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'these painters draw with SpendWiseColors and will not notice the '
          'ground changing under them: ${offenders.join(', ')}',
    );
  });
}

/// A painter that does nothing except carry the mixin, so the contract can be
/// checked without pumping a screen.
class _Probe extends CustomPainter with GroundAware {
  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(_Probe old) => groundMoved(old);
}
