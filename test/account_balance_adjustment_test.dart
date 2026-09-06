import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

/// Correcting an account's balance used to move the opening balance and say
/// nothing. The account then read correctly while explaining nothing: the
/// ledger showed no reason for the change, and Home — which is a picture of
/// what came in and what went out — could not see it at all.
void main() {
  ({LocalLedger ledger, String account}) openLedger() {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    final account = ledger.addAccount(
      name: 'Current account',
      type: AccountType.bank,
      openingBalanceMinor: 100000,
    );
    ledger.addManualTransaction(
      kind: TransactionKind.expense,
      amountMinor: 10000,
      occurredAt: DateTime.utc(2026, 8, 22),
      accountId: account,
      description: 'Purchase',
    );
    return (ledger: ledger, account: account);
  }

  test('the balance lands exactly where the bank says', () {
    final (:ledger, :account) = openLedger();
    expect(ledger.snapshot().accountBalanceMinor(account), 90000);

    ledger.setAccountCurrentBalance(
      id: account,
      currentBalanceMinor: 90000,
      targetBalanceMinor: 125000,
    );

    expect(ledger.snapshot().accountBalanceMinor(account), 125000);
  });

  test('and the correction is visible, with a reason', () {
    final (:ledger, :account) = openLedger();
    ledger.setAccountCurrentBalance(
      id: account,
      currentBalanceMinor: 90000,
      targetBalanceMinor: 125000,
    );

    final entries = ledger.snapshot().transactions;
    expect(entries, hasLength(2), reason: 'the purchase, and the correction');
    final adjustment = entries.firstWhere(
      (item) => item.description == 'Balance adjustment',
    );
    expect(adjustment.amount.minorUnits, 35000);
    expect(adjustment.kind, TransactionKind.income, reason: 'money appeared');
    expect(adjustment.accountId, account);
  });

  test('money that has gone missing is an expense', () {
    final (:ledger, :account) = openLedger();
    ledger.setAccountCurrentBalance(
      id: account,
      currentBalanceMinor: 90000,
      targetBalanceMinor: 77510,
    );

    final adjustment = ledger.snapshot().transactions.firstWhere(
      (item) => item.description == 'Balance adjustment',
    );
    expect(adjustment.kind, TransactionKind.expense);
    expect(adjustment.amount.minorUnits, 12490);
    expect(ledger.snapshot().accountBalanceMinor(account), 77510);
  });

  test('existing transactions are left exactly as they were', () {
    final (:ledger, :account) = openLedger();
    ledger.setAccountCurrentBalance(
      id: account,
      currentBalanceMinor: 90000,
      targetBalanceMinor: 125000,
    );

    final purchase = ledger.snapshot().transactions.firstWhere(
      (item) => item.description == 'Purchase',
    );
    expect(purchase.amount.minorUnits, 10000);
    expect(purchase.kind, TransactionKind.expense);
  });

  test('agreeing with the bank writes nothing', () {
    // Confirming the balance you already have is not an event.
    final (:ledger, :account) = openLedger();
    ledger.setAccountCurrentBalance(
      id: account,
      currentBalanceMinor: 90000,
      targetBalanceMinor: 90000,
    );

    expect(ledger.snapshot().transactions, hasLength(1));
  });

  test('the correction survives a reconcile', () {
    // It is written as a manual entry precisely so that rebuilding every
    // automatic transaction cannot quietly undo it.
    final (:ledger, :account) = openLedger();
    ledger.setAccountCurrentBalance(
      id: account,
      currentBalanceMinor: 90000,
      targetBalanceMinor: 125000,
    );

    ledger.reconcilePendingEvidence();

    expect(ledger.snapshot().accountBalanceMinor(account), 125000);
    expect(
      ledger.snapshot().transactions.where(
        (item) => item.description == 'Balance adjustment',
      ),
      hasLength(1),
    );
  });

  test('two corrections in a row both land', () {
    final (:ledger, :account) = openLedger();
    ledger.setAccountCurrentBalance(
      id: account,
      currentBalanceMinor: 90000,
      targetBalanceMinor: 125000,
    );
    ledger.setAccountCurrentBalance(
      id: account,
      currentBalanceMinor: 125000,
      targetBalanceMinor: 60000,
    );

    expect(ledger.snapshot().accountBalanceMinor(account), 60000);
    expect(
      ledger.snapshot().transactions.where(
        (item) => item.description == 'Balance adjustment',
      ),
      hasLength(2),
    );
  });
}
