import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/spendwise_controller.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart' as domain;
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// The Review answer, end to end. A rule that names the right loan is worth
/// nothing if the decision behind it does not carry the entry: the ledger
/// takes an entry out of the month by its `debt_id` and by nothing else, so
/// an answer that settles the loan without stamping the entry leaves the
/// month claiming the owner earned money they only got back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ({LocalLedger ledger, String account}) open() {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    final account = ledger.addAccount(
      name: 'Everyday',
      type: domain.AccountType.bank,
      openingBalanceMinor: 10000000,
    );
    return (ledger: ledger, account: account);
  }

  /// Built after the ledger is arranged: it takes its snapshot on
  /// construction, and there is no public way to make it take another.
  SpendWiseController controllerOn(LocalLedger ledger) {
    final controller = SpendWiseController.forTests(ledger);
    addTearDown(controller.dispose);
    return controller;
  }

  test(
    'answering the loan question takes the money out of the month',
    () async {
      final (:ledger, :account) = open();
      final out = ledger.addManualTransaction(
        kind: domain.TransactionKind.expense,
        amountMinor: 5000000,
        occurredAt: DateTime.now().subtract(const Duration(days: 8)),
        accountId: account,
        description: 'To Sana',
      );
      final debt = ledger.openDebt(
        transactionId: out,
        kind: DebtKind.lent,
        counterparty: 'Sana',
      );
      final back = ledger.addManualTransaction(
        kind: domain.TransactionKind.income,
        amountMinor: 5000000,
        occurredAt: DateTime.now(),
        accountId: account,
        description: 'From Sana',
      );
      final controller = controllerOn(ledger);
      expect(
        controller.dashboard.incomeThisMonth.minorUnits,
        5000000,
        reason: 'until it is answered it reads as money earned',
      );

      await controller.applyReviewDecision(
        ReviewDecision(
          kind: ReviewDecisionKind.settleLoan,
          transactionIds: [back],
          debtId: debt.id,
        ),
      );

      expect(controller.dashboard.incomeThisMonth.minorUnits, 0);
      expect(ledger.debt(debt.id)!.isSettled, isTrue);
      expect(ledger.debt(debt.id)!.outstandingMinor, 0);
    },
  );

  test('two payments in one answer both land on the loan', () async {
    final (:ledger, :account) = open();
    final out = ledger.addManualTransaction(
      kind: domain.TransactionKind.expense,
      amountMinor: 5000000,
      occurredAt: DateTime.now().subtract(const Duration(days: 8)),
      accountId: account,
      description: 'To Sana',
    );
    final debt = ledger.openDebt(
      transactionId: out,
      kind: DebtKind.lent,
      counterparty: 'Sana',
    );
    final first = ledger.addManualTransaction(
      kind: domain.TransactionKind.income,
      amountMinor: 2000000,
      occurredAt: DateTime.now(),
      accountId: account,
      description: 'From Sana',
    );
    final second = ledger.addManualTransaction(
      kind: domain.TransactionKind.income,
      amountMinor: 3000000,
      occurredAt: DateTime.now(),
      accountId: account,
      description: 'From Sana',
    );
    final controller = controllerOn(ledger);

    await controller.applyReviewDecision(
      ReviewDecision(
        kind: ReviewDecisionKind.settleLoan,
        transactionIds: [first, second],
        debtId: debt.id,
      ),
    );

    expect(controller.dashboard.incomeThisMonth.minorUnits, 0);
    expect(ledger.debt(debt.id)!.settledMinor, 5000000);
    expect(ledger.debt(debt.id)!.isSettled, isTrue);
  });

  test('each entry lands for its own amount, not the loan balance', () async {
    // A part payment must leave the rest of the loan out, and must leave the
    // rest of the month alone.
    final (:ledger, :account) = open();
    final out = ledger.addManualTransaction(
      kind: domain.TransactionKind.expense,
      amountMinor: 5000000,
      occurredAt: DateTime.now().subtract(const Duration(days: 8)),
      accountId: account,
      description: 'To Sana',
    );
    final debt = ledger.openDebt(
      transactionId: out,
      kind: DebtKind.lent,
      counterparty: 'Sana',
    );
    final part = ledger.addManualTransaction(
      kind: domain.TransactionKind.income,
      amountMinor: 2000000,
      occurredAt: DateTime.now(),
      accountId: account,
      description: 'From Sana',
    );
    final salary = ledger.addManualTransaction(
      kind: domain.TransactionKind.income,
      amountMinor: 9000000,
      occurredAt: DateTime.now(),
      accountId: account,
      description: 'Salary',
    );
    final controller = controllerOn(ledger);

    await controller.applyReviewDecision(
      ReviewDecision(
        kind: ReviewDecisionKind.settleLoan,
        transactionIds: [part],
        debtId: debt.id,
      ),
    );

    expect(ledger.debt(debt.id)!.outstandingMinor, 3000000);
    expect(ledger.debt(debt.id)!.isSettled, isFalse);
    expect(
      controller.dashboard.incomeThisMonth.minorUnits,
      9000000,
      reason: 'the salary is still income',
    );
    expect(
      ledger
          .snapshot()
          .transactions
          .firstWhere((item) => item.id == salary)
          .debtId,
      isNull,
    );
  });

  test('an answer with no loan is refused rather than half applied', () async {
    final (:ledger, :account) = open();
    final back = ledger.addManualTransaction(
      kind: domain.TransactionKind.income,
      amountMinor: 5000000,
      occurredAt: DateTime.now(),
      accountId: account,
      description: 'From Sana',
    );
    final controller = controllerOn(ledger);

    await expectLater(
      controller.applyReviewDecision(
        ReviewDecision(
          kind: ReviewDecisionKind.settleLoan,
          transactionIds: [back],
        ),
      ),
      throwsArgumentError,
    );
  });
}
