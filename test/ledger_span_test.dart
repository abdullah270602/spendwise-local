import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';
import 'package:spendwise/features/transactions/ledger_screen.dart';

/// The Ledger scopes to one month, which is the question people ask most.
/// Everything older stayed reachable only by stepping back a month at a time,
/// and "All months" appeared only as a side effect of searching — so there
/// was no way to simply ask for the whole ledger.
void main() {
  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month, 5);
  final longAgo = DateTime(now.year - 2, now.month, 5);

  TransactionViewData entry(String title, DateTime when) => TransactionViewData(
    id: title,
    title: title,
    subtitle: 'Everyday',
    amount: const MoneyViewData(-150000),
    kind: TransactionKind.expense,
    occurredAt: when,
    category: 'Groceries',
    accountId: 'bank',
  );

  Future<_Fake> openLedger(WidgetTester tester, {_Fake? viewModel}) async {
    final model = viewModel ?? _Fake();
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

  testWidgets('one month is still what you get by default', (tester) async {
    await openLedger(
      tester,
      viewModel: _Fake([entry('Recent', thisMonth), entry('Ancient', longAgo)]),
    );

    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Ancient'), findsNothing);
  });

  testWidgets('and everything older is one tap away', (tester) async {
    final viewModel = await openLedger(
      tester,
      viewModel: _Fake([entry('Recent', thisMonth), entry('Ancient', longAgo)]),
    );

    await tester.tap(find.byTooltip('Show every month'));
    await tester.pumpAndSettle();

    expect(find.text('Ancient'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('All months'), findsOneWidget);
    expect(viewModel.preferences['ledger_span'], 'all');
  });

  testWidgets('and one tap back again', (tester) async {
    final viewModel = await openLedger(
      tester,
      viewModel: _Fake([entry('Recent', thisMonth), entry('Ancient', longAgo)]),
    );
    await tester.tap(find.byTooltip('Show every month'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show one month at a time'));
    await tester.pumpAndSettle();

    expect(find.text('Ancient'), findsNothing);
    expect(viewModel.preferences['ledger_span'], 'month');
  });

  testWidgets('the choice sticks, the way the chart toggle does', (
    tester,
  ) async {
    final remembered = _Fake(
      [entry('Recent', thisMonth), entry('Ancient', longAgo)],
      {'ledger_span': 'all'},
    );
    await openLedger(tester, viewModel: remembered);

    expect(find.text('Ancient'), findsOneWidget);
  });

  testWidgets('an empty month points at the whole ledger, not just back', (
    tester,
  ) async {
    await openLedger(tester, viewModel: _Fake([entry('Ancient', longAgo)]));

    expect(find.textContaining('show every month'), findsOneWidget);
  });
}

class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  _Fake([this._transactions = const [], Map<String, String>? preferences])
    : preferences = {...?preferences};

  final List<TransactionViewData> _transactions;
  final Map<String, String> preferences;

  @override
  List<TransactionViewData> get transactions => _transactions;

  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'bank',
      name: 'Everyday',
      type: 'Bank',
      balance: MoneyViewData(500000),
    ),
  ];

  @override
  List<CategoryViewData> get categories => const [];

  @override
  DashboardViewData get dashboard => const DashboardViewData(
    netWorth: MoneyViewData(500000),
    incomeThisMonth: MoneyViewData(0),
    spendingThisMonth: MoneyViewData(150000),
    monthlyChangePercent: 0,
  );

  @override
  List<DebtViewData> get debts => const [];

  @override
  HomePeriod get homePeriod => HomePeriod.calendarMonth;

  @override
  String? viewPreference(String key) => preferences[key];

  @override
  void setViewPreference(String key, String value) => preferences[key] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
