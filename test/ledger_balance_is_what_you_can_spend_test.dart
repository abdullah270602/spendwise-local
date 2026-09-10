import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';
import 'package:spendwise/features/transactions/ledger_screen.dart';
import 'package:spendwise/widgets/shape_kit.dart';

/// "Balance now", and the line drawn underneath it, are both answers to one
/// question: how much can be spent. Each of them used to answer a different
/// one.
///
/// The figure was the plain total of the everyday accounts, so money held for
/// somebody else -- which lands in an account and looks exactly like the
/// owner's own -- was counted as theirs to spend. Accounts had always taken it
/// off the top and said so; one account holding nothing but a relative's
/// 100,000 read "Available to spend 0" there and "Balance now 100,000" here,
/// about the same money on the same day.
///
/// The chart was walked backwards from that figure, and the walk skipped every
/// transfer. But a transfer into savings does move the spendable balance:
/// savings is not part of it. A month that opened at 100,000, moved 20,000 into
/// savings and spent 5,000 printed 75,000 above a line that started the month
/// at 80,000 -- 20,000 low across the whole first third of the month, and
/// compounding for every earlier month, because the walk back to a past month
/// skipped those transfers too.
///
/// The rule both now follow: the walk-back un-applies exactly what the figure
/// counts, and nothing else.
void main() {
  final now = DateTime.now();

  DateTime thisMonthOn(int day) => DateTime(now.year, now.month, day, 12);
  DateTime lastMonthOn(int day) => DateTime(now.year, now.month - 1, day, 12);

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

  TransactionViewData earn(
    String title,
    DateTime when,
    int minor, {
    String? debtId,
  }) => TransactionViewData(
    id: title,
    title: title,
    subtitle: 'Everyday',
    amount: MoneyViewData(minor),
    kind: TransactionKind.income,
    occurredAt: when,
    category: 'Income',
    accountId: 'bank',
    debtId: debtId,
  );

  TransactionViewData move(
    String title,
    DateTime when,
    int minor, {
    required String from,
    required String to,
  }) => TransactionViewData(
    id: title,
    title: title,
    subtitle: 'Own accounts',
    amount: MoneyViewData(minor),
    kind: TransactionKind.transfer,
    occurredAt: when,
    category: 'Transfer',
    accountId: from,
    toAccountId: to,
  );

  DebtViewData held(String id, int minor, {int settledMinor = 0}) =>
      DebtViewData(
        id: id,
        kind: DebtKind.holding,
        counterparty: 'My brother',
        principal: MoneyViewData(minor),
        settled: MoneyViewData(settledMinor),
        outstanding: MoneyViewData(minor - settledMinor),
        openedAt: thisMonthOn(1),
        isSettled: minor - settledMinor == 0,
      );

  Future<void> openLedger(WidgetTester tester, _Fake model) async {
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
  }

  /// The figure printed under the "Balance now" eyebrow, exactly as drawn.
  String printedBalance(WidgetTester tester) {
    final column = find
        .ancestor(of: find.text('BALANCE NOW'), matching: find.byType(Column))
        .first;
    final texts = find.descendant(of: column, matching: find.byType(Text));
    return tester.widget<Text>(texts.last).data!;
  }

  /// The chart's end-of-day balances, oldest first.
  List<int> line(WidgetTester tester) =>
      tester.widget<BalanceLine>(find.byType(BalanceLine)).points;

  group('what the figure counts', () {
    testWidgets('money held for somebody else is not yours to spend', (
      tester,
    ) async {
      // One everyday account holding 100,000, every rupee of it a relative's.
      // Accounts prints "Available to spend 0" for exactly this ledger.
      await openLedger(
        tester,
        _Fake(
          transactions: [
            earn('From my brother', thisMonthOn(1), 10000000, debtId: 'held-1'),
          ],
          spendableMinor: 10000000,
          debts: [held('held-1', 10000000)],
        ),
      );

      expect(
        printedBalance(tester),
        formatMinor(0),
        reason: 'the balance is a bank total, not a permission to spend',
      );
    });

    testWidgets('and a settled holding is yours again', (tester) async {
      // The money was handed on, so nothing is being held any more and the
      // account total is the owner's own.
      await openLedger(
        tester,
        _Fake(
          transactions: [
            earn('From my brother', thisMonthOn(1), 10000000, debtId: 'held-1'),
          ],
          spendableMinor: 10000000,
          debts: [held('held-1', 10000000, settledMinor: 10000000)],
        ),
      );

      expect(printedBalance(tester), formatMinor(10000000));
    });
  });

  group('what the line un-applies', () {
    testWidgets('moving money into savings moves the balance', (tester) async {
      // The month opens at 100,000; 20,000 goes into savings on the 10th and
      // 5,000 is spent on the 12th, so 75,000 is left to spend.
      await openLedger(
        tester,
        _Fake(
          transactions: [
            move(
              'Into savings',
              thisMonthOn(10),
              2000000,
              from: 'bank',
              to: 'vault',
            ),
            spend('Groceries', thisMonthOn(12), 500000),
          ],
          spendableMinor: 7500000,
        ),
      );

      expect(printedBalance(tester), formatMinor(7500000));
      final points = line(tester);
      expect(
        points.first,
        10000000,
        reason: 'the month opened at 100,000, before either movement',
      );
      expect(
        points[9],
        8000000,
        reason: 'the 10th ends with the 20,000 already in savings',
      );
      expect(
        points[11],
        7500000,
        reason: 'and the 12th ends after the 5,000 was spent',
      );
    });

    testWidgets('taking it back out of savings moves it the other way', (
      tester,
    ) async {
      await openLedger(
        tester,
        _Fake(
          transactions: [
            move(
              'Out of savings',
              thisMonthOn(10),
              2000000,
              from: 'vault',
              to: 'bank',
            ),
          ],
          spendableMinor: 12000000,
        ),
      );

      expect(
        line(tester).first,
        10000000,
        reason: 'the 20,000 was not spendable until it left savings',
      );
    });

    testWidgets('moving it between two everyday accounts moves nothing', (
      tester,
    ) async {
      // Both ends are already inside the figure, so the total is untouched --
      // the case a fix that simply counted every transfer would get wrong.
      await openLedger(
        tester,
        _Fake(
          transactions: [
            move('To cash', thisMonthOn(10), 2000000, from: 'bank', to: 'cash'),
          ],
          spendableMinor: 10000000,
        ),
      );

      final points = line(tester);
      expect(points.first, 10000000);
      expect(points[9], 10000000, reason: 'the money never left the total');
    });

    testWidgets('and held money arriving moves nothing either', (tester) async {
      // 50,000 arrives on the 10th and is a relative's. The account is 50,000
      // fuller and the held total is 50,000 bigger, so what is left over --
      // the 100,000 that was there all along -- has not changed.
      await openLedger(
        tester,
        _Fake(
          transactions: [
            earn('From my brother', thisMonthOn(10), 5000000, debtId: 'held-1'),
          ],
          spendableMinor: 15000000,
          debts: [held('held-1', 5000000)],
        ),
      );

      expect(printedBalance(tester), formatMinor(10000000));
      final points = line(tester);
      expect(
        points.first,
        10000000,
        reason: 'nothing spendable arrived, so the line is flat across it',
      );
      expect(points[9], 10000000);
    });

    testWidgets('a past month is walked back through the transfers too', (
      tester,
    ) async {
      // Last month opened at 100,000 and spent 5,000 on the 12th, ending at
      // 95,000. This month 20,000 went into savings. Walking back from today's
      // 75,000 has to put that 20,000 back or every earlier month is drawn low
      // by it, and by everything else moved into savings since.
      await openLedger(
        tester,
        _Fake(
          transactions: [
            move(
              'Into savings',
              thisMonthOn(5),
              2000000,
              from: 'bank',
              to: 'vault',
            ),
            spend('Groceries', lastMonthOn(12), 500000),
          ],
          spendableMinor: 7500000,
        ),
      );

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();

      final points = line(tester);
      expect(points.first, 10000000, reason: 'last month opened at 100,000');
      expect(
        points.last,
        9500000,
        reason: 'and closed at 95,000, before the savings transfer happened',
      );
    });
  });
}

