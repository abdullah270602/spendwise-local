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
    var income = 0, spending = 0;
    for (final item in snapshot.transactions) {
      if (item.debtId != null) continue;
      if (item.kind == TransactionKind.income) {
        income += item.amount.minorUnits;
      }
      if (item.kind == TransactionKind.expense) {
        spending += item.amount.minorUnits;
      }
    }

    expect(income, greaterThan(0));
    expect(
      spending / income,
      lessThan(0.75),
      reason: 'a month that spent nearly everything draws a sliver',
    );
    expect(
      spending / income,
      greaterThan(0.25),
      reason: 'and one that spent nearly nothing is not anybody real',
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
