import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

void main() {
  test('notification evidence is categorized from its raw merchant text', () {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    ledger.rememberAndroidSources([
      {
        'packageName': 'pk.example.bank',
        'label': 'Example Bank',
        'configured': true,
      },
    ]);
    final source = ledger.sources().single;
    ledger.addAccount(
      name: 'Current account',
      type: AccountType.bank,
      sourceIds: [source.id],
    );

    expect(
      ledger.ingestNotification({
        'notificationKey': 'bank:44',
        'snapshotHash': 'snapshot:netflix',
        'packageName': 'pk.example.bank',
        'postedAt': DateTime.utc(2026, 8, 22).millisecondsSinceEpoch,
        'title': 'Card purchase',
        'text': 'Your account was debited PKR 1,500 at NETFLIX.COM',
      }),
      isTrue,
    );

    final transaction = ledger.snapshot().transactions.single;
    expect(transaction.kind, TransactionKind.expense);
    expect(ledger.transactionCategories()[transaction.id], 'Entertainment');
  });

  test('system categories include entertainment and subscriptions', () {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    final names = ledger.categories().map((category) => category.name).toSet();
    expect(names, contains('Entertainment'));
    expect(names, contains('Subscriptions & digital services'));
    expect(names, contains('Bills & utilities'));
    expect(names, contains('Income'));
  });

  test('archiving and restoring an account preserves history and sources', () {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    ledger.rememberAndroidSources([
      {
        'packageName': 'pk.example.bank',
        'label': 'Example Bank',
        'configured': true,
      },
    ]);
    final source = ledger.sources().single;
    final account = ledger.addAccount(
      name: 'Daily',
      type: AccountType.bank,
      sourceIds: [source.id],
    );
    ledger.addManualTransaction(
      kind: TransactionKind.expense,
      amountMinor: 25000,
      occurredAt: DateTime.utc(2026, 8, 22),
      accountId: account,
      description: 'Dinner',
    );

    ledger.archiveAccount(account);

    expect(ledger.snapshot().accounts, isEmpty);
    expect(ledger.sources(accountId: account), hasLength(1));
    expect(ledger.snapshot().transactions, hasLength(1));
    expect(ledger.latestArchivedAccount()?.id, account);

    ledger.restoreAccount(account);

    expect(ledger.snapshot().accounts, hasLength(1));
    expect(ledger.sources(accountId: account), hasLength(1));
    expect(ledger.snapshot().transactions, hasLength(1));
  });

  test('savings are tracked without inflating the spendable balance', () {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    final daily = ledger.addAccount(
      name: 'Daily',
      type: AccountType.bank,
      openingBalanceMinor: 2500000,
    );
    final savings = ledger.addAccount(
      name: 'Emergency fund',
      type: AccountType.savings,
      openingBalanceMinor: 10000000,
    );

    var snapshot = ledger.snapshot();
    expect(snapshot.accountBalanceMinor(daily), 2500000);
    expect(snapshot.accountBalanceMinor(savings), 10000000);
    expect(snapshot.spendableBalanceMinor, 2500000);
    expect(snapshot.savingsBalanceMinor, 10000000);
    expect(snapshot.netWorthMinor, 12500000);

    ledger.addManualTransaction(
      kind: TransactionKind.transfer,
      amountMinor: 500000,
      occurredAt: DateTime.utc(2026, 8, 22),
      fromAccountId: daily,
      toAccountId: savings,
      description: 'Move to savings',
    );

    snapshot = ledger.snapshot();
    expect(snapshot.spendableBalanceMinor, 2000000);
    expect(snapshot.savingsBalanceMinor, 10500000);
    expect(snapshot.netWorthMinor, 12500000);
  });
}
