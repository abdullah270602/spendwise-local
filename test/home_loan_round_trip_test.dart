import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/dashboard/home_savings.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// Home's shape is a share, and a share is only as honest as its
/// denominator. Money lent out and paid back inside the same window is the
/// same note leaving and returning -- counting both legs made a month read as
/// twice the size it was, and measured what was really kept against a figure
/// that never came in.
///
/// The fix is to net the two. It costs nothing, which is the point: what is
/// kept has to agree with the balance, and netting takes the same amount off
/// what came in and off what went out on loans, so that figure does not move
/// by a rupee.
void main() {
  // Home's window runs from the start of the period to now, so "now" has to
  // sit after every entry these tests place in it.
  final september = DateTime(2026, 9, 28);

  TransactionViewData move({
    required String id,
    required TransactionKind kind,
    required int minor,
    int day = 10,
    String? debtId,
  }) => TransactionViewData(
    id: id,
    title: 'x',
    subtitle: 'x',
    amount: MoneyViewData(minor),
    kind: kind,
    occurredAt: DateTime(2026, 9, day, 12),
    category: 'Other',
    accountId: 'current',
    debtId: debtId,
  );

  HomeFigures figuresFor({
    required List<TransactionViewData> transactions,
    required int income,
    required int spending,
    List<DebtViewData> debts = const [],
  }) => homeFigures(
    _Fake(
      transactions: transactions,
      income: income,
      spending: spending,
      loans: debts,
    ),
    now: september,
  );

  /// What the dashboard would report: entries attached to a loan are neither
  /// income nor spending, which is the rule these figures are built on top of.
  int incomeOf(List<TransactionViewData> items) => items
      .where(
        (item) => item.kind == TransactionKind.income && item.debtId == null,
      )
      .fold<int>(0, (sum, item) => sum + item.amount.minorUnits);

  int spendingOf(List<TransactionViewData> items) => items
      .where(
        (item) => item.kind == TransactionKind.expense && item.debtId == null,
      )
      .fold<int>(0, (sum, item) => sum + item.amount.minorUnits);

  HomeFigures picture(List<TransactionViewData> items) => figuresFor(
    transactions: items,
    income: incomeOf(items),
    spending: spendingOf(items),
    debts: const [],
  );

  final salary = move(
    id: 'salary',
    kind: TransactionKind.income,
    minor: 10000000,
    day: 1,
  );
  final groceries = move(
    id: 'shop',
    kind: TransactionKind.expense,
    minor: 3000000,
    day: 5,
  );

  test('a loan lent and repaid in the same month leaves the shape alone', () {
    final plain = picture([salary, groceries]);
    final withLoan = picture([
      salary,
      groceries,
      move(
        id: 'out',
        kind: TransactionKind.expense,
        minor: 21600000,
        day: 8,
        debtId: 'kashif',
      ),
      move(
        id: 'back',
        kind: TransactionKind.income,
        minor: 21600000,
        day: 20,
        debtId: 'kashif',
      ),
    ]);

    expect(
      withLoan.received,
      plain.received,
      reason: 'the same note leaving and returning is not money coming in',
    );
    expect(withLoan.kept, plain.kept);
    expect(withLoan.spent, plain.spent);
  });

  test('what is kept never moves, whichever way the netting goes', () {
    // The property the whole change rests on. Kept is the figure that has to
    // agree with the balance, so netting is only allowed because it takes
    // the same amount off both sides of it.
    for (final (out, back) in [
      (21600000, 21600000),
      (21600000, 5000000),
      (5000000, 21600000),
      (0, 21600000),
      (21600000, 0),
    ]) {
      final items = [
        salary,
        groceries,
        if (out > 0)
          move(
            id: 'out',
            kind: TransactionKind.expense,
            minor: out,
            day: 8,
            debtId: 'kashif',
          ),
        if (back > 0)
          move(
            id: 'back',
            kind: TransactionKind.income,
            minor: back,
            day: 20,
            debtId: 'kashif',
          ),
      ];
      final figures = picture(items);
      expect(
        figures.kept,
        10000000 - 3000000 - out + back,
        reason: 'out $out, back $back',
      );
      // And the shape still adds up: what came in is what was spent, what is
      // kept, and what went back out on loans.
      expect(
        figures.received,
        figures.kept + figures.spent + (out > back ? out - back : 0),
        reason: 'out $out, back $back',
      );
    }
  });

  test(
    'a loan you made and have not been repaid still lowers what is kept',
    () {
      final figures = picture([
        salary,
        groceries,
        move(
          id: 'out',
          kind: TransactionKind.expense,
          minor: 21600000,
          day: 8,
          debtId: 'kashif',
        ),
      ]);

      expect(figures.received, 10000000, reason: 'nothing extra came in');
      expect(
        figures.kept,
        10000000 - 3000000 - 21600000,
        reason: 'the money is out of the account and out of your hands',
      );
    },
  );

  test('a repayment of an older loan still counts as money arriving', () {
    // Nothing went out this month, so there is nothing to net it against.
    // The money genuinely arrived and is genuinely yours again.
    final figures = picture([
      salary,
      groceries,
      move(
        id: 'back',
        kind: TransactionKind.income,
        minor: 21600000,
        day: 20,
        debtId: 'kashif',
      ),
    ]);

    expect(figures.received, 10000000 + 21600000);
    expect(figures.kept, 10000000 + 21600000 - 3000000);
  });

  test('money held for somebody stays out of the shape entirely', () {
    // Held money is not the owner's on either leg, so it is not netted --
    // it is excluded, which is a different and stronger claim.
    final held = DebtViewData(
      id: 'held',
      kind: DebtKind.holding,
      counterparty: 'Bilal',
      principal: const MoneyViewData(4000000),
      settled: const MoneyViewData(0),
      outstanding: const MoneyViewData(4000000),
      openedAt: DateTime(2026, 9, 2),
      isSettled: false,
    );
    final items = [
      salary,
      groceries,
      move(
        id: 'in',
        kind: TransactionKind.income,
        minor: 4000000,
        day: 3,
        debtId: 'held',
      ),
    ];
    final figures = figuresFor(
      transactions: items,
      income: incomeOf(items),
      spending: spendingOf(items),
      debts: [held],
    );

    expect(figures.received, 10000000, reason: 'it was never theirs');
    expect(figures.kept, 10000000 - 3000000);
  });

  test('a round trip on its own leaves nothing to draw', () {
    // Rather than a confident split of a month that never happened.
    final figures = picture([
      move(
        id: 'out',
        kind: TransactionKind.expense,
        minor: 21600000,
        day: 8,
        debtId: 'kashif',
      ),
      move(
        id: 'back',
        kind: TransactionKind.income,
        minor: 21600000,
        day: 20,
        debtId: 'kashif',
      ),
    ]);

    expect(figures.received, 0);
    expect(figures.kept, 0);
    expect(figures.spent, 0);
  });
}

class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  _Fake({
    required this.transactions,
    required this.income,
    required this.spending,
    required this.loans,
  });

  final int income;
  final int spending;
  final List<DebtViewData> loans;

  @override
  final List<TransactionViewData> transactions;

  @override
  List<DebtViewData> get debts => loans;

  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'current',
      name: 'Everyday',
      type: 'bank',
      balance: MoneyViewData(0),
    ),
  ];

  @override
  DashboardViewData get dashboard => DashboardViewData(
    netWorth: const MoneyViewData(0),
    incomeThisMonth: MoneyViewData(income),
    spendingThisMonth: MoneyViewData(spending),
    monthlyChangePercent: 0,
  );

  @override
  HomePeriod get homePeriod => HomePeriod.calendarMonth;

  @override
  bool get busy => false;

  @override
  String? get errorMessage => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