class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  _Fake({
    this.transactions = const [],
    required this.spendableMinor,
    this.debts = const [],
  });

  @override
  final List<TransactionViewData> transactions;

  @override
  final List<DebtViewData> debts;

  final int spendableMinor;
  final Map<String, String> preferences = {};

  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'bank',
      name: 'Everyday',
      type: 'Bank',
      balance: MoneyViewData(0),
    ),
    AccountViewData(
      id: 'cash',
      name: 'Cash',
      type: 'Cash',
      balance: MoneyViewData(0),
    ),
    AccountViewData(
      id: 'vault',
      name: 'Savings',
      type: 'Savings',
      balance: MoneyViewData(0),
      isIncluded: false,
    ),
  ];

  @override
  List<CategoryViewData> get categories => const [];

  @override
  DashboardViewData get dashboard => DashboardViewData(
    netWorth: MoneyViewData(spendableMinor),
    spendableBalance: MoneyViewData(spendableMinor),
    incomeThisMonth: const MoneyViewData(0),
    spendingThisMonth: const MoneyViewData(0),
    monthlyChangePercent: 0,
  );

  @override
  HomePeriod get homePeriod => HomePeriod.calendarMonth;

  @override
  String? viewPreference(String key) => preferences[key];

  @override
  void setViewPreference(String key, String value) => preferences[key] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
