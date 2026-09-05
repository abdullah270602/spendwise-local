import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

void main() {
  test('own names persist through the ledger settings store', () {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);

    expect(ledger.ownNames, isEmpty);
    ledger.setOwnNames(['Abdullah Naseem', '  ', 'A. Naseem']);
    expect(ledger.ownNames, ['Abdullah Naseem', 'A. Naseem']);
  });

  test('the transfer category is labelled for the user\'s own accounts', () {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);

    final transferCategory = ledger.categories().singleWhere(
      (category) => category.id == 'transfer',
    );
    expect(transferCategory.name, 'Between your accounts');
  });

  Map<String, String> setUpUblAndMeezan(LocalLedger ledger) {
    ledger.rememberAndroidSources([
      {'packageName': 'pk.example.ubl', 'label': 'UBL', 'configured': true},
      {
        'packageName': 'pk.example.meezan',
        'label': 'Meezan',
        'configured': true,
      },
    ]);
    final sources = ledger.sources();
    final ubl = ledger.addAccount(
      name: 'UBL current',
      type: AccountType.bank,
      sourceIds: [
        sources.firstWhere((s) => s.packageName == 'pk.example.ubl').id,
      ],
    );
    final meezan = ledger.addAccount(
      name: 'Meezan current',
      type: AccountType.bank,
      sourceIds: [
        sources.firstWhere((s) => s.packageName == 'pk.example.meezan').id,
      ],
    );
    return {'ubl': ubl, 'meezan': meezan};
  }

  void ingestTransferLegs(
    LocalLedger ledger,
    DateTime start, {
    Duration gap = const Duration(minutes: 4),
  }) {
    ledger.ingestNotification({
      'notificationKey': 'ubl:1',
      'snapshotHash': 'snap:ubl:1',
      'packageName': 'pk.example.ubl',
      'postedAt': start.millisecondsSinceEpoch,
      'title': 'Debit alert',
      'text': 'PKR 5,000.00 sent to ABDULLAH NASEEM via IBFT',
    });
    ledger.ingestNotification({
      'notificationKey': 'meezan:1',
      'snapshotHash': 'snap:meezan:1',
      'packageName': 'pk.example.meezan',
      'postedAt': start.add(gap).millisecondsSinceEpoch,
      'title': 'Credit alert',
      'text': 'PKR 5,000.00 credited to your account',
    });
  }

  test('without a registered own name, the two legs stay separate', () {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    setUpUblAndMeezan(ledger);
    ingestTransferLegs(ledger, DateTime.utc(2026, 8, 22, 9));

    final transactions = ledger.snapshot().transactions;
    expect(transactions, hasLength(2));
    expect(
      transactions.every((item) => item.kind != TransactionKind.transfer),
      isTrue,
    );
  });

  test('once the sender\'s own name is registered, the cross-bank transfer '
      'merges into one "Between your accounts" transaction', () {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    final accounts = setUpUblAndMeezan(ledger);
    ledger.setOwnNames(['Abdullah Naseem']);
    ingestTransferLegs(ledger, DateTime.utc(2026, 8, 22, 9));

    final transactions = ledger.snapshot().transactions;
    expect(transactions, hasLength(1));
    final transaction = transactions.single;
    expect(transaction.kind, TransactionKind.transfer);
    expect(transaction.fromAccountId, accounts['ubl']);
    expect(transaction.toAccountId, accounts['meezan']);
    expect(
      ledger.transactionCategories()[transaction.id],
      'Between your accounts',
    );
  });

  test('a registered name alone never merges legs that are hours apart -- only '
      'a counterparty naming the destination account may settle that late', () {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    setUpUblAndMeezan(ledger);
    ledger.setOwnNames(['Abdullah Naseem']);
    ingestTransferLegs(
      ledger,
      DateTime.utc(2026, 8, 22, 9),
      gap: const Duration(hours: 20),
    );

    final transactions = ledger.snapshot().transactions;
    expect(
      transactions,
      hasLength(2),
      reason: 'same amount a day apart is a coincidence, not a transfer',
    );
  });
}
