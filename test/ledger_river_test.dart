import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/insights/river_view.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';
import 'package:spendwise/features/transactions/ledger_screen.dart';

/// The river came from Insights, where it answered "what happened" -- which is
/// Ledger's question, not that screen's. It also broke its own scope there:
/// the heading showed one period's totals while the list below it was handed
/// the entire unfiltered ledger, so the two could never agree.
///
/// Here it reads exactly what the register reads.
void main() {
  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month, 5);
  final longAgo = DateTime(now.year - 2, now.month, 5);

  TransactionViewData spend(String title, DateTime when, int minor) =>
      TransactionViewData(
        id: title,
        title: title,
        subtitle: 'Everyday',
        amount: MoneyViewData(-minor),
        kind: TransactionKind.expense,
        occurredAt: when,
        category: 'Groceries',
        accountId: 'bank',
      );

  Future<_Fake> openLedger(
    WidgetTester tester,
    List<TransactionViewData> t,
  ) async {
    final model = _Fake(t);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Scaffold(body: LedgerScreen(viewModel: model)),
      ),
    );
    await tester.pumpAndSettle();
    return model;
  }

  testWidgets('the river is a third way to read the month, not new chrome', (
    tester,
  ) async {
    await openLedger(tester, [spend('Recent', thisMonth, 150000)]);

    // It shares the toggle that already chose between the chart and the
    // plain register.
    expect(find.text('CHART'), findsOneWidget);
    expect(find.text('RIVER'), findsOneWidget);
    expect(find.text('PLAIN'), findsOneWidget);
    expect(find.byType(RiverView), findsNothing);

    await tester.tap(find.text('RIVER'));
    await tester.pumpAndSettle();

    expect(find.byType(RiverView), findsOneWidget);
  });

  testWidgets('and it shows the month in view, not the whole ledger', (
    tester,
  ) async {
    // The defect it arrived with. On Insights the heading was scoped and the
    // list was not, so a total could sit above entries it did not count.
    await openLedger(tester, [
      spend('Recent', thisMonth, 150000),
      spend('Ancient', longAgo, 900000),
    ]);

    await tester.tap(find.text('RIVER'));
    await tester.pumpAndSettle();

    final river = tester.widget<RiverView>(find.byType(RiverView));
    expect(river.transactions.map((item) => item.title), ['Recent']);
    expect(
      river.transactions.any((item) => item.title == 'Ancient'),
      isFalse,
      reason: 'the heading above it counts this month only',
    );
  });

  testWidgets('the choice is remembered', (tester) async {
    final model = await openLedger(tester, [
      spend('Recent', thisMonth, 150000),
    ]);

    await tester.tap(find.text('RIVER'));
    await tester.pumpAndSettle();
    expect(model.preferences['ledger_view'], 'river');

    await tester.tap(find.text('PLAIN'));
    await tester.pumpAndSettle();
    expect(model.preferences['ledger_view'], 'plain');
    expect(find.byType(RiverView), findsNothing);
  });
}

class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  _Fake(this._transactions);

  final List<TransactionViewData> _transactions;
  final Map<String, String> preferences = {};

  @override
  List<TransactionViewData> get transactions => _transactions;

  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'bank',
      name: 'Everyday',
      type: 'Bank',
      balance: MoneyViewData(1000000),
    ),
  ];

  @override
  List<CategoryViewData> get categories => const [];

  @override
  DashboardViewData get dashboard => const DashboardViewData(
    netWorth: MoneyViewData(1000000),
    incomeThisMonth: MoneyViewData(0),
    spendingThisMonth: MoneyViewData(150000),
    monthlyChangePercent: 0,
  );

  @override
  List<DebtViewData> get debts => const [];

  @override
  String? viewPreference(String key) => preferences[key];

  @override
  void setViewPreference(String key, String value) => preferences[key] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
