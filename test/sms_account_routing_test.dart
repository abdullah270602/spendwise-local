import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

/// Every bank's SMS arrives through the one messaging app. Filing alerts by
/// the delivering app put them all on a single account, which is wrong on its
/// face and also made a real transfer between two accounts look like two
/// entries on one — impossible to pair.
void main() {
  ({LocalLedger ledger, String meezan, String ubl}) setUp() {
    final ledger = LocalLedger.openInMemoryForTests();
    ledger.rememberAndroidSources([
      {
        'packageName': 'com.google.android.apps.messaging',
        'label': 'Messages',
        'configured': true,
      },
    ]);
    final smsSource = ledger.sources().single.id;
    // Both accounts are fed by the same messaging app, exactly as on a real
    // phone.
    final meezan = ledger.addAccount(
      name: 'Meezan Debit',
      type: AccountType.bank,
      institutionName: 'Meezan Bank',
      accountSuffix: '4821',
      sourceIds: [smsSource],
    );
    final ubl = ledger.addAccount(
      name: 'UBL Current',
      type: AccountType.bank,
      institutionName: 'UBL',
      accountSuffix: '9012',
      sourceIds: [smsSource],
    );
    return (ledger: ledger, meezan: meezan, ubl: ubl);
  }

  void ingest(
    LocalLedger ledger,
    String key,
    String text, {
    required DateTime at,
    String? sender,
  }) {
    ledger.ingestNotification({
      'notificationKey': key,
      'snapshotHash': 'snap:$key',
      'packageName': 'com.google.android.apps.messaging',
      'postedAt': at.millisecondsSinceEpoch,
      'title': sender ?? 'Messages',
      'text': text,
      'sender': ?sender,
    });
  }

  test('an SMS is filed against the bank it names', () {
    final env = setUp();
    addTearDown(env.ledger.close);

    ingest(
      env.ledger,
      'meezan-1',
      'Meezan Bank: PKR 1,060 debited from a/c ****4821. Avl Bal PKR 5,000',
      at: DateTime.utc(2026, 9, 5, 10),
      sender: 'Meezan',
    );

    final transaction = env.ledger.snapshot().transactions.single;
    expect(
      transaction.accountId,
      env.meezan,
      reason: 'a Meezan alert must not land on another account',
    );
    expect(transaction.amount.minorUnits, 106000);
  });

  test('money moved between the user\'s own accounts becomes one transfer', () {
    final env = setUp();
    addTearDown(env.ledger.close);

    ingest(
      env.ledger,
      'meezan-out',
      'Meezan Bank: PKR 10,000 transferred to UBL from a/c ****4821. '
          'Avl Bal PKR 5,000',
      at: DateTime.utc(2026, 9, 5, 10),
      sender: 'Meezan',
    );
    ingest(
      env.ledger,
      'ubl-in',
      'UBL: PKR 10,000 credited to your a/c ****9012. Avl Bal PKR 30,000',
      at: DateTime.utc(2026, 9, 5, 10, 2),
      sender: 'UBL',
    );

    final transactions = env.ledger.snapshot().transactions;
    expect(
      transactions,
      hasLength(1),
      reason: 'the two legs are one movement of money, not two events',
    );
    final transfer = transactions.single;
    expect(transfer.kind, TransactionKind.transfer);
    expect(transfer.fromAccountId, env.meezan);
    expect(transfer.toAccountId, env.ubl);
    expect(
      env.ledger.transactionCategories()[transfer.id],
      'Between your accounts',
    );
  });

  test('a self-transfer is excluded from spending and income', () {
    final env = setUp();
    addTearDown(env.ledger.close);

    ingest(
      env.ledger,
      'meezan-out',
      'Meezan Bank: PKR 10,000 transferred to UBL from a/c ****4821',
      at: DateTime.utc(2026, 9, 5, 10),
      sender: 'Meezan',
    );
    ingest(
      env.ledger,
      'ubl-in',
      'UBL: PKR 10,000 credited to your a/c ****9012',
      at: DateTime.utc(2026, 9, 5, 10, 2),
      sender: 'UBL',
    );

    final transactions = env.ledger.snapshot().transactions;
    expect(
      transactions.every((item) => item.kind == TransactionKind.transfer),
      isTrue,
      reason: 'moving your own money is neither spending nor earning',
    );
  });
}
