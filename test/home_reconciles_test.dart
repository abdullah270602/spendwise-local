import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/dashboard/home_savings.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// The rule Home has to obey, and did not.
///
///     what came in
///   − everything that left
///   = how much the spendable balance actually changed
///
/// It used to compute `received − spent`, which assumes spending is the only
/// way money leaves an account. When it is not — a loan made, a borrowing
/// handed back, money put into savings — the headline drifts from the
/// balances by exactly the amount ignored, and Home and Accounts stop being
/// reconcilable by hand. Which is how a person ends up at 2am unable to
/// account for their own money.
void main() {
  final from = DateTime(2026, 9, 1);
  final to = DateTime(2026, 10, 1);
  const savingsIds = {'ubl'};

  TransactionViewData at(
    int day, {
    required TransactionKind kind,
    required int minor,
    String? account,
    String? into,
    String? debtId,
  }) => TransactionViewData(
    id: '$day-$minor-$kind',
    title: 'x',
    subtitle: 'x',
    amount: MoneyViewData(minor),
    kind: kind,
    occurredAt: DateTime(2026, 9, day, 12),
    category: 'Other',
    accountId: account,
    toAccountId: into,
    debtId: debtId,
  );

  test('September, as it actually happened, reconciles', () {
    // The real month: salary in, ordinary spending, 40,000 lent, 168,000 of
    // family money handed back, 40,000 into savings.
    final ledger = [
      at(2, kind: TransactionKind.income, minor: 17680000, account: 'meezan'),
      at(3, kind: TransactionKind.expense, minor: 3574159, account: 'meezan'),
      at(
        4,
        kind: TransactionKind.expense,
        minor: 4000000,
        account: 'meezan',
        debtId: 'kashif',
      ),
      at(
        7,
        kind: TransactionKind.expense,
        minor: 16800000,
        account: 'meezan',
        debtId: 'family',
      ),
      at(
        8,
        kind: TransactionKind.transfer,
        minor: 4000000,
        account: 'meezan',
        into: 'ubl',
      ),
    ];

    const received = 17680000;
    const spent = 3574159; // debt-linked movements are not spending
    final debtOutflow = debtOutflowInWindow(
      transactions: ledger,
      from: from,
      to: to,
    );
    final saved = savedInWindow(
      transactions: ledger,
      savingsAccountIds: savingsIds,
      from: from,
      to: to,
    );

    expect(debtOutflow, 20800000, reason: '40,000 lent + 168,000 handed back');
    expect(saved, 4000000);
    // Nothing debt-linked *arrived* in September -- the family money landed on
    // 31 August, inside the opening balance. That accident is the only reason
    // this month reconciled while the inflow half was still missing.
    expect(
      debtInflowInWindow(transactions: ledger, from: from, to: to),
      0,
      reason: 'the arriving leg fell outside the window',
    );

    // What Home shows once saving is set aside.
    final available = received - spent - debtOutflow - saved;

    // What actually happened to the spendable accounts: 150,314.97 -> 43,373.38
    const openingMinor = 15031497;
    const closingMinor = 4337338;
    expect(
      available,
      closingMinor - openingMinor,
      reason: 'what came in minus everything that left IS the balance change',
    );
    expect(openingMinor + available, closingMinor);
  });

  test('the old formula was wrong by exactly what it ignored', () {
    final ledger = [
      at(2, kind: TransactionKind.income, minor: 17680000, account: 'meezan'),
      at(3, kind: TransactionKind.expense, minor: 3574159, account: 'meezan'),
      at(
        4,
        kind: TransactionKind.expense,
        minor: 4000000,
        account: 'meezan',
        debtId: 'kashif',
      ),
      at(
        7,
        kind: TransactionKind.expense,
        minor: 16800000,
        account: 'meezan',
        debtId: 'family',
      ),
      at(
        8,
        kind: TransactionKind.transfer,
        minor: 4000000,
        account: 'meezan',
        into: 'ubl',
      ),
    ];
    const received = 17680000;
    const spent = 3574159;

    final ignored =
        debtOutflowInWindow(transactions: ledger, from: from, to: to) +
        savedInWindow(
          transactions: ledger,
          savingsAccountIds: savingsIds,
          from: from,
          to: to,
        );

    expect(ignored, 24800000, reason: '40,000 + 168,000 + 40,000');
    expect(
      (received - spent) - (4337338 - 15031497),
      ignored,
      reason: 'the whole discrepancy, and nothing else',
    );
  });

  test('an ordinary month is unaffected', () {
    // Nothing lent, nothing borrowed, nothing put away: the old formula and
    // the new one agree, which is why this went unnoticed for so long.
    final ledger = [
      at(2, kind: TransactionKind.income, minor: 17680000, account: 'meezan'),
      at(3, kind: TransactionKind.expense, minor: 3574159, account: 'meezan'),
    ];
    expect(debtOutflowInWindow(transactions: ledger, from: from, to: to), 0);
    expect(
      savedInWindow(
        transactions: ledger,
        savingsAccountIds: savingsIds,
        from: from,
        to: to,
      ),
      0,
    );
  });

  test('money coming back from a loan is an inflow, not an outflow', () {
    // Repayment arrives as income carrying the debt. Counting it as an
    // outflow would double-punish the month it returns in -- but counting it
    // nowhere at all was the other half of the same mistake. The balance rose
    // by 40,000 and the headline did not move.
    final ledger = [
      at(
        9,
        kind: TransactionKind.income,
        minor: 4000000,
        account: 'meezan',
        debtId: 'kashif',
      ),
    ];
    expect(debtOutflowInWindow(transactions: ledger, from: from, to: to), 0);
    expect(
      debtInflowInWindow(transactions: ledger, from: from, to: to),
      4000000,
    );

    final received = debtInflowInWindow(
      transactions: ledger,
      from: from,
      to: to,
    );
    final available =
        received -
        0 -
        debtOutflowInWindow(transactions: ledger, from: from, to: to);
    expect(available, 4000000, reason: '40,000 landed, so Home must say so');
  });

  test('money held for someone and passed straight on changes nothing', () {
    // The courier case. Someone hands you money to give to someone else: it
    // arrives, it leaves, and the account ends exactly where it started.
    // Counting only the leg that leaves reported a loss of the whole amount.
    final ledger = [
      at(
        2,
        kind: TransactionKind.income,
        minor: 16800000,
        account: 'meezan',
        debtId: 'family',
      ),
      at(
        7,
        kind: TransactionKind.expense,
        minor: 16800000,
        account: 'meezan',
        debtId: 'family',
      ),
    ];
    final received = debtInflowInWindow(
      transactions: ledger,
      from: from,
      to: to,
    );
    final available =
        received -
        0 -
        debtOutflowInWindow(transactions: ledger, from: from, to: to);
    expect(available, 0, reason: 'in and straight back out is not a loss');
  });

  test('direction survives: lending out is not being repaid', () {
    // The same debt id appears on the way out and on the way back, so the two
    // helpers must not both claim it.
    final ledger = [
      at(
        4,
        kind: TransactionKind.expense,
        minor: 4000000,
        account: 'meezan',
        debtId: 'kashif',
      ),
    ];
    expect(debtInflowInWindow(transactions: ledger, from: from, to: to), 0);
    expect(
      debtOutflowInWindow(transactions: ledger, from: from, to: to),
      4000000,
    );
  });

  test('another period is another period', () {
    final ledger = [
      at(
        4,
        kind: TransactionKind.expense,
        minor: 4000000,
        account: 'meezan',
        debtId: 'kashif',
      ),
    ];
    expect(
      debtOutflowInWindow(
        transactions: ledger,
        from: DateTime(2026, 9, 10),
        to: DateTime(2026, 9, 17),
      ),
      0,
    );
  });
}
