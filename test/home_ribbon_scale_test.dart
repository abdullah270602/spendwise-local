import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/widgets/shape_kit.dart';

import 'home_categories_honoured_test.dart' as home;

/// With the breakdown hidden the ribbon is the whole of Home, so it takes a
/// share of the screen rather than a fixed number of pixels.
///
/// The bound at the top of that range is not cosmetic. A fixed 210 looked
/// right on one phone and nowhere else, and the first attempt at scaling --
/// half the usable height -- pushed the tray scan clean off a 640dp screen,
/// which is the opposite of where that control belongs.
void main() {
  const devices = [
    ('compact', 360.0, 640.0),
    ('pixel', 360.0, 800.0),
    ('tall', 412.0, 915.0),
  ];

  Future<Rect> shapeOn(
    WidgetTester tester,
    double width,
    double height, {
    String? categories,
  }) async {
    tester.view.physicalSize = Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Scaffold(body: home.buildHome(categories)),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getRect(find.byType(FlowShape));
  }

  testWidgets('the ribbon grows with the screen', (tester) async {
    final small = await shapeOn(tester, 360, 640, categories: 'off');
    final medium = await shapeOn(tester, 360, 800, categories: 'off');
    final large = await shapeOn(tester, 412, 915, categories: 'off');

    expect(medium.height, greaterThan(small.height));
    expect(large.height, greaterThan(medium.height));
  });

  testWidgets('and never so far that the tray scan leaves the screen', (
    tester,
  ) async {
    for (final (name, width, height) in devices) {
      await shapeOn(tester, width, height, categories: 'off');
      final tray = tester.getRect(
        find.ancestor(
          of: find.textContaining('SCAN THE TRAY'),
          matching: find.byType(InkWell),
        ),
      );
      expect(
        tray.bottom,
        lessThanOrEqualTo(height),
        reason: '$name: the one control on Home must stay reachable',
      );
    }
  });

  testWidgets('the breakdown still gets its room when it is drawn', (
    tester,
  ) async {
    // Scaling applies only where the space is genuinely free. With every
    // category listed the ribbon goes back to its ordinary size so the rows
    // beneath it are not pushed off the fold.
    final bare = await shapeOn(tester, 360, 800, categories: 'off');
    final full = await shapeOn(tester, 360, 800, categories: 'all');

    expect(full.height, 168);
    expect(bare.height, greaterThan(full.height));
  });

  testWidgets('a short screen is not given a ribbon it cannot afford', (
    tester,
  ) async {
    // The floor matters as much as the ceiling: below about 190 the curve
    // stops reading as a shape and becomes a stripe.
    final small = await shapeOn(tester, 360, 640, categories: 'off');
    expect(small.height, greaterThanOrEqualTo(190));
    expect(small.height, lessThan(640 * 0.4));
  });
}
