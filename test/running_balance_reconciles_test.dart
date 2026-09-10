import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

/// A balance printed beside each entry is the one figure in this app an owner
/// can check against their own bank without trusting a single sum the app
/// makes. That is only true while it reconciles: the last running balance for
/// an account has to be that account's balance, exactly, on every ledger.
///
/// So these do not assert numbers somebody typed into the test. They assert
/// that two independent routes to the same figure agree — the walk forward
/// from the opening balance, and the total the rest of the app reads.
void main() {
  ({LocalLedger ledger, String bank, String pot}) open() {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    final bank = ledger.addAccount(
      name: 'Everyday',
      type: AccountType.bank,
      openingBalanceMinor: 10000000,
    );
    final pot = ledger.addAccount(
      name: 'Emergency fund',
      type: AccountType.savings,
      openingBalanceMinor: 2500000,
    );
    return (ledger: ledger, bank: bank, pot: pot);
  }

  /// The last value the walk produced for [account], in entry order.
  int? lastRunningFor(LocalLedger ledger, String account) {
    final snapshot = ledger.snapshot();
    final running = snapshot.accountRunningBalances();
    int? last;
    for (final item in snapshot.transactions.reversed) {
      final value = running[item.id]?[account];
      if (value != null) last = value;
    }
    return last;
  }

  void expectReconciles(LocalLedger ledger, List<String> accounts) {
    final snapshot = ledger.snapshot();
    for (final account in accounts) {
      final walked = lastRunningFor(ledger, account);
      if (walked == null) continue;
      expect(
        walked,
        snapshot.accountBalanceMinor(account),
        reason: 'the walk and the balance must be the same number',
      );
    }
  }

  test('an empty ledger has nothing to walk', () {
    final (:ledger, :bank, :pot) = open();
    expect(ledger.snapshot().accountRunningBalances(), isEmpty);
    expect(ledger.snapshot().accountBalanceMinor(bank), 10000000);
  });

  test('one entry lands on the balance', () {
    final (:ledger, :bank, :pot) = open();
    final id = ledger.addManualTransaction(
      kind: TransactionKind.expense,
      amountMinor: 1500000,
      occurredAt: DateTime(2026, 9, 3),
      accountId: bank,
      description: 'Groceries',
    );

    final running = ledger.snapshot().accountRunningBalances();
    expect(running[id]![bank], 8500000, reason: '100,000 less 15,000');
    expectReconciles(ledger, [bank, pot]);
  });

  test('it reconciles across every kind of movement', () {
    final (:ledger, :bank, :pot) = open();
    ledger.addManualTransaction(
      kind: TransactionKind.income,
      amountMinor: 20000000,
      occurredAt: DateTime(2026, 9, 1),
      accountId: bank,
      description: 'Salary',
    );
    ledger.addManualTransaction(
      kind: TransactionKind.expense,
      amountMinor: 3000000,
      occurredAt: DateTime(2026, 9, 4),
      accountId: bank,
      description: 'Rent',
    );
    ledger.addManualTransaction(
      kind: TransactionKind.transfer,
      amountMinor: 5000000,
      occurredAt: DateTime(2026, 9, 6),
      // A transfer names both ends. `accountId` alone is the leg it is filed
      // under; the balances move on `fromAccountId` and `toAccountId`.
      accountId: bank,
      fromAccountId: bank,
      toAccountId: pot,
      description: 'To the fund',
    );
    ledger.addManualTransaction(
      kind: TransactionKind.income,
      amountMinor: 400000,
      occurredAt: DateTime(2026, 9, 9),
      accountId: pot,
      description: 'Profit',
    );

    expectReconciles(ledger, [bank, pot]);
    expect(ledger.snapshot().accountBalanceMinor(bank), 22000000);
    expect(ledger.snapshot().accountBalanceMinor(pot), 7900000);
  });

  test('a transfer is recorded against both of its accounts', () {
    // One entry, two balances. Showing only one side would leave the other
    // account looking as though money had appeared in it from nowhere.
    final (:ledger, :bank, :pot) = open();
    final id = ledger.addManualTransaction(
      kind: TransactionKind.transfer,
      amountMinor: 5000000,
      occurredAt: DateTime(2026, 9, 6),
      // A transfer names both ends. `accountId` alone is the leg it is filed
      // under; the balances move on `fromAccountId` and `toAccountId`.
      accountId: bank,
      fromAccountId: bank,
      toAccountId: pot,
      description: 'To the fund',
    );

    final around = ledger.snapshot().accountRunningBalances()[id]!;
    expect(around[bank], 5000000);
    expect(around[pot], 7500000);
  });

  test('entries sharing a timestamp still reconcile', () {
    // Their order between themselves is whatever the query says, and the
    // running figures follow it. The total after all of them does not care.
    final (:ledger, :bank, :pot) = open();
    final at = DateTime(2026, 9, 5, 12);
    for (var i = 0; i < 5; i++) {
      ledger.addManualTransaction(
        kind: TransactionKind.expense,
        amountMinor: 100000,
        occurredAt: at,
        accountId: bank,
        description: 'Round $i',
      );
    }
    expectReconciles(ledger, [bank]);
    expect(ledger.snapshot().accountBalanceMinor(bank), 9500000);
  });

  test('a deleted entry leaves no trace in the walk', () {
    final (:ledger, :bank, :pot) = open();
    final id = ledger.addManualTransaction(
      kind: TransactionKind.expense,
      amountMinor: 1500000,
      occurredAt: DateTime(2026, 9, 3),
      accountId: bank,
      description: 'Groceries',
    );
    ledger.deleteTransaction(id);

    expect(ledger.snapshot().accountRunningBalances()[id], isNull);
    expectReconciles(ledger, [bank]);
    expect(ledger.snapshot().accountBalanceMinor(bank), 10000000);
  });

  test('an entry that reached no account is skipped, not counted as zero', () {
    // An alert that matched nothing has no account to have a balance in.
    // Inventing one would be the app asserting something it cannot know.
    final (:ledger, :bank, :pot) = open();
    final orphan = ledger.addManualTransaction(
      kind: TransactionKind.expense,
      amountMinor: 900000,
      occurredAt: DateTime(2026, 9, 7),
      description: 'Unattached',
    );

    expect(ledger.snapshot().accountRunningBalances()[orphan], isNull);
    expectReconciles(ledger, [bank, pot]);
  });
}
