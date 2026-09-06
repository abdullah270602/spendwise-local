import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/debt_kind.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';
import 'package:spendwise/features/dashboard/home_savings.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart' as view;

/// Money that lands in your account and was never yours.
///
/// A brother sends funds to pass to your father; a friend parks money with
/// you; someone asks you to forward it on. Until now the nearest available
/// answer was "I borrowed it", which is wrong in the one way that matters:
/// borrowed money is yours to spend until you give it back, and this never is.
void main() {
  LocalLedger ledgerWithAccount() {
    final ledger = LocalLedger.openInMemoryForTests();
    ledger.addAccount(name: 'Current', type: AccountType.bank);
    return ledger;
  }

  String arrive(LocalLedger ledger, int minor, {String from = 'My brother'}) =>
      ledger.addManualTransaction(
        kind: TransactionKind.income,
        amountMinor: minor,
        occurredAt: DateTime.utc(2026, 9, 2, 12),
        accountId: ledger.snapshot().accounts.single.id,
        description: from,
      );

  String handOver(LocalLedger ledger, int minor, {String to = 'My father'}) =>
      ledger.addManualTransaction(
        kind: TransactionKind.expense,
        amountMinor: minor,
        occurredAt: DateTime.utc(2026, 9, 7, 12),
        accountId: ledger.snapshot().accounts.single.id,
        description: to,
      );

  group('recording it', () {
    test('holding survives the round trip to storage and back', () {
      // It stores as a borrowing that was never yours -- two columns, because
      // direction and ownership genuinely vary independently -- so the thing
      // worth asserting is that it comes back as itself.
      final ledger = ledgerWithAccount();
      addTearDown(ledger.close);
      final id = arrive(ledger, 16800000);

      final debt = ledger.openDebt(
        transactionId: id,
        kind: DebtKind.holding,
        counterparty: 'My father',
      );

      expect(debt.kind, DebtKind.holding);
      expect(debt.isHeld, isTrue);
      expect(debt.lent, isFalse, reason: 'nobody owes it to you');
      expect(ledger.debt(debt.id)!.kind, DebtKind.holding);
    });

    test('the entry is filed as held, not as borrowed', () {
      final ledger = ledgerWithAccount();
      addTearDown(ledger.close);
      final id = arrive(ledger, 16800000);
      ledger.openDebt(
        transactionId: id,
        kind: DebtKind.holding,
        counterparty: 'My father',
      );

      expect(ledger.transactionCategories()[id], 'Held for someone');
    });

    test('holding money is not income', () {
      // The point of the whole thing: 168,000 arriving does not make you
      // 168,000 richer.
      final ledger = ledgerWithAccount();
      addTearDown(ledger.close);
      final id = arrive(ledger, 16800000);
      ledger.openDebt(
        transactionId: id,
        kind: DebtKind.holding,
        counterparty: 'My father',
      );

      final entry = ledger.snapshot().transactions.firstWhere(
        (item) => item.id == id,
      );
      expect(
        entry.debtId,
        isNotNull,
        reason: 'debt-linked money is not income',
      );
    });

    test('and passing it on is not spending', () {
      final ledger = ledgerWithAccount();
      addTearDown(ledger.close);
      final out = handOver(ledger, 16800000);
      ledger.openDebt(
        transactionId: out,
        kind: DebtKind.holding,
        counterparty: 'My father',
      );

      expect(
        ledger.spendingByCategory(month: DateTime.utc(2026, 9)),
        isEmpty,
        reason: 'you gave away money that was never yours',
      );
    });
  });

  group('what you can spend', () {
    test('held money comes off the top', () {
      final ledger = ledgerWithAccount();
      addTearDown(ledger.close);
      final id = arrive(ledger, 16800000);
      ledger.openDebt(
        transactionId: id,
        kind: DebtKind.holding,
        counterparty: 'My father',
      );

      expect(ledger.heldOutstandingMinor(), 16800000);
    });

    test('borrowed money does not, because it is yours to spend', () {
      // The distinction the third story exists for. Both are money you will
      // hand over; only one of them is yours meanwhile.
      final ledger = ledgerWithAccount();
      addTearDown(ledger.close);
      final id = arrive(ledger, 16800000);
      ledger.openDebt(
        transactionId: id,
        kind: DebtKind.borrowed,
        counterparty: 'My brother',
      );

      expect(ledger.heldOutstandingMinor(), 0);
    });

    test('once it has been passed on it stops being held', () {
      final ledger = ledgerWithAccount();
      addTearDown(ledger.close);
      final id = arrive(ledger, 16800000);
      final debt = ledger.openDebt(
        transactionId: id,
        kind: DebtKind.holding,
        counterparty: 'My father',
      );

      ledger.settleDebt(
        debtId: debt.id,
        amountMinor: 16800000,
        at: DateTime.utc(2026, 9, 7, 12),
      );

      expect(
        ledger.heldOutstandingMinor(),
        0,
        reason: 'the money is with its owner; it is no longer in your account',
      );
    });

    test('a part-handed-over amount only holds back the remainder', () {
      final ledger = ledgerWithAccount();
      addTearDown(ledger.close);
      final id = arrive(ledger, 16800000);
      final debt = ledger.openDebt(
        transactionId: id,
        kind: DebtKind.holding,
        counterparty: 'My father',
      );

      ledger.settleDebt(
        debtId: debt.id,
        amountMinor: 10000000,
        at: DateTime.utc(2026, 9, 5, 12),
      );

      expect(ledger.heldOutstandingMinor(), 6800000);
    });
  });

  group('re-filing history', () {
    test('a borrowing can be corrected to holding', () {
      // Everything recorded before the third story existed is sitting under
      // the nearest wrong answer. Telling someone their history is mis-filed
      // but unfixable would be worse than never offering the story.
      final ledger = ledgerWithAccount();
      addTearDown(ledger.close);
      final id = arrive(ledger, 16800000);
      final debt = ledger.openDebt(
        transactionId: id,
        kind: DebtKind.borrowed,
        counterparty: 'My father',
      );
      expect(ledger.heldOutstandingMinor(), 0);

      final refiled = ledger.changeDebtKind(debt.id, DebtKind.holding);

      expect(refiled.kind, DebtKind.holding);
      expect(ledger.heldOutstandingMinor(), 16800000);
    });

    test('re-filing relabels the entries too', () {
      final ledger = ledgerWithAccount();
      addTearDown(ledger.close);
      final id = arrive(ledger, 16800000);
      final debt = ledger.openDebt(
        transactionId: id,
        kind: DebtKind.borrowed,
        counterparty: 'My father',
      );
      expect(ledger.transactionCategories()[id], 'Borrowed');

      ledger.changeDebtKind(debt.id, DebtKind.holding);

      expect(
        ledger.transactionCategories()[id],
        'Held for someone',
        reason: 'the debt and the entry cannot disagree about what it was',
      );
    });

    test('the amount, date and counterparty are left alone', () {
      // Re-filing, not re-entering. Only what the money *was* changes.
      final ledger = ledgerWithAccount();
      addTearDown(ledger.close);
      final id = arrive(ledger, 16800000);
      final before = ledger.openDebt(
        transactionId: id,
        kind: DebtKind.borrowed,
        counterparty: 'My father',
      );

      final after = ledger.changeDebtKind(before.id, DebtKind.holding);

      expect(after.principalMinor, before.principalMinor);
      expect(after.counterparty, before.counterparty);
      expect(after.openedAt, before.openedAt);
      expect(after.openingTransactionId, before.openingTransactionId);
    });

    test('and it goes back the other way', () {
      final ledger = ledgerWithAccount();
      addTearDown(ledger.close);
      final id = arrive(ledger, 16800000);
      final debt = ledger.openDebt(
        transactionId: id,
        kind: DebtKind.holding,
        counterparty: 'My brother',
      );

      ledger.changeDebtKind(debt.id, DebtKind.borrowed);

      expect(ledger.debt(debt.id)!.kind, DebtKind.borrowed);
      expect(ledger.heldOutstandingMinor(), 0);
    });
  });

  group('on Home', () {
    final from = DateTime(2026, 9, 1);
    final to = DateTime(2026, 10, 1);

    view.TransactionViewData at(
      int day, {
      required view.TransactionKind kind,
      required int minor,
      String? debtId,
    }) => view.TransactionViewData(
      id: '$day-$minor-$kind',
      title: 'x',
      subtitle: 'x',
      amount: view.MoneyViewData(minor),
      kind: kind,
      occurredAt: DateTime(2026, 9, day, 12),
      category: 'Other',
      accountId: 'meezan',
      debtId: debtId,
    );

    test('neither leg of held money reaches the flow', () {
      // It arrives in one period and leaves in another as often as not.
      // Counting it would show a windfall in September and a loss in October,
      // and neither ever happened to the person.
      final ledger = [
        at(
          2,
          kind: view.TransactionKind.income,
          minor: 16800000,
          debtId: 'family',
        ),
        at(
          7,
          kind: view.TransactionKind.expense,
          minor: 16800000,
          debtId: 'family',
        ),
      ];
      const held = {'family'};

      expect(
        debtInflowInWindow(
          transactions: ledger,
          from: from,
          to: to,
          heldDebtIds: held,
        ),
        0,
      );
      expect(
        debtOutflowInWindow(
          transactions: ledger,
          from: from,
          to: to,
          heldDebtIds: held,
        ),
        0,
      );
    });

    test('the arriving month alone is still silent', () {
      // The case that filing it as "borrowed" got wrong: 168,000 lands in
      // September and is passed on in October. Home must not report a
      // 168,000 windfall in between.
      final ledger = [
        at(
          2,
          kind: view.TransactionKind.income,
          minor: 16800000,
          debtId: 'family',
        ),
      ];
      expect(
        debtInflowInWindow(
          transactions: ledger,
          from: from,
          to: to,
          heldDebtIds: const {'family'},
        ),
        0,
      );
      expect(
        debtInflowInWindow(transactions: ledger, from: from, to: to),
        16800000,
        reason: 'filed as an ordinary borrowing it would have counted',
      );
    });

    test('a real loan is untouched by any of this', () {
      final ledger = [
        at(
          4,
          kind: view.TransactionKind.expense,
          minor: 4000000,
          debtId: 'kashif',
        ),
      ];
      expect(
        debtOutflowInWindow(
          transactions: ledger,
          from: from,
          to: to,
          heldDebtIds: const {'family'},
        ),
        4000000,
        reason: 'only the named debts are held',
      );
    });
  });
}
