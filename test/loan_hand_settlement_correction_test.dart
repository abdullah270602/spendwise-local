import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/debt_kind.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';
import 'package:spendwise/features/debts/debt_matching.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart' as ui;

/// The trap this exists to undo: a loan settled by typing the figure into it.
///
/// That is the right record for cash, which sends no alert. For money that
/// arrived in an account it records the same money twice -- the loan says it
/// came home, and the entry that brought it home is still sitting in the
/// month as income. And because every way of attaching an entry looks for a
/// loan with money still out, settling by hand used to close the only door
/// back: the loan read settled, the month stayed wrong, and nothing on any
/// screen could reach either fact.
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

  int income(LocalLedger ledger) => ledger
      .snapshot()
      .transactions
      .where(
        (item) => item.kind == TransactionKind.income && item.debtId == null,
      )
      .fold<int>(0, (sum, item) => sum + item.amount.minorUnits);

  ({String debt, String entry}) lentAndRepaid(
    LocalLedger ledger,
    String account, {
    int principal = 5000000,
    int back = 5000000,
  }) {
    final out = ledger.addManualTransaction(
      kind: TransactionKind.expense,
      amountMinor: principal,
      occurredAt: DateTime(2026, 9, 2),
      accountId: account,
      description: 'To Sana',
    );
    final debt = ledger.openDebt(
      transactionId: out,
      kind: DebtKind.lent,
      counterparty: 'Sana',
    );
    final entry = ledger.addManualTransaction(
      kind: TransactionKind.income,
      amountMinor: back,
      occurredAt: DateTime(2026, 9, 20),
      accountId: account,
      description: 'From Sana',
    );
    return (debt: debt.id, entry: entry);
  }

  test('settling by hand leaves the entry counted, which is the trap', () {
    final (:ledger, :account) = open();
    final (:debt, :entry) = lentAndRepaid(ledger, account);

    ledger.settleDebt(debtId: debt, amountMinor: 5000000);

    expect(ledger.debt(debt)!.isSettled, isTrue);
    expect(income(ledger), 5000000, reason: 'the money is recorded twice');
    expect(ledger.debt(debt)!.settledByHandMinor, 5000000);
  });

  test('the entry can be recorded afterwards, and replaces what was typed', () {
    final (:ledger, :account) = open();
    final (:debt, :entry) = lentAndRepaid(ledger, account);
    ledger.settleDebt(debtId: debt, amountMinor: 5000000);

    ledger.settleDebt(
      debtId: debt,
      amountMinor: 5000000,
      transactionId: entry,
      replacingByHand: true,
    );

    expect(income(ledger), 0, reason: 'it came back, it was not earned');
    expect(
      ledger.debt(debt)!.settledMinor,
      5000000,
      reason: 'once, not twice: the typed figure was the same money',
    );
    expect(ledger.debt(debt)!.settledByHandMinor, 0);
    expect(ledger.debt(debt)!.isSettled, isTrue);
    expect(ledger.debt(debt)!.outstandingMinor, 0);
  });

  test('a genuine cash payment beside it is not thrown away', () {
    // Half came back in notes and half by transfer. Both records are true,
    // and correcting one must not delete the other.
    final (:ledger, :account) = open();
    final (:debt, :entry) = lentAndRepaid(ledger, account, back: 3000000);
    ledger.settleDebt(debtId: debt, amountMinor: 2000000);

    ledger.settleDebt(
      debtId: debt,
      amountMinor: 3000000,
      transactionId: entry,
      replacingByHand: true,
    );

    expect(ledger.debt(debt)!.settledMinor, 5000000);
    expect(
      ledger.debt(debt)!.settledByHandMinor,
      2000000,
      reason: 'the notes really did change hands',
    );
    expect(income(ledger), 0);
    expect(ledger.debt(debt)!.isSettled, isTrue);
  });

  test('an entry that fits what is still out displaces nothing', () {
    // The loan is still open here, so the entry has somewhere of its own to
    // go and the hand record is not what it is accounting for. Two payments,
    // two records -- and the correction flow is never even offered on a loan
    // in this state.
    final (:ledger, :account) = open();
    final (:debt, :entry) = lentAndRepaid(ledger, account, back: 2000000);
    ledger.settleDebt(debtId: debt, amountMinor: 2000000);
    expect(ledger.debt(debt)!.outstandingMinor, 3000000);

    ledger.settleDebt(
      debtId: debt,
      amountMinor: 2000000,
      transactionId: entry,
      replacingByHand: true,
    );

    expect(ledger.debt(debt)!.settledMinor, 4000000);
    expect(ledger.debt(debt)!.settledByHandMinor, 2000000);
    expect(ledger.debt(debt)!.outstandingMinor, 1000000);
    expect(income(ledger), 0, reason: 'the entry is attached either way');
  });

  test('a mistyped record is corrected only as far as the entry reaches', () {
    // Somebody typed the whole loan in when only part of it had arrived by
    // transfer. Attaching that transfer corrects that much of the record and
    // no more: deleting the rest would be the app deciding the remainder
    // never happened, which it has no way to know.
    final (:ledger, :account) = open();
    final (:debt, :entry) = lentAndRepaid(ledger, account, back: 2000000);
    ledger.settleDebt(debtId: debt, amountMinor: 5000000);
    expect(ledger.debt(debt)!.isSettled, isTrue);

    ledger.settleDebt(
      debtId: debt,
      amountMinor: 2000000,
      transactionId: entry,
      replacingByHand: true,
    );

    expect(
      ledger.debt(debt)!.settledMinor,
      5000000,
      reason: 'the same total, 2,000,000 of it now attached to the entry',
    );
    expect(ledger.debt(debt)!.settledByHandMinor, 3000000);
    expect(ledger.debt(debt)!.isSettled, isTrue);
    expect(income(ledger), 0, reason: 'the entry is out of the month');
  });

  test('a loan written off reopens when money turns up after all', () {
    // "Call it settled" is the owner deciding it is never coming back. If
    // some of it then does, the loan has to stop reading as settled: a
    // closed loan with money still out is the one nobody goes back to check.
    final (:ledger, :account) = open();
    final (:debt, :entry) = lentAndRepaid(ledger, account, back: 2000000);
    ledger.closeDebt(debt);
    expect(ledger.debt(debt)!.isSettled, isTrue);
    expect(ledger.debt(debt)!.outstandingMinor, 5000000);

    ledger.settleDebt(debtId: debt, amountMinor: 2000000, transactionId: entry);

    expect(ledger.debt(debt)!.isSettled, isFalse);
    expect(ledger.debt(debt)!.outstandingMinor, 3000000);
    expect(income(ledger), 0);
  });

  test('without the flag nothing is replaced', () {
    // The ordinary path must not quietly rewrite anybody's records.
    final (:ledger, :account) = open();
    final (:debt, :entry) = lentAndRepaid(ledger, account);
    ledger.settleDebt(debtId: debt, amountMinor: 5000000);

    ledger.settleDebt(debtId: debt, amountMinor: 5000000, transactionId: entry);

    expect(
      ledger.debt(debt)!.settledMinor,
      10000000,
      reason: 'both records stand, which is why the flag exists',
    );
    expect(ledger.debt(debt)!.settledByHandMinor, 5000000);
  });

  group('the screens can find it again', () {
    ui.DebtViewData settledByHand({int byHand = 5000000}) => ui.DebtViewData(
      id: 'loan',
      kind: DebtKind.lent,
      counterparty: 'Sana',
      principal: const ui.MoneyViewData(5000000),
      settled: const ui.MoneyViewData(5000000),
      settledByHand: ui.MoneyViewData(byHand),
      outstanding: const ui.MoneyViewData(0),
      openedAt: DateTime(2026, 9, 2),
      isSettled: true,
    );

    ui.TransactionViewData entry({int amount = 5000000}) =>
        ui.TransactionViewData(
          id: 'back',
          title: 'From Sana',
          subtitle: 'Everyday',
          amount: ui.MoneyViewData(amount),
          kind: ui.TransactionKind.income,
          occurredAt: DateTime(2026, 9, 20),
          category: 'Uncategorised',
        );

    test('the entry is offered against the loan settled by hand', () {
      final found = debtMatchesFor(
        transaction: entry(),
        debts: [settledByHand()],
      );
      expect(found, hasLength(1));
      expect(
        found.single.reason,
        contains('already recorded by hand'),
        reason: 'saying "what is still out" would be nonsense here',
      );
    });

    test('and the loan is offered the entry', () {
      final found = entriesMatching(
        debt: settledByHand(),
        transactions: [entry()],
      );
      expect(found.map((item) => item.id), ['back']);
    });

    test('but only up to what was typed in', () {
      // A loan settled entirely from real entries has nothing to correct,
      // and must not start suggesting that ordinary income belongs to it.
      final settledProperly = settledByHand(byHand: 0);
      expect(
        debtMatchesFor(transaction: entry(), debts: [settledProperly]),
        isEmpty,
      );
      expect(
        entriesMatching(debt: settledProperly, transactions: [entry()]),
        isEmpty,
      );
    });

    test('the picker offers it too', () {
      final open = debtsOpenTo(
        transaction: entry(),
        debts: [settledByHand(), settledByHand(byHand: 0)],
      );
      expect(open, hasLength(1), reason: 'only the one with something to fix');
    });
  });
}
