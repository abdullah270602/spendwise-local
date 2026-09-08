import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/category_tones.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/insights/seismograph.dart';
import 'package:spendwise/features/insights/spending_analytics.dart';

/// The Seismograph's whole promise is a *fixed* scale: a category's swing
/// draws at the same pixel deviation whether this was the calmest month on
/// record or the most violent one. The design brief this widget implements
/// found that promise broken in an earlier sketch, which rescaled itself to
/// each render's own loudest category and so made every month look equally
/// busy. These tests are written to have caught that bug.
void main() {
  CategoryAnalytics change({
    required String category,
    required int amountMinor,
    int previousAmountMinor = 0,
  }) => CategoryAnalytics(
    category: category,
    amountMinor: amountMinor,
    previousAmountMinor: previousAmountMinor,
    fraction: 0,
  );

  // Wrapped in the same 22px gutter `InsightsScreen`'s own `SliverPadding`
  // applies on both sides, so a width tested here is the width the widget
  // actually gets in the app, not a looser stand-in for it -- the project
  // has already been burned once by a test that passed at a width the real
  // screen never gives a widget.
  Widget harness({
    required List<CategoryAnalytics> changes,
    String? selected,
    ValueChanged<String?>? onSelect,
    bool reduceMotion = false,
    double width = 360,
  }) {
    final tones = CategoryTones.positional(changes.map((c) => c.category));
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SpendWiseTheme.gutter,
              ),
              child: Seismograph(
                changes: changes,
                tones: tones,
                selected: selected,
                onSelect: onSelect ?? (_) {},
                currency: 'PKR',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder paintFinder() => find.descendant(
    of: find.byType(Seismograph),
    matching: find.byType(CustomPaint),
  );

  // The painter's geometry is private; its `toString` carries the one frame
  // it painted with, the same way `motion_contract_test` and
  // `flow_shape_flow_and_wobble_test` already read `_FlowShapePainter` back.
  String painterText(WidgetTester tester) =>
      '${tester.widget<CustomPaint>(paintFinder()).painter}';

  double field(String text, String name) =>
      double.parse(RegExp('$name: ([-0-9.]+)').firstMatch(text)!.group(1)!);

  group('the fixed scale', () {
    final calm = [
      change(
        category: 'Groceries',
        amountMinor: 40100,
        previousAmountMinor: 40000,
      ),
      change(
        category: 'Transport',
        amountMinor: 15400,
        previousAmountMinor: 15000,
      ),
      change(
        category: 'Dining out',
        amountMinor: 11700,
        previousAmountMinor: 12000,
      ),
      change(category: 'Health', amountMinor: 4150, previousAmountMinor: 4000),
      change(category: 'Bills', amountMinor: 8000, previousAmountMinor: 8000),
    ];
    final violent = [
      change(
        category: 'Groceries',
        amountMinor: 44000,
        previousAmountMinor: 40000,
      ),
      change(
        category: 'Home repairs',
        amountMinor: 3080,
        previousAmountMinor: 140,
      ),
      change(
        category: 'Transport',
        amountMinor: 9000,
        previousAmountMinor: 15000,
      ),
      change(
        category: 'Dining out',
        amountMinor: 20000,
        previousAmountMinor: 12000,
      ),
      change(category: 'Bills', amountMinor: 8000, previousAmountMinor: 8000),
    ];

    testWidgets(
      "a calm month's largest swing is a small fraction of the lane",
      (tester) async {
        await tester.pumpWidget(harness(changes: calm, reduceMotion: true));
        await tester.pump();

        final text = painterText(tester);
        final largest = field(text, 'largestDeviation');
        final lane = field(text, 'maxDeviation');
        expect(
          largest / lane,
          lessThan(0.2),
          reason:
              'the loudest category this month only moved 3.75%, nowhere '
              'near the fixed 260% reference the lane is calibrated to',
        );
      },
    );

    testWidgets(
      "a violent month's clamped swing reaches the lane's edge, at the "
      'same lane width a calm month uses',
      (tester) async {
        await tester.pumpWidget(harness(changes: violent, reduceMotion: true));
        await tester.pump();

        final violentText = painterText(tester);
        final largest = field(violentText, 'largestDeviation');
        final violentLane = field(violentText, 'maxDeviation');
        expect(
          largest / violentLane,
          closeTo(1.0, 0.02),
          reason:
              'Home repairs went from 140 to 3,080, +2100% -- clamped, it '
              'must sit exactly at the lane edge, not stretch the lane to '
              'fit it',
        );

        // Same stage, same widget width, so the lane itself did not move
        // between a calm render and a violent one -- a per-render rescale
        // is exactly the bug this widget exists to not have.
        await tester.pumpWidget(harness(changes: calm, reduceMotion: true));
        await tester.pump();
        final calmLane = field(painterText(tester), 'maxDeviation');
        expect(calmLane, closeTo(violentLane, 0.001));
      },
    );
  });

  group('motion', () {
    final data = [
      change(
        category: 'Groceries',
        amountMinor: 40100,
        previousAmountMinor: 40000,
      ),
      change(
        category: 'Transport',
        amountMinor: 15400,
        previousAmountMinor: 15000,
      ),
      change(
        category: 'Dining out',
        amountMinor: 11700,
        previousAmountMinor: 12000,
      ),
    ];

    testWidgets('draws itself in over time, then settles', (tester) async {
      await tester.pumpWidget(harness(changes: data));
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        field(painterText(tester), 'reveal'),
        lessThan(1.0),
        reason: 'the entrance is still playing',
      );
      await tester.pumpAndSettle();
      expect(field(painterText(tester), 'reveal'), closeTo(1.0, 0.001));
    });

    testWidgets('renders the final frame instantly under reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(harness(changes: data, reduceMotion: true));
      await tester.pump(const Duration(milliseconds: 120));
      expect(field(painterText(tester), 'reveal'), closeTo(1.0, 0.001));
    });
  });

  group('selection', () {
    final data = [
      change(
        category: 'Groceries',
        amountMinor: 40100,
        previousAmountMinor: 40000,
      ),
      change(
        category: 'Transport',
        amountMinor: 15400,
        previousAmountMinor: 15000,
      ),
      change(
        category: 'Dining out',
        amountMinor: 11700,
        previousAmountMinor: 12000,
      ),
    ];

    testWidgets('dims every other row, in place', (tester) async {
      await tester.pumpWidget(harness(changes: data, selected: 'Transport'));
      await tester.pump();

      expect(field(painterText(tester), 'dim'), closeTo(1.0, 0.001));

      final opacities = tester
          .widgetList<AnimatedOpacity>(
            find.descendant(
              of: find.byType(Seismograph),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .map((widget) => widget.opacity)
          .toList();
      expect(
        opacities,
        containsAll(<double>[1.0, 0.30, 0.30]),
        reason:
            'the selected row stays fully bright, every other row dims to '
            '30% -- the whole month never leaves the screen, only its '
            'emphasis moves',
      );
    });

    testWidgets('never removes a row -- the shape stays whole when filtered', (
      tester,
    ) async {
      await tester.pumpWidget(harness(changes: data, selected: 'Transport'));
      await tester.pump();
      for (final row in data) {
        expect(find.text(row.category), findsOneWidget);
      }
    });
  });

  group('per-row hit-testing', () {
    // Four rows chosen so every shape this widget draws is exercised once: a
    // plain rise, a plain fall, a flat diamond sitting on the centre line,
    // and a brand-new category with no honest percentage at all. Coordinates
    // below are the same formulas `seismograph.dart` computes them with,
    // mirrored here the way `flow_shape_flow_and_wobble_test` mirrors
    // `_buildFlowGeometry` -- at this harness's 360px stage, minus the 22px
    // gutter on each side and the 84px names column, the lane is centred at
    // x=116 with a 68px half-width.
    const centerX = 116.0;
    const laneHalfWidth = 68.0;
    const rowHeight = 25.0;
    const topPad = 10.0;

    final rows = [
      // Alpha: +130%. ss(130) / ss(260) == sqrt(0.5), not clamped.
      change(category: 'Alpha', amountMinor: 2300, previousAmountMinor: 1000),
      // Beta: -64%. ss(64) / ss(260) == 8 / sqrt(260).
      change(category: 'Beta', amountMinor: 360, previousAmountMinor: 1000),
      // Gamma: unchanged -- a diamond sitting exactly on the centre line.
      change(category: 'Gamma', amountMinor: 500, previousAmountMinor: 500),
      // Delta: new this period -- no previous total to divide by.
      change(category: 'Delta', amountMinor: 400),
    ];

    final capMagnitude = math.sqrt(260.0);
    final alphaX = centerX + (math.sqrt(130.0) / capMagnitude) * laneHalfWidth;
    final betaX = centerX - (math.sqrt(64.0) / capMagnitude) * laneHalfWidth;
    const gammaX = centerX;
    // Delta's own share of this month's total, against the largest share on
    // screen (Alpha's) -- the same formula `_shapeFor` uses for a new
    // category, since there is no honest percentage to plot instead.
    final deltaShareNorm = math.sqrt((400 / 3560) / (2300 / 3560));
    final deltaX = centerX + 0.5 * (0.3 + 0.7 * deltaShareNorm) * laneHalfWidth;

    double yMidOf(int index) => topPad + index * rowHeight + rowHeight / 2;

    testWidgets('tapping a rising row selects it, tapping it again clears it', (
      tester,
    ) async {
      String? selected;
      await tester.pumpWidget(
        harness(
          changes: rows,
          reduceMotion: true,
          onSelect: (value) => selected = value,
        ),
      );
      await tester.pump();
      final origin = tester.getTopLeft(paintFinder());

      await tester.tapAt(origin + Offset(alphaX, yMidOf(0)));
      expect(selected, 'Alpha');

      // Re-pump with the new selection wired through, the way InsightsScreen
      // itself would after `onSelect` calls `setState`.
      await tester.pumpWidget(
        harness(
          changes: rows,
          selected: selected,
          reduceMotion: true,
          onSelect: (value) => selected = value,
        ),
      );
      await tester.pump();
      await tester.tapAt(origin + Offset(alphaX, yMidOf(0)));
      expect(
        selected,
        isNull,
        reason: 'tapping the selected row again clears it',
      );
    });

    testWidgets('tapping a falling row selects it', (tester) async {
      String? selected;
      await tester.pumpWidget(
        harness(
          changes: rows,
          reduceMotion: true,
          onSelect: (value) => selected = value,
        ),
      );
      await tester.pump();
      final origin = tester.getTopLeft(paintFinder());
      await tester.tapAt(origin + Offset(betaX, yMidOf(1)));
      expect(selected, 'Beta');
    });

    testWidgets('tapping a flat row selects it, even on the centre line', (
      tester,
    ) async {
      String? selected;
      await tester.pumpWidget(
        harness(
          changes: rows,
          reduceMotion: true,
          onSelect: (value) => selected = value,
        ),
      );
      await tester.pump();
      final origin = tester.getTopLeft(paintFinder());
      await tester.tapAt(origin + Offset(gammaX, yMidOf(2)));
      expect(selected, 'Gamma');
    });

    testWidgets('tapping a new category selects it', (tester) async {
      String? selected;
      await tester.pumpWidget(
        harness(
          changes: rows,
          reduceMotion: true,
          onSelect: (value) => selected = value,
        ),
      );
      await tester.pump();
      final origin = tester.getTopLeft(paintFinder());
      await tester.tapAt(origin + Offset(deltaX, yMidOf(3)));
      expect(selected, 'Delta');
    });

    testWidgets('a tap that lands between rows selects nothing', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        harness(changes: rows, reduceMotion: true, onSelect: (_) => calls++),
      );
      await tester.pump();
      final origin = tester.getTopLeft(paintFinder());
      // In the padding beneath the last row -- past every row's own hit
      // region and nowhere near the centre spine either.
      await tester.tapAt(
        origin + const Offset(centerX + 40, topPad * 2 + rowHeight * 4 - 1),
      );
      expect(calls, 0);
    });
  });

  group('degenerate cases', () {
    testWidgets('renders nothing below three categories', (tester) async {
      for (final count in [0, 1, 2]) {
        final data = List.generate(
          count,
          (i) => change(
            category: 'Cat$i',
            amountMinor: 100,
            previousAmountMinor: 90,
          ),
        );
        await tester.pumpWidget(harness(changes: data));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(paintFinder(), findsNothing);
      }
    });

    testWidgets('a fully new month does not throw', (tester) async {
      final data = [
        change(category: 'Alpha', amountMinor: 100),
        change(category: 'Beta', amountMinor: 200),
        change(category: 'Gamma', amountMinor: 300),
      ];
      await tester.pumpWidget(harness(changes: data));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a fully stopped month does not throw', (tester) async {
      final data = [
        change(category: 'Alpha', amountMinor: 0, previousAmountMinor: 100),
        change(category: 'Beta', amountMinor: 0, previousAmountMinor: 200),
        change(category: 'Gamma', amountMinor: 0, previousAmountMinor: 300),
      ];
      await tester.pumpWidget(harness(changes: data));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a completely flat month does not throw', (tester) async {
      final data = [
        change(category: 'Alpha', amountMinor: 100, previousAmountMinor: 100),
        change(category: 'Beta', amountMinor: 200, previousAmountMinor: 200),
        change(category: 'Gamma', amountMinor: 300, previousAmountMinor: 300),
      ];
      await tester.pumpWidget(harness(changes: data));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'twenty-five rows fold the smallest tail into one aggregate row',
      (tester) async {
        final data = [
          for (var i = 0; i < 25; i++)
            change(
              // Largest movement first, matching the order the real
              // analytics layer already sorts `categoryChanges` in.
              category: 'Category $i',
              amountMinor: 1000 - i * 30,
              previousAmountMinor: 500,
            ),
        ];
        await tester.pumpWidget(harness(changes: data));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('more categories'), findsOneWidget);
        expect(
          tester
              .widgetList<AnimatedOpacity>(
                find.descendant(
                  of: find.byType(Seismograph),
                  matching: find.byType(AnimatedOpacity),
                ),
              )
              .length,
          17,
          reason: '16 real rows plus the one folded aggregate row',
        );
      },
    );

    testWidgets(
      'a selected category is promoted out of the folded tail, not hidden',
      (tester) async {
        final data = [
          for (var i = 0; i < 20; i++)
            change(
              category: 'Category $i',
              amountMinor: 1000 - i * 30,
              previousAmountMinor: 500,
            ),
        ];
        // Category 18 ranks below the 16-row fold threshold and would
        // otherwise be summed away into "+4 more categories".
        await tester.pumpWidget(
          harness(changes: data, selected: 'Category 18'),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Category 18'), findsOneWidget);
      },
    );

    testWidgets('does not overflow at a 360px-wide phone', (tester) async {
      final data = [
        for (var i = 0; i < 20; i++)
          change(
            category: 'A rather long category name $i',
            amountMinor: 1000 - i * 20,
            previousAmountMinor: 500 + i,
          ),
      ];
      await tester.pumpWidget(harness(changes: data, width: 360));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
