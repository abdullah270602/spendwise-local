import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/category_tones.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/insights/chronograph.dart';
import 'package:spendwise/features/insights/spending_analytics.dart';

/// Duplicates the geometry `chronograph.dart` builds its ticks from, the same
/// way `flow_shape_flow_and_wobble_test.dart` duplicates the ribbon's own
/// geometry -- so a tap here is aimed at a point provably inside a real
/// wedge, not a guess at where a category "probably" is. The numbers below
/// are the exact ones the finalized design states, not private constants
/// reached into.
const _canvas = 280.0;
const _center = Offset(140, 140);
const _outerRadius = 114.0;
const _hubRadius = 58.0;

Offset _tapFor(int index, int count) {
  final angle = (-90 + index * (360 / count)) * math.pi / 180;
  // Midway between the hub and the rim -- inside every wedge's tappable
  // annulus regardless of how short the tick itself is drawn.
  final radius = (_hubRadius + _outerRadius) / 2;
  return _center + Offset(math.cos(angle), math.sin(angle)) * radius;
}

List<CategoryAnalytics> _categories(List<(String, int)> raw) {
  final total = raw.fold<int>(0, (sum, item) => sum + item.$2);
  return [
    for (final (name, amount) in raw)
      CategoryAnalytics(
        category: name,
        amountMinor: amount,
        fraction: total == 0 ? 0 : amount / total,
      ),
  ];
}

CategoryTones _tones(List<CategoryAnalytics> categories) =>
    CategoryTones.positional([for (final c in categories) c.category]);

Widget _harness({
  required List<CategoryAnalytics> categories,
  String? selected,
  required ValueChanged<String?> onSelect,
  bool reduceMotion = false,
}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reduceMotion),
  child: MaterialApp(
    theme: SpendWiseTheme.dark,
    home: Scaffold(
      body: SingleChildScrollView(
        child: Chronograph(
          categories: categories,
          tones: _tones(categories),
          selected: selected,
          onSelect: onSelect,
          currency: 'PKR',
        ),
      ),
    ),
  ),
);

Finder _dialPaint() => find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint && widget.size == const Size(_canvas, _canvas),
);

