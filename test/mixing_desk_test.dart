import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/category_tones.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/insights/mixing_desk.dart';
import 'package:spendwise/features/insights/spending_analytics.dart';

/// Invented placeholders throughout -- no real names, no real amounts.
///
/// Builds a category list the shape `SpendingAnalytics.categories` actually
/// takes: largest amount first, fraction computed against the group's own
/// total. Order in the map does not matter; sorting is done here so a test
/// can hand the same set of names two different rankings without having to
/// think about it twice.
List<CategoryAnalytics> _categories(Map<String, int> amounts) {
  final total = amounts.values.fold<int>(0, (sum, value) => sum + value);
  final entries = amounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (final entry in entries)
      CategoryAnalytics(
        category: entry.key,
        amountMinor: entry.value,
        fraction: total == 0 ? 0 : entry.value / total,
      ),
  ];
}

Widget _host(Widget child) => MaterialApp(
  theme: SpendWiseTheme.dark,
  home: Scaffold(body: SafeArea(child: child)),
);

/// Mirrors `_ChannelStrip._hitIndex`'s non-mini branch: equal, contiguous
/// slices across the whole strip. Kept separate from the widget under test
/// on purpose, the same way `flow_shape_flow_and_wobble_test.dart` mirrors
/// `_buildFlowGeometry` rather than reaching into it -- a test that could
/// only ever agree with the code it is checking would not be proving
/// anything.
int _expectedSliceIndex(double dx, double width, int n) =>
    (dx / (width / n)).floor().clamp(0, n - 1);

/// Mirrors the mini branch: fixed-width, centred channels with a blank
/// cheek at each end, nearest-centre wins.
int _expectedMiniIndex(double dx, double width, int n) {
  const cheek = 10.0, channelWidth = 26.0, gap = 16.0;
  final content = 2 * cheek + n * channelWidth + (n - 1) * gap;
  final left = (width - content).clamp(0, double.infinity) / 2 + cheek;
  var best = 0;
  var bestDistance = double.infinity;
  for (var i = 0; i < n; i++) {
    final center = left + i * (channelWidth + gap) + channelWidth / 2;
    final distance = (dx - center).abs();
    if (distance < bestDistance) {
      bestDistance = distance;
      best = i;
    }
  }
  return best;
}

