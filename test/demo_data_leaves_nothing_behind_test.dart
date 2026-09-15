import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

/// Sample data is what the screenshots are made of, so it has to be able to
/// come back out again cleanly. Everything it creates is registered in
/// `demo_entities` and deleted by id — everything, which is easy to get wrong
/// the moment the seed learns to create a new kind of thing.
///
/// It did get it wrong: the demo loan was not registered. `transactions`
/// cascades on a deleted account, but a debt row survives its opening entry
/// being deleted, so every flip of the toggle left another loan behind and
/// the amount the owner supposedly had out with somebody grew by 20,000 a
/// time — on top of a ledger that was meant to be empty.
void main() {
  test('turning sample data off leaves an empty ledger', () {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    ledger.completeOnboarding();

    final ownAccounts = ledger
        .snapshot()
        .accounts
        .where((account) => account.type != AccountType.cash)
        .length;

    ledger.seedDemoData();
    expect(ledger.snapshot().transactions, isNotEmpty);
    expect(ledger.debts(), isNotEmpty, reason: 'the sample month has a loan');

    ledger.removeDemoData();
    expect(ledger.snapshot().transactions, isEmpty);
    expect(
      ledger.debts(),
      isEmpty,
      reason: 'a loan nobody made must not outlive the data that made it',
    );
    expect(
      ledger
          .snapshot()
          .accounts
          .where((account) => account.type != AccountType.cash)
          .length,
      ownAccounts,
    );
  });

  test('and flipping it twice does not double anything', () {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    ledger.completeOnboarding();

    ledger.seedDemoData();
    final loans = ledger.debts().length;
    final entries = ledger.snapshot().transactions.length;

    ledger.removeDemoData();
    ledger.seedDemoData();

    expect(ledger.debts(), hasLength(loans));
    expect(ledger.snapshot().transactions, hasLength(entries));
  });

  test('the sample month is worth looking at', () {
    // It is the app's shop window: the shape on Home divides what came in,
    // so a month that spent almost all of it draws a sliver beside a slab and
    // demonstrates nothing. These are the proportions the screenshots show.
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    ledger.completeOnboarding();
    ledger.seedDemoData();

    final snapshot = ledger.snapshot();
    var income = 0, spending = 0, lentOut = 0, saved = 0;
    final savingsIds = {
      for (final account in snapshot.accounts)
        if (account.type == AccountType.savings) account.id,
    };
    for (final item in snapshot.transactions) {
      final amount = item.amount.minorUnits;
      if (item.debtId != null) {
        if (item.kind == TransactionKind.expense) lentOut += amount;
        continue;
      }
      switch (item.kind) {
        case TransactionKind.income:
          income += amount;
        case TransactionKind.expense:
          spending += amount;
        case TransactionKind.transfer:
          if (savingsIds.contains(item.toAccountId)) saved += amount;
      }
    }

    expect(income, greaterThan(0));

    // The proportion the ribbon actually draws, worked out the way Home
    // works it out: what is still yours against what went, with money put
    // away taken off the kept side. Spending against income was the old
    // proxy for this and measured the wrong thing -- it says nothing about
    // the two branches, which is the entire picture.
    final kept = income - spending - lentOut;
    final aside = saved < kept ? saved : kept;
    final drawnKept = kept - aside;
    final share = drawnKept / (drawnKept + spending);

    expect(
      share,
      greaterThan(0.6),
      reason: 'the app mark is one wide branch against one narrow one',
    );
    expect(
      share,
      lessThan(0.85),
      reason: 'but not so lopsided that the spent branch is a hairline',
    );

    // Deliberately unequal balances: Accounts draws each account to scale.
    final balances =
        snapshot.accounts
            .where((account) => account.type != AccountType.cash)
            .map((account) => snapshot.accountBalanceMinor(account.id))
            .toList()
          ..sort();
    expect(balances.toSet(), hasLength(balances.length));
    expect(
      balances.last,
      greaterThan(balances.first * 4),
      reason: 'a ladder, not a row of similar bars',
    );
  });
}
