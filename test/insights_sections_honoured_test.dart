import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/insights/chronograph.dart';
import 'package:spendwise/features/insights/gate.dart';
import 'package:spendwise/features/insights/insights_layout.dart';
import 'package:spendwise/features/insights/insights_screen.dart';
import 'package:spendwise/features/insights/mixing_desk.dart';
import 'package:spendwise/features/insights/seismograph.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// The fold was unit-tested and the preview was widget-tested, and the last
/// setting this app shipped still did nothing on the screen it configured.
/// Neither test asked the only question that mattered. These do: for every
/// value of every one of the three settings, is the thing it names on screen,
/// and is nothing else.
void main() {
  /// [scroll] reaches the sections that sit below the fold. It is off for the
  /// spine, which sits at the top in a sliver: dragging past it unmounts it,
  /// and a test that scrolled first would report it missing when it is simply
  /// no longer built.
  Future<void> pump(
    WidgetTester tester,
    Map<String, String> prefs, {
    bool scroll = true,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Scaffold(body: InsightsScreen(viewModel: _Fake(prefs))),
      ),
    );
    await tester.pumpAndSettle();
    if (!scroll) return;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
  }

  group('where your money went', () {
    // The three drawn answers and the widget each one must produce, written
    // as a map so a new option cannot be added without a row here failing.
    final expected = {
      InsightsShare.bars: CategoryBars,
      InsightsShare.chronograph: Chronograph,
      InsightsShare.mixingDesk: MixingDesk,
    };

    for (final entry in expected.entries) {
      testWidgets('${entry.key.id} draws ${entry.value}', (tester) async {
        await pump(tester, {InsightsPreference.share: entry.key.id});

        expect(find.byType(entry.value), findsOneWidget);
        for (final other in expected.values) {
          if (other == entry.value) continue;
          expect(
            find.byType(other),
            findsNothing,
            reason: 'choosing ${entry.key.id} drew $other as well',
          );
        }
      });
    }

    testWidgets('off draws none of them', (tester) async {
      await pump(tester, {InsightsPreference.share: InsightsShare.off.id});
      for (final widget in expected.values) {
        expect(find.byType(widget), findsNothing, reason: '$widget survived');
      }
      expect(find.text('WHERE YOUR MONEY WENT'), findsNothing);
    });
  });

  group('what changed', () {
    testWidgets('is off until it is asked for', (tester) async {
      // Nothing stored at all: the agreed default.
      await pump(tester, {});
      expect(find.byType(Seismograph), findsNothing);
      expect(find.byType(Gate), findsNothing);
    });

    testWidgets('seismograph draws the trace and not the gate', (tester) async {
      await pump(tester, {
        InsightsPreference.change: InsightsChange.seismograph.id,
      });
      expect(find.byType(Seismograph), findsOneWidget);
      expect(find.byType(Gate), findsNothing);
    });

    testWidgets('the gate draws the corridor and not the trace', (
      tester,
    ) async {
      await pump(tester, {InsightsPreference.change: InsightsChange.gate.id});
      expect(find.byType(Gate), findsOneWidget);
      expect(find.byType(Seismograph), findsNothing);
    });
  });

  group('over time', () {
    testWidgets('is drawn by default', (tester) async {
      await pump(tester, {}, scroll: false);
      expect(find.byType(FlowSpine), findsOneWidget);
    });

    testWidgets('is gone when it is turned off', (tester) async {
      await pump(tester, {
        InsightsPreference.overTime: InsightsOverTime.off.id,
      }, scroll: false);
      expect(find.byType(FlowSpine), findsNothing);
    });
  });

  group('the chosen period', () {
    testWidgets('opens on the month when nothing is stored', (tester) async {
      await pump(tester, {}, scroll: false);
      expect(find.text('THIS MONTH'), findsOneWidget);
    });

    testWidgets('is honoured when one is stored', (tester) async {
      // It was the one view preference the app forgot, so somebody who reads
      // their spending by year said so again on every launch.
      await pump(tester, {InsightsPreference.period: 'years'}, scroll: false);
      expect(find.text('YEARS'), findsOneWidget);
    });

    testWidgets('a stored value that no longer exists falls back', (
      tester,
    ) async {
      await pump(tester, {
        InsightsPreference.period: 'fortnight',
      }, scroll: false);
      expect(find.text('THIS MONTH'), findsOneWidget);
    });
  });

  testWidgets('every section can be off at once without breaking', (
    tester,
  ) async {
    // The figures are the floor. Turning everything off must leave a screen
    // that still reports something, not an empty scroll view.
    await pump(tester, {
      InsightsPreference.overTime: InsightsOverTime.off.id,
      InsightsPreference.share: InsightsShare.off.id,
      InsightsPreference.change: InsightsChange.off.id,
    });
    expect(tester.takeException(), isNull);
    expect(find.text('SPENT IN THIS VIEW'), findsOneWidget);
    expect(find.text('Change what Insights shows'), findsOneWidget);
  });

  testWidgets('a corrupt preference falls back rather than blanking', (
    tester,
  ) async {
    // A value written by a version that no longer exists must not silently
    // remove a whole section.
    await pump(tester, {
      InsightsPreference.share: 'donut',
      InsightsPreference.change: 'sparkline',
    });
    expect(find.byType(Chronograph), findsOneWidget);
    expect(find.byType(Seismograph), findsNothing);
    expect(find.byType(Gate), findsNothing);
  });
}

class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  _Fake(this.preferences);

  final Map<String, String> preferences;

  /// Pinned to the first of each month so both windows sit comfortably inside
  /// their own calendar unit whatever day the suite happens to run on.
  static final _now = DateTime.now();
  static final _thisPeriod = DateTime(_now.year, _now.month);
  static final _lastPeriod = DateTime(_now.year, _now.month - 1);

  @override
  String? viewPreference(String key) => preferences[key];

  @override
  void setViewPreference(String key, String value) => preferences[key] = value;

  @override
  List<CategoryViewData> get categories => const [];

  @override
  List<TransactionViewData> get transactions => [
    for (final entry in const <(String, int)>[
      ('Groceries', 4218000),
      ('Bills & utilities', 2890000),
      ('Transport', 2145000),
      ('Food & dining', 1860000),
      ('Health', 1420000),
    ])
      TransactionViewData(
        id: 'now-${entry.$1}',
        title: entry.$1,
        subtitle: '',
        amount: MoneyViewData(-entry.$2),
        kind: TransactionKind.expense,
        occurredAt: _thisPeriod,
        category: entry.$1,
        accountId: 'bank',
      ),
    // A comparison period, so "what changed" has something to compare against
    // and Travel can be a category that stopped.
    for (final entry in const <(String, int)>[
      ('Groceries', 3890000),
      ('Travel', 1540000),
    ])
      TransactionViewData(
        id: 'then-${entry.$1}',
        title: entry.$1,
        subtitle: '',
        amount: MoneyViewData(-entry.$2),
        kind: TransactionKind.expense,
        occurredAt: _lastPeriod,
        category: entry.$1,
        accountId: 'bank',
      ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