void main() {
  group('channel order is stable, not sorted', () {
    testWidgets('a category keeps its channel number when ranking changes', (
      tester,
    ) async {
      const known = ['Alpha', 'Beta', 'Gamma', 'Delta', 'Epsilon', 'Zeta'];
      final tones = CategoryTones(known: known);
      String? selected;

      final periodA = _categories({
        'Zeta': 6000,
        'Epsilon': 5000,
        'Delta': 4000,
        'Gamma': 3000,
        'Beta': 2000,
        'Alpha': 1000,
      });
      final periodB = _categories({
        'Delta': 9000,
        'Alpha': 8000,
        'Zeta': 700,
        'Beta': 600,
        'Gamma': 500,
        'Epsilon': 400,
      });

      await tester.pumpWidget(
        _host(
          MixingDesk(
            categories: periodA,
            tones: tones,
            selected: selected,
            onSelect: (value) => selected = value,
            currency: 'PKR',
          ),
        ),
      );
      await tester.pumpAndSettle();

      String printedNumber(String category) {
        final finder = find.descendant(
          of: find.byKey(ValueKey('channel-$category')),
          matching: find.textContaining(RegExp(r'^\d{2}$')),
        );
        return tester.widget<Text>(finder).data!;
      }

      final beforeNumbers = {
        for (final name in known) name: printedNumber(name),
      };
      for (final name in known) {
        expect(
          beforeNumbers[name],
          tones.channelOf(name).toString().padLeft(2, '0'),
          reason: '$name should print the stable index, not its rank',
        );
      }

      await tester.pumpWidget(
        _host(
          MixingDesk(
            categories: periodB,
            tones: tones,
            selected: selected,
            onSelect: (value) => selected = value,
            currency: 'PKR',
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final name in known) {
        expect(
          printedNumber(name),
          beforeNumbers[name],
          reason:
              '$name changed its printed channel number when only the '
              'ranking changed, not the category itself',
        );
      }
    });
  });

  group('touch targets', () {
    testWidgets('a tap anywhere in the (non-mini) strip resolves to the '
        'nearest channel', (tester) async {
      const known = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
      final tones = CategoryTones(known: known);
      final categories = _categories({
        'H': 800,
        'G': 700,
        'F': 600,
        'E': 500,
        'D': 400,
        'C': 300,
        'B': 200,
        'A': 100,
      });
      String? selected;

      await tester.pumpWidget(
        _host(
          MixingDesk(
            categories: categories,
            tones: tones,
            selected: selected,
            onSelect: (value) => selected = value,
            currency: 'PKR',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final stripFinder = find.byKey(const Key('mixing-desk-strip'));
      final rect = tester.getRect(stripFinder);
      final n = known.length;

      // Eight channels at 8 known categories -- no AUX fold, no dead
      // channels available to this widget at all (it only ever sees active
      // categories), so every one of the eight is a real, tappable channel.
      final probes = [2.0, rect.width / n, rect.width * 0.5, rect.width - 2.0];
      for (final dx in probes) {
        selected = null;
        await tester.tapAt(Offset(rect.left + dx, rect.center.dy));
        await tester.pump();
        final expectedIndex = _expectedSliceIndex(dx, rect.width, n);
        expect(
          selected,
          known[expectedIndex],
          reason: 'tap at dx=$dx did not resolve to the nearest channel',
        );
      }
    });

    testWidgets('a tap in the centred mini strip resolves to the nearest '
        'channel centre', (tester) async {
      const known = ['X', 'Y', 'Z'];
      final tones = CategoryTones(known: known);
      final categories = _categories({'X': 100, 'Y': 200, 'Z': 300});
      String? selected;

      await tester.pumpWidget(
        _host(
          MixingDesk(
            categories: categories,
            tones: tones,
            selected: selected,
            onSelect: (value) => selected = value,
            currency: 'PKR',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rect = tester.getRect(find.byKey(const Key('mixing-desk-strip')));
      final n = known.length;

      for (final dx in [1.0, rect.width / 2, rect.width - 1.0]) {
        selected = null;
        await tester.tapAt(Offset(rect.left + dx, rect.center.dy));
        await tester.pump();
        final expectedIndex = _expectedMiniIndex(dx, rect.width, n);
        expect(selected, known[expectedIndex]);
      }
    });

    testWidgets('the patch-bay row is a real 48dp fallback target', (
      tester,
    ) async {
      final tones = CategoryTones(known: const ['One', 'Two', 'Three']);
      final categories = _categories({'One': 100, 'Two': 200, 'Three': 300});

      await tester.pumpWidget(
        _host(
          MixingDesk(
            categories: categories,
            tones: tones,
            selected: null,
            onSelect: (_) {},
            currency: 'PKR',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rowSize = tester.getSize(find.byKey(const ValueKey('patch-One')));
      expect(rowSize.height, greaterThanOrEqualTo(48));
    });
  });

  group('360px width', () {
    testWidgets('the flagship 14-category case does not overflow', (
      tester,
    ) async {
      addTearDown(() => tester.view.resetPhysicalSize());
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;

      final known = [for (var i = 0; i < 14; i++) 'Category $i'];
      final tones = CategoryTones(known: known);
      final amounts = {
        for (var i = 0; i < 14; i++) 'Category $i': 1000 - i * 60,
      };

      await tester.pumpWidget(
        _host(
          MixingDesk(
            categories: _categories(amounts),
            tones: tones,
            selected: null,
            onSelect: (_) {},
            currency: 'PKR',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('the solo module does not overflow', (tester) async {
      addTearDown(() => tester.view.resetPhysicalSize());
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(
        _host(
          MixingDesk(
            categories: _categories({'Groceries': 15000}),
            tones: CategoryTones(known: const ['Groceries']),
            selected: null,
            onSelect: (_) {},
            currency: 'PKR',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('degenerate counts', () {
    testWidgets('zero categories renders a quiet message, not a blank '
        'strip', (tester) async {
      await tester.pumpWidget(
        _host(
          MixingDesk(
            categories: const [],
            tones: CategoryTones(known: const []),
            selected: null,
            onSelect: (_) {},
            currency: 'PKR',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text('Categorised spending will appear here.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('mixing-desk-strip')), findsNothing);
    });

    testWidgets('one category renders the solo module, not the strip', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          MixingDesk(
            categories: _categories({'Groceries': 15000}),
            tones: CategoryTones(known: const ['Groceries']),
            selected: null,
            onSelect: (_) {},
            currency: 'PKR',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.byKey(const Key('mixing-desk-strip')), findsNothing);
    });

    testWidgets('under six channels uses the centred mini layout without '
        'throwing', (tester) async {
      final tones = CategoryTones(known: const ['One', 'Two', 'Three']);
      await tester.pumpWidget(
        _host(
          MixingDesk(
            categories: _categories({'One': 100, 'Two': 50, 'Three': 25}),
            tones: tones,
            selected: null,
            onSelect: (_) {},
            currency: 'PKR',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final name in ['One', 'Two', 'Three']) {
        expect(find.byKey(ValueKey('channel-$name')), findsOneWidget);
      }
    });

    testWidgets('past 14 active categories folds the rest into one AUX '
        'channel, expandable on tap', (tester) async {
      final known = [for (var i = 0; i < 20; i++) 'Category $i'];
      final tones = CategoryTones(known: known);
      // Descending amounts, so which 13 stay individual is unambiguous:
      // Category 0..12 are the 13 largest, 13..19 are the folded seven.
      final amounts = {
        for (var i = 0; i < 20; i++) 'Category $i': 2000 - i * 50,
      };

      await tester.pumpWidget(
        _host(
          MixingDesk(
            categories: _categories(amounts),
            tones: tones,
            selected: null,
            onSelect: (_) {},
            currency: 'PKR',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (var i = 0; i < 13; i++) {
        expect(
          find.byKey(ValueKey('channel-Category $i')),
          findsOneWidget,
          reason:
              'Category $i is one of the 13 largest and should keep its '
              'own channel',
        );
      }
      for (var i = 13; i < 20; i++) {
        expect(
          find.byKey(ValueKey('channel-Category $i')),
          findsNothing,
          reason:
              'Category $i should be folded into AUX, not drawn on its '
              'own',
        );
      }
      expect(find.byKey(const ValueKey('channel-aux')), findsOneWidget);
      expect(find.textContaining('+ 7 more'), findsOneWidget);

      // The fold is not a dead end: tapping AUX's patch-bay row opens the
      // list of everything it swallowed.
      expect(find.text('Category 19'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('patch-aux')));
      await tester.pumpAndSettle();
      expect(find.text('Category 19'), findsOneWidget);
    });
  });

  group('reduced motion', () {
    testWidgets('the entry cascade does not keep scheduling frames', (
      tester,
    ) async {
      final known = [for (var i = 0; i < 8; i++) 'Category $i'];
      final tones = CategoryTones(known: known);
      final amounts = {for (var i = 0; i < 8; i++) 'Category $i': 100 + i};

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: _host(
            MixingDesk(
              categories: _categories(amounts),
              tones: tones,
              selected: null,
              onSelect: (_) {},
              currency: 'PKR',
            ),
          ),
        ),
      );
      await tester.pump();

      // Under reduced motion the controller jumps to its resting value
      // instead of being driven forward, so there is nothing left to tick --
      // a raw AnimationController gets none of Flutter's help honouring this
      // by itself, so if the widget forgot to check, this frame would still
      // be scheduling the next one.
      expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
    });

    testWidgets('without reduced motion the cascade is still running after '
        'the first frame', (tester) async {
      final known = [for (var i = 0; i < 8; i++) 'Category $i'];
      final tones = CategoryTones(known: known);
      final amounts = {for (var i = 0; i < 8; i++) 'Category $i': 100 + i};

      await tester.pumpWidget(
        _host(
          MixingDesk(
            categories: _categories(amounts),
            tones: tones,
            selected: null,
            onSelect: (_) {},
            currency: 'PKR',
          ),
        ),
      );
      await tester.pump();

      expect(SchedulerBinding.instance.hasScheduledFrame, isTrue);
      await tester.pumpAndSettle();
    });
  });

  group('selection', () {
    testWidgets('tapping a channel twice selects then clears the filter', (
      tester,
    ) async {
      final tones = CategoryTones(known: const ['One', 'Two', 'Three']);
      String? selected;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => _host(
            MixingDesk(
              categories: _categories({'One': 100, 'Two': 50, 'Three': 25}),
              tones: tones,
              selected: selected,
              onSelect: (value) => setState(() => selected = value),
              currency: 'PKR',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('patch-One')));
      await tester.pumpAndSettle();
      expect(selected, 'One');

      await tester.tap(find.byKey(const ValueKey('patch-One')));
      await tester.pumpAndSettle();
      expect(selected, isNull);
    });

    testWidgets('the desk still renders every category while a filter is '
        'active -- fader levels do not move on selection', (tester) async {
      final tones = CategoryTones(known: const ['One', 'Two', 'Three']);
      final categories = _categories({'One': 100, 'Two': 50, 'Three': 25});

      await tester.pumpWidget(
        _host(
          MixingDesk(
            categories: categories,
            tones: tones,
            selected: 'Two',
            onSelect: (_) {},
            currency: 'PKR',
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final name in ['One', 'Two', 'Three']) {
        expect(find.byKey(ValueKey('channel-$name')), findsOneWidget);
      }
    });
  });
}
