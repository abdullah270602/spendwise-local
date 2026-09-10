import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/spendwise_controller.dart';
import 'package:spendwise/core/debt_kind.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart' as domain;

/// Money you are holding for somebody else has to come off what you can
/// spend, because a balance is not a permission. But the subtraction is only
/// right where the money actually is.
///
/// Both screens took the whole held total off the everyday accounts, wherever
/// it had landed. A relative's funds paid straight into a savings account are
/// not in the everyday total to begin with, so taking them off it showed the
/// owner less of their own money than they had — and the two screens agreed
/// with each other while both being wrong, which is the hardest kind of wrong
/// to notice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ({SpendWiseController controller, String everyday, String pot}) ledgerWith({
    required bool heldGoesToSavings,
  }) {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    final everyday = ledger.addAccount(
      name: 'Everyday',
      type: domain.AccountType.bank,
      openingBalanceMinor: 10000000,
    );
    final pot = ledger.addAccount(
      name: 'Emergency fund',
      type: domain.AccountType.savings,
      openingBalanceMinor: 0,
    );

    // Somebody else's 50,000, landing in one account or the other.
    final arrived = ledger.addManualTransaction(
      kind: domain.TransactionKind.income,
      amountMinor: 5000000,
      occurredAt: DateTime.now(),
      accountId: heldGoesToSavings ? pot : everyday,
      description: 'From Bilal',
    );
    ledger.openDebt(
      transactionId: arrived,
      kind: DebtKind.holding,
      counterparty: 'Bilal',
    );

    final controller = SpendWiseController.forTests(ledger);
    addTearDown(controller.dispose);
    return (controller: controller, everyday: everyday, pot: pot);
  }

  /// What the screens do: the everyday total, less the held money that is
  /// actually in it.
  int availableToSpend(SpendWiseController controller) {
    final spendable = {
      for (final account in controller.accounts)
        if (account.isIncluded) account.id,
    };
    final everydayTotal = controller.accounts
        .where((account) => account.isIncluded)
        .fold<int>(0, (sum, account) => sum + account.balance.minorUnits);
    final held = controller.debts
        .where(
          (item) =>
              item.isHeld &&
              !item.isSettled &&
              (item.accountId == null || spendable.contains(item.accountId)),
        )
        .fold<int>(0, (sum, item) => sum + item.outstanding.minorUnits);
    return everydayTotal - held;
  }

  test('a loan knows which account its money landed in', () {
    final (:controller, :everyday, :pot) = ledgerWith(heldGoesToSavings: false);
    final held = controller.debts.single;
    expect(held.accountId, everyday);
  });

  test('held money in an everyday account comes off what you can spend', () {
    final (:controller, :everyday, :pot) = ledgerWith(heldGoesToSavings: false);
    // 100,000 of their own plus 50,000 of somebody else's, in one account.
    expect(
      availableToSpend(controller),
      10000000,
      reason: 'the 50,000 is in the account and is not theirs',
    );
  });

  test('held money in savings does not come off the everyday total', () {
    // It was never in that total. Subtracting it there told the owner they
    // had 50,000 less of their own money than they did.
    final (:controller, :everyday, :pot) = ledgerWith(heldGoesToSavings: true);
    expect(controller.debts.single.accountId, pot);
    expect(
      availableToSpend(controller),
      10000000,
      reason: 'their everyday money is untouched by what sits in savings',
    );
  });

  test('and once it is handed on, what can be spent does not move', () {
    // Passing it on takes the same amount off the account and off the
    // holding, so the figure between them must sit still. If it moved, the
    // owner would see money appear or vanish for doing the honest thing.
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    final everyday = ledger.addAccount(
      name: 'Everyday',
      type: domain.AccountType.bank,
      openingBalanceMinor: 10000000,
    );
    final arrived = ledger.addManualTransaction(
      kind: domain.TransactionKind.income,
      amountMinor: 5000000,
      occurredAt: DateTime.now(),
      accountId: everyday,
      description: 'From Bilal',
    );
    final held = ledger.openDebt(
      transactionId: arrived,
      kind: DebtKind.holding,
      counterparty: 'Bilal',
    );

    final before = SpendWiseController.forTests(ledger);
    addTearDown(before.dispose);
    expect(availableToSpend(before), 10000000);

    final onward = ledger.addManualTransaction(
      kind: domain.TransactionKind.expense,
      amountMinor: 5000000,
      occurredAt: DateTime.now(),
      accountId: everyday,
      description: 'To Bilal father',
    );
    ledger.settleDebt(
      debtId: held.id,
      amountMinor: 5000000,
      transactionId: onward,
    );

    final after = SpendWiseController.forTests(ledger);
    addTearDown(after.dispose);
    expect(
      availableToSpend(after),
      10000000,
      reason: 'the account fell by 50,000 and so did what was owed',
    );
  });
}
