import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/debt_kind.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

/// A loan going out already stopped counting as spending. A loan coming back
/// did not stop counting as income, because the only way to settle one was to
/// type an amount into the loan -- which recorded the repayment twice: once
/// as the loan closing, and again as a month where the owner apparently
/// earned the money they had merely got back.
///
/// The exclusion turns on one thing, `debt_id` on the entry. Recording an
/// amount alone never set it. These hold the two paths apart: attaching the
/// entry is what changes the month, and recording an amount is for cash that
/// never touched an account and therefore has no entry to attach.
void main() {
  ({LocalLedger ledger, String account}) open() {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    final account = ledger.addAccount(
      name: 'Everyday',
      type: AccountType.bank,
      openingBalanceMinor: 10000000,
    );
    return (ledger: ledger, account: account);
  }

  /// What the month says, using the same rule the dashboard uses: an entry
  /// attached to a loan is neither income nor spending.
  ({int income, int spending}) month(LocalLedger ledger) {
    var income = 0, spending = 0;
    for (final item in ledger.snapshot().transactions) {
      if (item.debtId != null) continue;
      if (item.kind == TransactionKind.income) {
        income += item.amount.minorUnits;
      }
      if (item.kind == TransactionKind.expense) {
        spending += item.amount.minorUnits;
      }
    }
    return (income: income, spending: spending);
  }

  String lend(LocalLedger ledger, String account, int amount) =>
      ledger.addManualTransaction(
        kind: TransactionKind.expense,
        amountMinor: amount,
        occurredAt: DateTime(2026, 9, 2),
        accountId: account,
        description: 'To Sana',
      );

  String repaid(LocalLedger ledger, String account, int amount) =>
      ledger.addManualTransaction(
        kind: TransactionKind.income,
        amountMinor: amount,
        occurredAt: DateTime(2026, 9, 20),
        accountId: account,
        description: 'From Sana',
      );

  test('lending it out is not spending', () {
    final (:ledger, :account) = open();
    final out = lend(ledger, account, 5000000);
    expect(month(ledger).spending, 5000000, reason: 'until it is called one');

    ledger.openDebt(
      transactionId: out,
      kind: DebtKind.lent,
      counterparty: 'Sana',
    );
    expect(month(ledger).spending, 0);
  });

  test('the repayment stops counting as income once it is attached', () {
    // The whole point. Before this path existed the loan closed and the
    // month still showed the money as earned.
    final (:ledger, :account) = open();
    final out = lend(ledger, account, 5000000);
    final debt = ledger.openDebt(
      transactionId: out,
      kind: DebtKind.lent,
      counterparty: 'Sana',
    );
    final back = repaid(ledger, account, 5000000);
    expect(month(ledger).income, 5000000, reason: 'not yet attached');

    ledger.settleDebt(
      debtId: debt.id,
      amountMinor: 5000000,
      transactionId: back,
    );

    expect(month(ledger).income, 0, reason: 'it came back, it was not earned');
    expect(month(ledger).spending, 0);
    expect(ledger.debt(debt.id)!.isSettled, isTrue);
    expect(ledger.debt(debt.id)!.outstandingMinor, 0);
  });

  test('and the balance is untouched by any of it', () {
    // Attaching an entry to a loan changes what the money means, never how
    // much of it there is.
    final (:ledger, :account) = open();
    final out = lend(ledger, account, 5000000);
    final debt = ledger.openDebt(
      transactionId: out,
      kind: DebtKind.lent,
      counterparty: 'Sana',
    );
    final back = repaid(ledger, account, 5000000);
    final before = ledger.snapshot().accountBalanceMinor(account);

    ledger.settleDebt(
      debtId: debt.id,
      amountMinor: 5000000,
      transactionId: back,
    );

    expect(ledger.snapshot().accountBalanceMinor(account), before);
    expect(before, 10000000, reason: 'out and back again');
  });

  test('a part payment leaves the loan open with the rest still out', () {
    final (:ledger, :account) = open();
    final out = lend(ledger, account, 5000000);
    final debt = ledger.openDebt(
      transactionId: out,
      kind: DebtKind.lent,
      counterparty: 'Sana',
    );
    final half = repaid(ledger, account, 2000000);

    ledger.settleDebt(
      debtId: debt.id,
      amountMinor: 2000000,
      transactionId: half,
    );

    expect(ledger.debt(debt.id)!.outstandingMinor, 3000000);
    expect(ledger.debt(debt.id)!.isSettled, isFalse);
    expect(month(ledger).income, 0, reason: 'the part that arrived was a loan');
  });

  test('two part payments close it between them', () {
    final (:ledger, :account) = open();
    final out = lend(ledger, account, 5000000);
    final debt = ledger.openDebt(
      transactionId: out,
      kind: DebtKind.lent,
      counterparty: 'Sana',
    );
    final first = repaid(ledger, account, 2000000);
    final second = repaid(ledger, account, 3000000);

    ledger.settleDebt(
      debtId: debt.id,
      amountMinor: 2000000,
      transactionId: first,
    );
    ledger.settleDebt(
      debtId: debt.id,
      amountMinor: 3000000,
      transactionId: second,
    );

    expect(ledger.debt(debt.id)!.isSettled, isTrue);
    expect(month(ledger).income, 0);
  });

  test('cash in hand settles the loan and leaves the month alone', () {
    // The other path, and it is correct: money handed over in notes sends no
    // alert, so there is no entry to attach and nothing in the month to take
    // out. The loan closing is the entire record of it.
    final (:ledger, :account) = open();
    final out = lend(ledger, account, 5000000);
    final debt = ledger.openDebt(
      transactionId: out,
      kind: DebtKind.lent,
      counterparty: 'Sana',
    );

    ledger.settleDebt(debtId: debt.id, amountMinor: 5000000);

    expect(ledger.debt(debt.id)!.isSettled, isTrue);
    expect(month(ledger).income, 0, reason: 'nothing arrived in an account');
    expect(
      ledger.snapshot().accountBalanceMinor(account),
      5000000,
      reason: 'the notes are in a pocket, not in the bank',
    );
  });

  test('money you borrowed and paid back is not spending either', () {
    final (:ledger, :account) = open();
    final borrowed = ledger.addManualTransaction(
      kind: TransactionKind.income,
      amountMinor: 3000000,
      occurredAt: DateTime(2026, 9, 2),
      accountId: account,
      description: 'From Omar',
    );
    final debt = ledger.openDebt(
      transactionId: borrowed,
      kind: DebtKind.borrowed,
      counterparty: 'Omar',
    );
    final paid = ledger.addManualTransaction(
      kind: TransactionKind.expense,
      amountMinor: 3000000,
      occurredAt: DateTime(2026, 9, 25),
      accountId: account,
      description: 'To Omar',
    );

    ledger.settleDebt(
      debtId: debt.id,
      amountMinor: 3000000,
      transactionId: paid,
    );

    expect(month(ledger).income, 0, reason: 'borrowing is not earning');
    expect(month(ledger).spending, 0, reason: 'repaying is not spending');
    expect(ledger.debt(debt.id)!.isSettled, isTrue);
  });

  test('passing on held money is not spending, and never was income', () {
    final (:ledger, :account) = open();
    final arrived = ledger.addManualTransaction(
      kind: TransactionKind.income,
      amountMinor: 4000000,
      occurredAt: DateTime(2026, 9, 3),
      accountId: account,
      description: 'From Bilal',
    );
    final debt = ledger.openDebt(
      transactionId: arrived,
      kind: DebtKind.holding,
      counterparty: 'Bilal',
    );
    expect(
      ledger.heldOutstandingMinor(),
      4000000,
      reason: 'it is in the bank and it is not theirs',
    );

    final onward = ledger.addManualTransaction(
      kind: TransactionKind.expense,
      amountMinor: 4000000,
      occurredAt: DateTime(2026, 9, 4),
      accountId: account,
      description: 'To Bilal father',
    );
    ledger.settleDebt(
      debtId: debt.id,
      amountMinor: 4000000,
      transactionId: onward,
    );

    expect(month(ledger).income, 0);
    expect(month(ledger).spending, 0);
    expect(
      ledger.heldOutstandingMinor(),
      0,
      reason: 'it has gone where it belonged',
    );
  });

  test('the entry is stamped with the loan and locked against drift', () {
    final (:ledger, :account) = open();
    final out = lend(ledger, account, 5000000);
    final debt = ledger.openDebt(
      transactionId: out,
      kind: DebtKind.lent,
      counterparty: 'Sana',
    );
    final back = repaid(ledger, account, 5000000);
    ledger.settleDebt(
      debtId: debt.id,
      amountMinor: 5000000,
      transactionId: back,
    );

    final entry = ledger.snapshot().transactions.firstWhere(
      (item) => item.id == back,
    );
    expect(entry.debtId, debt.id);
    expect(entry.needsReview, isFalse, reason: 'the owner just answered it');
    expect(
      entry.locked,
      isTrue,
      reason: 'a later re-parse must not take the loan back off it',
    );
  });
}
