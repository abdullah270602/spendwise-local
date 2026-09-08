import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/widgets/shape_kit.dart';

/// The category breakdown bar used to redraw itself outright the moment a
/// weight changed -- a category taking a bigger bite of the month appeared
/// rather than grew, while the ribbon above it was already travelling on the
/// same figures. Now a segment moves the same way that ribbon does.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool reduceMotion = false,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: MaterialApp(
          theme: SpendWiseTheme.dark,
          // A fixed width so the pixel target a weight resolves to is
          // arithmetic, not whatever the test surface happens to measure.
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 300, child: child),
            ),
          ),
        ),
      ),
    );
  }

  // Two segments, a 2px gap between them: 298 logical pixels to divide.
  const rentShare = 238.4; // 298 * 0.8
  const foodShare = 59.6; // 298 * 0.2

  List<double> widthsOn(WidgetTester tester) => tester
      .widgetList<SizedBox>(
        find.descendant(
          of: find.byType(SegmentBar),
          matching: find.byType(SizedBox),
        ),
      )
      // The bar's own outer SizedBox (its fixed height) and the gap between
      // segments are SizedBoxes too; only an animated segment pairs its width
      // with the ColoredBox it is colouring.
      .where((box) => box.child is ColoredBox)
      .map((box) => box.width!)
      .toList();

  double widthOf(WidgetTester tester, String id) => tester
      .widget<SizedBox>(
        find.descendant(
          // `SegmentBar.ids` is typed `List<Object>?`, so the key it builds
          // is a `ValueKey<Object>` even for a caller passing strings --
          // `ValueKey`'s equality checks `runtimeType`, so matching it here
          // with a bare `ValueKey<String>` would never find it.
          of: find.byKey(ValueKey<Object>(id)),
          matching: find.byType(SizedBox),
        ),
      )
      .width!;

  Widget bar(List<double> weights) => SegmentBar(
    key: const ValueKey('bar'),
    weights: weights,
    colors: [SpendWiseColors.keep, SpendWiseColors.spend],
  );

  testWidgets('a segment travels to its new width instead of jumping to it', (
    tester,
  ) async {
    await pump(tester, bar(const [0.8, 0.2]));
    await tester.pumpAndSettle();
    expect(widthsOn(tester)[0], closeTo(rentShare, 0.5));

    // The same two categories, a month later, with the split reversed.
    await pump(tester, bar(const [0.2, 0.8]));
    await tester.pump(const Duration(milliseconds: 400));

    final travelling = widthsOn(tester)[0];
    expect(travelling, lessThan(rentShare), reason: 'it has left where it was');
    expect(
      travelling,
      greaterThan(foodShare),
      reason: 'and has not arrived yet -- if it had, it jumped',
    );

    await tester.pumpAndSettle();
    expect(widthsOn(tester)[0], closeTo(foodShare, 0.5));
  });

  testWidgets('and arrives at once when motion is turned off', (tester) async {
    await pump(tester, bar(const [0.8, 0.2]), reduceMotion: true);
    await tester.pump();
    await pump(tester, bar(const [0.2, 0.8]), reduceMotion: true);
    await tester.pump();

    expect(widthsOn(tester)[0], closeTo(foodShare, 0.5));
  });

  testWidgets('a segment keeps its own target when rank swaps, rather than the '
      'position it moved into', (tester) async {
    Widget idBar(List<double> weights, List<String> ids) => SegmentBar(
      weights: weights,
      colors: [SpendWiseColors.keep, SpendWiseColors.spend],
      ids: ids,
    );

    await pump(tester, idBar(const [0.8, 0.2], const ['rent', 'food']));
    await tester.pumpAndSettle();
    expect(widthOf(tester, 'rent'), closeTo(rentShare, 0.5));
    expect(widthOf(tester, 'food'), closeTo(foodShare, 0.5));

    // Food overtook rent this month -- the same two categories, reordered,
    // because the list is sorted largest first.
    await pump(tester, idBar(const [0.8, 0.2], const ['food', 'rent']));
    await tester.pump(const Duration(milliseconds: 400));

    // Rent is travelling down toward its own new share. Without the id,
    // its Element would have stayed at position 0 and its colour would
    // have snapped straight to food's, mid-slide, while the width kept
    // easing toward a target that was never rent's.
    final rentTravelling = widthOf(tester, 'rent');
    expect(rentTravelling, lessThan(rentShare));
    expect(rentTravelling, greaterThan(foodShare));

    await tester.pumpAndSettle();
    expect(widthOf(tester, 'rent'), closeTo(foodShare, 0.5));
    expect(widthOf(tester, 'food'), closeTo(rentShare, 0.5));
  });
}