void main() {
  group('degenerate counts', () {
    testWidgets('no categories states the heading and a plain message', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(categories: const [], onSelect: (_) {}));
      await tester.pumpAndSettle();

      expect(find.text('WHERE YOUR MONEY WENT'), findsOneWidget);
      expect(
        find.text('Categorised spending will appear here.'),
        findsOneWidget,
      );
      expect(_dialPaint(), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('one category states the figure once, not a dial', (
      tester,
    ) async {
      final categories = _categories([('Groceries', 18500)]);
      await tester.pumpWidget(
        _harness(categories: categories, onSelect: (_) {}),
      );
      await tester.pumpAndSettle();

      expect(find.text('185'), findsOneWidget);
      expect(find.textContaining('100.0% · GROCERIES'), findsOneWidget);
      // A single point cannot show a spread; the floor keeps the dial (and
      // therefore any wedge geometry a tap could land on) off the tree.
      expect(_dialPaint(), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('two categories render the plate, still no dial', (
      tester,
    ) async {
      final categories = _categories([
        ('Groceries', 6000),
        ('Transport', 4000),
      ]);
      String? selected;
      await tester.pumpWidget(
        _harness(
          categories: categories,
          selected: selected,
          onSelect: (value) => selected = value,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Transport'), findsOneWidget);
      expect(_dialPaint(), findsNothing);

      await tester.tap(find.text('Transport'));
      await tester.pumpAndSettle();
      expect(selected, 'Transport');
    });

    testWidgets('twenty-five categories render every row without throwing', (
      tester,
    ) async {
      final categories = _categories([
        for (var i = 0; i < 25; i++) ('Category $i', 25 - i),
      ]);
      await tester.pumpWidget(
        _harness(categories: categories, onSelect: (_) {}),
      );
      await tester.pumpAndSettle();

      expect(_dialPaint(), findsOneWidget);
      for (var i = 0; i < 25; i++) {
        expect(find.text('Category $i'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a category at 0.4% beside one at 23% both render and tap', (
      tester,
    ) async {
      // The design's own skewed stress case: Groceries at 23%, Insurance at
      // 0.4% of the same 100,000 total.
      final categories = _categories([
        ('Groceries', 23000),
        ('Transport', 19000),
        ('Bills', 16000),
        ('Health', 14000),
        ('Shopping', 12500),
        ('Dining', 9500),
        ('Subscriptions', 5600),
        ('Insurance', 400),
      ]);
      expect(categories.first.fraction, closeTo(0.23, 0.001));
      expect(categories.last.fraction, closeTo(0.004, 0.0005));
      String? selected;
      await tester.pumpWidget(
        _harness(categories: categories, onSelect: (value) => selected = value),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final origin = tester.getTopLeft(_dialPaint());
      await tester.tapAt(origin + _tapFor(7, categories.length));
      await tester.pumpAndSettle();
      expect(
        selected,
        'Insurance',
        reason: 'the smallest wedge must still be reachable, floor or not',
      );
    });
  });

  group('tapping the dial', () {
    testWidgets('a tap on a tick reports the right category', (tester) async {
      final categories = _categories([
        ('Groceries', 40),
        ('Transport', 30),
        ('Health', 20),
        ('Shopping', 10),
      ]);
      String? selected;
      await tester.pumpWidget(
        _harness(categories: categories, onSelect: (value) => selected = value),
      );
      await tester.pumpAndSettle();

      final origin = tester.getTopLeft(_dialPaint());
      await tester.tapAt(origin + _tapFor(2, categories.length));
      await tester.pumpAndSettle();

      expect(selected, 'Health');
    });

    testWidgets('a tap on the selected tick clears the filter', (tester) async {
      final categories = _categories([
        ('Groceries', 40),
        ('Transport', 30),
        ('Health', 20),
        ('Shopping', 10),
      ]);
      String? selected = 'Health';
      await tester.pumpWidget(
        _harness(
          categories: categories,
          selected: selected,
          onSelect: (value) => selected = value,
        ),
      );
      await tester.pumpAndSettle();

      final origin = tester.getTopLeft(_dialPaint());
      await tester.tapAt(origin + _tapFor(2, categories.length));
      await tester.pumpAndSettle();

      expect(selected, isNull);
    });

    testWidgets('a plate row toggles the same way a tick does', (tester) async {
      final categories = _categories([
        ('Groceries', 40),
        ('Transport', 30),
        ('Health', 20),
      ]);
      String? selected;
      await tester.pumpWidget(
        _harness(categories: categories, onSelect: (value) => selected = value),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transport'));
      await tester.pumpAndSettle();
      expect(selected, 'Transport');

      await tester.pumpWidget(
        _harness(
          categories: categories,
          selected: selected,
          onSelect: (value) => selected = value,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transport'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
    });

    testWidgets(
      'a selection absent from this period does not throw and reads as zero',
      (tester) async {
        final categories = _categories([
          ('Groceries', 40),
          ('Transport', 30),
          ('Health', 20),
        ]);
        await tester.pumpWidget(
          _harness(
            categories: categories,
            selected: 'Cash Withdrawal',
            onSelect: (_) {},
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('CASH WITHDRAWAL'), findsOneWidget);
      },
    );
  });

  group('selection does not move the dial', () {
    testWidgets(
      'the same screen point resolves to the same category whether or not a filter is already active',
      (tester) async {
        final categories = _categories([
          ('Groceries', 40),
          ('Transport', 30),
          ('Health', 20),
          ('Shopping', 10),
        ]);

        String? selectedA;
        await tester.pumpWidget(
          _harness(
            categories: categories,
            onSelect: (value) => selectedA = value,
          ),
        );
        await tester.pumpAndSettle();
        final originA = tester.getTopLeft(_dialPaint());
        final point = _tapFor(3, categories.length);
        await tester.tapAt(originA + point);
        await tester.pumpAndSettle();
        expect(selectedA, 'Shopping');

        String? selectedB;
        await tester.pumpWidget(
          _harness(
            categories: categories,
            selected: 'Groceries',
            onSelect: (value) => selectedB = value,
          ),
        );
        await tester.pumpAndSettle();
        final originB = tester.getTopLeft(_dialPaint());
        await tester.tapAt(originB + point);
        await tester.pumpAndSettle();

        expect(
          selectedB,
          'Shopping',
          reason:
              'tick geometry is built from unfiltered fractions only -- an '
              'active filter must dim and thicken ticks, never relocate them',
        );
      },
    );
  });

  group('motion', () {
    testWidgets('reduced motion renders the settled frame with no needle', (
      tester,
    ) async {
      final categories = _categories([
        ('Groceries', 40),
        ('Transport', 30),
        ('Health', 20),
      ]);
      await tester.pumpWidget(
        _harness(categories: categories, onSelect: (_) {}, reduceMotion: true),
      );
      // A single pump, deliberately not pumpAndSettle -- the point of
      // reduced motion is that the entrance never runs at all, not merely
      // that it runs quickly.
      await tester.pump();

      final paint = tester.widget<CustomPaint>(_dialPaint());
      final description = '${paint.painter}';
      expect(description, contains('reduce: true'));
      expect(description, contains('entryValue: 1.0'));
    });

    testWidgets(
      'full motion starts below its settled value on the first frame',
      (tester) async {
        final categories = _categories([
          ('Groceries', 40),
          ('Transport', 30),
          ('Health', 20),
        ]);
        await tester.pumpWidget(
          _harness(categories: categories, onSelect: (_) {}),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final paint = tester.widget<CustomPaint>(_dialPaint());
        final match = RegExp(r'entryValue: ([0-9.]+)')
            .firstMatch('${paint.painter}');
        final entryValue = double.parse(match!.group(1)!);
        expect(
          entryValue,
          lessThan(1.0),
          reason: 'the entrance is still running, not skipped',
        );

        await tester.pumpAndSettle();
        final settled = tester.widget<CustomPaint>(_dialPaint());
        expect('${settled.painter}', contains('entryValue: 1.0'));
      },
    );
  });

  group('360px phone', () {
    void phoneSized(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    testWidgets('the fourteen-category baseline survives a real phone width', (
      tester,
    ) async {
      phoneSized(tester);
      final categories = _categories([
        ('Groceries', 39650),
        ('Bills & Utilities', 27200),
        ('Transport', 19850),
        ('Dining Out', 16700),
        ('Health', 13100),
        ('Shopping', 11400),
        ('Subscriptions', 8950),
        ('Self Care', 7600),
        ('Education', 6300),
        ('Travel', 5200),
        ('Gifts & Charity', 3700),
        ('Bank Fees', 2650),
        ('Cash Withdrawal', 1980),
        ('Insurance', 690),
      ]);
      await tester.pumpWidget(
        _harness(
          categories: categories,
          selected: 'Bills & Utilities',
          onSelect: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Bills & Utilities'), findsOneWidget);
    });
  });
}
