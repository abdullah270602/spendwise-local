import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/category_tones.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/insights/gate.dart';
import 'package:spendwise/features/insights/spending_analytics.dart';

/// The Gate exists to say "the money moved further than usual", and the one
/// way to get that wrong is to let a percentage speak for itself: a Rs 350
/// category that becomes Rs 900 is a "huge" +157%, and a Rs 41,000 category
/// that becomes Rs 47,500 is a "modest" +15.9%, but the second move is twelve
/// times the money. These tests hold the two-part rule -- corridor and
/// materiality floor, both required -- to real numbers, not to the rule's own
/// description of itself.
void main() {
  CategoryAnalytics change({
    required String category,
    required int now,
    required int prev,
  }) => CategoryAnalytics(
    category: category,
    amountMinor: now,
    previousAmountMinor: prev,
    fraction: 0,
  );

  Future<void> pumpGate(
    WidgetTester tester, {
    required List<CategoryAnalytics> changes,
    required GateSensitivity sensitivity,
    required int totalSpendingMinor,
    String? selected,
    ValueChanged<String?>? onSelect,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: SpendWiseTheme.dark,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SpendWiseTheme.gutter,
          ),
          child: Gate(
            changes: changes,
            tones: CategoryTones.positional(changes.map((c) => c.category)),
            sensitivity: sensitivity,
            totalSpendingMinor: totalSpendingMinor,
            selected: selected,
            onSelect: onSelect ?? (_) {},
            currency: 'PKR',
          ),
        ),
      ),
    ),
  );

  double topOf(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  group('the two-part rule', () {
    testWidgets(
      'a tiny category with a huge percentage swing stays quiet, while a '
      'large category with a modest percentage clears both bars',
      (tester) async {
        // Parking: +157% but only Rs 550 of real money -- the exact shape of
        // category the materiality floor exists to catch.
        final categories = [
          change(category: 'Utilities', now: 126000, prev: 100000), // +26%
          change(category: 'Parking', now: 900, prev: 350), // +157%
        ];
        // 1% of 140,000 is 1,400: past Parking's Rs 550 move, short of
        // Utilities' Rs 26,000 one.
        await pumpGate(
          tester,
          changes: categories,
          sensitivity: GateSensitivity.balanced,
          totalSpendingMinor: 140000,
        );
        await tester.pumpAndSettle();

        expect(find.text('WHAT MOVED'), findsOneWidget);
        final loudHead = topOf(tester, 'WHAT MOVED');
        final quietHead = topOf(tester, 'HELD STEADY');
        final utilities = topOf(tester, 'Utilities');
        final parking = topOf(tester, 'Parking');

        expect(
          utilities,
          allOf(greaterThan(loudHead), lessThan(quietHead)),
          reason: 'Utilities clears both the corridor and the floor',
        );
        expect(
          parking,
          greaterThan(quietHead),
          reason:
              "Parking's move is real in percent but not in money, and the "
              'floor is what is supposed to catch that',
        );
      },
    );

    testWidgets('a zero-money category never reads as loud', (tester) async {
      final categories = [
        change(category: 'Subscriptions', now: 9880, prev: 9880),
      ];
      await pumpGate(
        tester,
        changes: categories,
        sensitivity: GateSensitivity.everything,
        totalSpendingMinor: 9880,
      );
      await tester.pumpAndSettle();

      expect(find.text('HELD STEADY'), findsOneWidget);
      expect(
        topOf(tester, 'Subscriptions'),
        greaterThan(topOf(tester, 'HELD STEADY')),
      );
    });
  });

  group('new and stopped categories', () {
    testWidgets('are named instead of quoting a percentage', (tester) async {
      final categories = [
        change(category: 'Vending & snacks', now: 2600, prev: 0),
        change(category: 'Streaming bundle', now: 0, prev: 3400),
        change(category: 'Groceries', now: 41000, prev: 39500),
      ];
      await pumpGate(
        tester,
        changes: categories,
        sensitivity: GateSensitivity.balanced,
        totalSpendingMinor: 80000,
      );
      await tester.pumpAndSettle();

      expect(find.text('New'), findsOneWidget);
      expect(find.text('Stopped'), findsOneWidget);

      // Both cleared the 1%-of-80,000 = 800 floor by a wide margin, and
      // neither has an honest percentage to be held to a corridor, so both
      // are loud regardless of which sensitivity is chosen.
      final loudHead = topOf(tester, 'WHAT MOVED');
      final quietHead = topOf(tester, 'HELD STEADY');
      expect(
        topOf(tester, 'Vending & snacks'),
        allOf(greaterThan(loudHead), lessThan(quietHead)),
      );
      expect(
        topOf(tester, 'Streaming bundle'),
        allOf(greaterThan(loudHead), lessThan(quietHead)),
      );
    });
  });

  group('both empty extremes', () {
    testWidgets('everything holding steady is stated, not left blank', (
      tester,
    ) async {
      final categories = [
        change(category: 'Groceries', now: 40000, prev: 39500),
        change(category: 'Transport', now: 15000, prev: 14800),
      ];
      await pumpGate(
        tester,
        changes: categories,
        sensitivity: GateSensitivity.balanced,
        totalSpendingMinor: 55000,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Nothing moved more than usual this period.'),
        findsOneWidget,
      );
      expect(find.text('WHAT MOVED'), findsNothing);
      expect(find.text('HELD STEADY'), findsOneWidget);
    });

    testWidgets('everything moving is stated, not left blank', (tester) async {
      final categories = [
        change(category: 'Groceries', now: 80000, prev: 40000),
        change(category: 'Transport', now: 30000, prev: 15000),
      ];
      await pumpGate(
        tester,
        changes: categories,
        sensitivity: GateSensitivity.balanced,
        totalSpendingMinor: 110000,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Nothing held steady — every category moved this period.'),
        findsOneWidget,
      );
      expect(find.text('HELD STEADY'), findsNothing);
      expect(find.text('WHAT MOVED'), findsOneWidget);
    });
  });

  group('the truncation point', () {
    testWidgets('a long quiet band collapses, and expands on tap', (
      tester,
    ) async {
      final categories = [
        for (var i = 0; i < 10; i++)
          change(category: 'Steady $i', now: 1000 + i, prev: 1000 + i),
      ];
      await pumpGate(
        tester,
        changes: categories,
        sensitivity: GateSensitivity.balanced,
        totalSpendingMinor: 200000, // floor swamps every one of these
      );
      await tester.pumpAndSettle();

      // "Held steady" sorts by current spend descending, so the two rows a
      // truncation point of 8 hides are the smallest, not the last created.
      expect(find.text('+2 more held steady'), findsOneWidget);
      expect(find.text('Steady 0'), findsNothing);
      expect(find.text('Steady 1'), findsNothing);
      expect(find.text('Steady 9'), findsOneWidget);

      await tester.tap(find.text('+2 more held steady'));
      await tester.pumpAndSettle();

      expect(find.text('+2 more held steady'), findsNothing);
      expect(find.text('Steady 0'), findsOneWidget);
      expect(find.text('Steady 1'), findsOneWidget);
    });
  });

  group('sensitivity', () {
    testWidgets(
      'changing it moves a specific row between bands, gliding rather '
      'than snapping',
      (tester) async {
        final categories = [
          change(category: 'Shifter', now: 130000, prev: 100000), // +30%
          change(category: 'Steady', now: 20000, prev: 19800), // ~1%
        ];
        const total = 200000;

        await pumpGate(
          tester,
          changes: categories,
          sensitivity: GateSensitivity.bigMovesOnly, // ±40%
          totalSpendingMinor: total,
        );
        await tester.pumpAndSettle();
        expect(
          topOf(tester, 'Shifter'),
          greaterThan(topOf(tester, 'HELD STEADY')),
          reason: '+30% does not clear a ±40% corridor',
        );
        final quietTop = topOf(tester, 'Shifter');

        await pumpGate(
          tester,
          changes: categories,
          sensitivity: GateSensitivity.balanced, // ±25%
          totalSpendingMinor: total,
        );
        await tester.pump(const Duration(milliseconds: 50));
        final midTop = topOf(tester, 'Shifter');
        expect(
          midTop,
          isNot(closeTo(quietTop, 0.5)),
          reason:
              'it should already be travelling, not waiting to jump once '
              'the animation ends',
        );

        await tester.pumpAndSettle();
        final loudTop = topOf(tester, 'Shifter');
        expect(
          loudTop,
          lessThan(quietTop),
          reason: '+30% clears a ±25% corridor, and the loud band sits above',
        );
        expect(
          midTop,
          allOf(greaterThan(loudTop), lessThan(quietTop)),
          reason: 'a mid-flight frame should sit strictly between the two',
        );
      },
    );

    test('an unrecognised or missing id falls back to balanced', () {
      expect(GateSensitivity.fromId(null), GateSensitivity.balanced);
      expect(GateSensitivity.fromId('nonsense'), GateSensitivity.balanced);
      expect(GateSensitivity.fromId('sensitive'), GateSensitivity.everything);
      expect(GateSensitivity.fromId('coarse'), GateSensitivity.bigMovesOnly);
    });

    test('every level is named and its id is stable for persistence', () {
      expect(GateSensitivity.everything.id, 'sensitive');
      expect(GateSensitivity.balanced.id, 'standard');
      expect(GateSensitivity.bigMovesOnly.id, 'coarse');
      for (final level in GateSensitivity.values) {
        expect(level.title, isNotEmpty, reason: level.id);
      }
    });
  });

  group('selection', () {
    testWidgets('tapping a row selects it, and tapping it again clears it', (
      tester,
    ) async {
      final categories = [
        change(category: 'Health', now: 21400, prev: 8100),
        change(category: 'Groceries', now: 41200, prev: 39000),
      ];
      String? selected;
      await pumpGate(
        tester,
        changes: categories,
        sensitivity: GateSensitivity.balanced,
        totalSpendingMinor: 62600,
        selected: selected,
        onSelect: (value) => selected = value,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Health'));
      expect(selected, 'Health');

      await pumpGate(
        tester,
        changes: categories,
        sensitivity: GateSensitivity.balanced,
        totalSpendingMinor: 62600,
        selected: selected,
        onSelect: (value) => selected = value,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Health'));
      expect(selected, isNull, reason: 'tapping the selected row clears it');
    });
  });

  group('360px', () {
    testWidgets('a crowded board with long names does not overflow', (
      tester,
    ) async {
      // The header on this same screen once overflowed a real 360px phone by
      // 108 pixels and no test noticed, because no test was ever the size of
      // one -- every test ran at the 800x600 default, where almost anything
      // fits.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final categories = [
        for (var i = 0; i < 20; i++)
          change(
            category: 'A rather long invented category name, number $i',
            now: 20000 + i * 733,
            prev: 15000,
          ),
      ];
      await pumpGate(
        tester,
        changes: categories,
        sensitivity: GateSensitivity.balanced,
        totalSpendingMinor: 600000,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final more = find.textContaining('more held steady');
      if (more.evaluate().isNotEmpty) {
        await tester.tap(more.first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await tester.tap(
        find.text('A rather long invented category name, number 0'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('reduced motion', () {
    testWidgets('a crossing settles at once instead of gliding', (
      tester,
    ) async {
      final categories = [
        change(category: 'Shifter', now: 130000, prev: 100000),
      ];
      const total = 200000;

      Future<void> pumpReduced(GateSensitivity sensitivity) =>
          tester.pumpWidget(
            MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: MaterialApp(
                theme: SpendWiseTheme.dark,
                home: Scaffold(
                  body: Gate(
                    changes: categories,
                    tones: CategoryTones.positional(
                      categories.map((c) => c.category),
                    ),
                    sensitivity: sensitivity,
                    totalSpendingMinor: total,
                    selected: null,
                    onSelect: (_) {},
                    currency: 'PKR',
                  ),
                ),
              ),
            ),
          );

      await pumpReduced(GateSensitivity.bigMovesOnly);
      await tester.pump();
      final quietTop = topOf(tester, 'Shifter');

      await pumpReduced(GateSensitivity.balanced);
      await tester.pump();
      final settledTop = topOf(tester, 'Shifter');

      expect(
        settledTop,
        isNot(closeTo(quietTop, 0.5)),
        reason: 'the row already reads as loud on the very next frame',
      );
    });
  });
}
