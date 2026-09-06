import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/debt_kind.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

/// Lending is the one movement a bank alert cannot describe. "PKR 20,000 sent"
/// reads identically whether it bought a phone or went to a friend, so the
/// person marks it — and once marked, the promise is that it stops counting as
/// spending, because it is coming back.
void main() {
  LocalLedger ledgerWithAccount() {
    final ledger = LocalLedger.openInMemoryForTests();
    ledger.addAccount(name: 'Current', type: AccountType.bank);
    return ledger;
  }

  String spend(LocalLedger ledger, int minor, {String at = 'A friend'}) =>
      ledger.addManualTransaction(
        kind: TransactionKind.expense,
        amountMinor: minor,
        occurredAt: DateTime.utc(2026, 9, 4, 12),
        accountId: ledger.snapshot().accounts.single.id,
        description: at,
      );

  String receive(LocalLedger ledger, int minor, {String from = 'A friend'}) =>
      ledger.addManualTransaction(
        kind: TransactionKind.income,
        amountMinor: minor,
        occurredAt: DateTime.utc(2026, 9, 20, 12),
        accountId: ledger.snapshot().accounts.single.id,
        description: from,
      );

  test('lending stops the money counting as spending', () {
    final ledger = ledgerWithAccount();
    addTearDown(ledger.close);
    final id = spend(ledger, 2000000);

    expect(
      ledger
          .spendingByCategory(month: DateTime.utc(2026, 9))
          .values
          .fold<int>(0, (a, b) => a + b),
      2000000,
      reason: 'before marking, it is ordinary spending',
    );

    ledger.openDebt(
      transactionId: id,
      kind: DebtKind.lent,
      counterparty: 'A friend',
    );

    expect(
      ledger.spendingByCategory(month: DateTime.utc(2026, 9)),
      isEmpty,
      reason: 'a loan is not spending; it is coming back',
    );
  });

  test('the debt records who, how much, and that nothing is back yet', () {
    final ledger = ledgerWithAccount();
    addTearDown(ledger.close);
    final id = spend(ledger, 2000000);

    final debt = ledger.openDebt(
      transactionId: id,
      kind: DebtKind.lent,
      counterparty: 'A friend',
      note: 'For the deposit',
    );

    expect(debt.lent, isTrue);
    expect(debt.counterparty, 'A friend');
    expect(debt.principalMinor, 2000000);
    expect(debt.settledMinor, 0);
    expect(debt.outstandingMinor, 2000000);
    expect(debt.isSettled, isFalse);
    expect(debt.note, 'For the deposit');
    expect(debt.openingTransactionId, id);
  });

  test('a partial repayment leaves the rest outstanding', () {
    final ledger = ledgerWithAccount();
    addTearDown(ledger.close);
    final debt = ledger.openDebt(
      transactionId: spend(ledger, 2000000),
      kind: DebtKind.lent,
      counterparty: 'A friend',
    );

    ledger.settleDebt(debtId: debt.id, amountMinor: 500000);

    final after = ledger.debt(debt.id)!;
    expect(after.settledMinor, 500000);
    expect(after.outstandingMinor, 1500000);
    expect(after.isSettled, isFalse);
  });

  test('paying the rest closes it on its own', () {
    final ledger = ledgerWithAccount();
    addTearDown(ledger.close);
    final debt = ledger.openDebt(
      transactionId: spend(ledger, 2000000),
      kind: DebtKind.lent,
      counterparty: 'A friend',
    );

    ledger.settleDebt(debtId: debt.id, amountMinor: 500000);
    ledger.settleDebt(debtId: debt.id, amountMinor: 1500000);

    final after = ledger.debt(debt.id)!;
    expect(after.outstandingMinor, 0);
    expect(after.isSettled, isTrue);
    expect(after.closedAt, isNotNull);
    expect(ledger.debts(includeSettled: false), isEmpty);
  });

  test('money coming back is not income either', () {
    final ledger = ledgerWithAccount();
    addTearDown(ledger.close);
    final debt = ledger.openDebt(
      transactionId: spend(ledger, 2000000),
      kind: DebtKind.lent,
      counterparty: 'A friend',
    );
    final repayment = receive(ledger, 2000000);

    ledger.settleDebt(
      debtId: debt.id,
      amountMinor: 2000000,
      transactionId: repayment,
    );

    final settled = ledger.snapshot().transactions.firstWhere(
      (item) => item.id == repayment,
    );
    expect(
      settled.debtId,
      debt.id,
      reason: 'the repayment is linked, so Home leaves it out of income',
    );
  });

  test('borrowing is the mirror image', () {
    final ledger = ledgerWithAccount();
    addTearDown(ledger.close);
    final debt = ledger.openDebt(
      transactionId: receive(ledger, 500000),
      kind: DebtKind.borrowed,
      counterparty: 'A cousin',
    );

    expect(debt.lent, isFalse);
    expect(debt.outstandingMinor, 500000);
    expect(ledger.debts().single.counterparty, 'A cousin');
  });

  test('unmarking a loan gives the money back to the ledger', () {
    final ledger = ledgerWithAccount();
    addTearDown(ledger.close);
    final id = spend(ledger, 2000000);
    final debt = ledger.openDebt(
      transactionId: id,
      kind: DebtKind.lent,
      counterparty: 'A friend',
    );

    ledger.removeDebt(debt.id);

    expect(ledger.debts(), isEmpty);
    final restored = ledger.snapshot().transactions.firstWhere(
      (item) => item.id == id,
    );
    expect(
      restored.debtId,
      isNull,
      reason:
          'what happened to the money is unchanged; only the promise is '
          'gone, so it counts as spending again',
    );
  });

  test('a loan needs somebody to owe it', () {
    final ledger = ledgerWithAccount();
    addTearDown(ledger.close);
    expect(
      () => ledger.openDebt(
        transactionId: spend(ledger, 100000),
        kind: DebtKind.lent,
        counterparty: '   ',
      ),
      throwsArgumentError,
    );
  });
}
