import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

/// Review offered one action on an unreadable alert: drop it. When the alert
/// plainly was a transaction there was nowhere to go, so the only button on
/// offer destroyed real money. This is the other answer — the user supplies
/// the one thing the parser could not read, and the parser still contributes
/// everything it did read.
void main() {
  LocalLedger openLedger() {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    ledger.rememberAndroidSources([
      {'packageName': 'pk.wallet.app', 'label': 'Wallet', 'configured': true},
    ]);
    ledger.addAccount(
      name: 'Wallet',
      type: AccountType.wallet,
      openingBalanceMinor: 0,
      sourceIds: [ledger.sources().single.id],
    );
    return ledger;
  }

  void alert(LocalLedger ledger, String body, {String key = 'a'}) {
    ledger.ingestNotification({
      'id': key,
      'packageName': 'pk.wallet.app',
      'notificationKey': key,
      'snapshotHash': key,
      'title': 'Alert',
      'text': body,
      'postedAt': 1700000000000,
      'capturedAt': 1700000000000,
    });
  }

  List<String> unreadIds(LocalLedger ledger) =>
      ledger.alerts().map((item) => item.id).toList(growable: false);

  test('answering the direction turns an unread alert into a transaction', () {
    final ledger = openLedger();
    // No debit or credit verb anywhere: the parser reads Rs 4,500 and stops.
    alert(ledger, 'Mystery Merchant XYZ. Amount Rs. 4,500. Thank you.');
    expect(ledger.snapshot().transactions, isEmpty);

    final filed = ledger.fileAlerts(
      unreadIds(ledger),
      direction: EntryDirection.debit,
    );

    expect(filed, 1);
    final transaction = ledger.snapshot().transactions.single;
    expect(transaction.kind, TransactionKind.expense);
    expect(transaction.amount.minorUnits, 450000);
    expect(ledger.snapshot().unparsedCount, 0);
  });

  test('money in works the same way', () {
    final ledger = openLedger();
    alert(ledger, 'Mystery Merchant XYZ. Amount Rs. 4,500. Thank you.');

    ledger.fileAlerts(unreadIds(ledger), direction: EntryDirection.credit);

    expect(ledger.snapshot().transactions.single.kind, TransactionKind.income);
  });

  test('one answer settles every alert it covers', () {
    final ledger = openLedger();
    for (var i = 0; i < 3; i++) {
      alert(
        ledger,
        'Mystery Merchant XYZ. Amount Rs. ${100 + i}. Thank you.',
        key: 'alert-$i',
      );
    }

    expect(
      ledger.fileAlerts(unreadIds(ledger), direction: EntryDirection.debit),
      3,
    );
    expect(ledger.snapshot().transactions, hasLength(3));
  });

  test('the answer is a hint, never an override', () {
    // Wording that is already clear keeps its own reading. Otherwise one
    // careless tap would silently flip a pile of correctly-read alerts.
    final ledger = openLedger();
    alert(ledger, 'Rs. 900 credited to your account from SALARY');

    final before = ledger.snapshot().transactions.single;
    expect(before.kind, TransactionKind.income, reason: 'read correctly');

    ledger.fileAlerts(['no-such-alert'], direction: EntryDirection.debit);
    expect(ledger.snapshot().transactions.single.kind, TransactionKind.income);
  });

  test('an alert with no readable amount is reported, not invented', () {
    final ledger = openLedger();
    alert(ledger, 'Your statement is ready. Tap to view.');

    final filed = ledger.fileAlerts(
      unreadIds(ledger),
      direction: EntryDirection.debit,
    );

    expect(filed, 0, reason: 'nothing to file');
    expect(ledger.snapshot().transactions, isEmpty);
  });

  test('it can place and file in one answer', () {
    // An alert from a shared app has no account, so filing has to be able to
    // supply that too -- otherwise the user answers twice.
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    ledger.rememberAndroidSources([
      {'packageName': 'com.messages', 'label': 'Messages', 'configured': true},
    ]);
    final accountId = ledger.addAccount(
      name: 'Everyday',
      type: AccountType.bank,
      openingBalanceMinor: 0,
    );
    ledger.ingestNotification({
      'id': 'x',
      'packageName': 'com.messages',
      'notificationKey': 'x',
      'snapshotHash': 'x',
      'title': 'Alert',
      'text': 'Mystery Merchant XYZ. Amount Rs. 250. Thank you.',
      'postedAt': 1700000000000,
      'capturedAt': 1700000000000,
    });

    final filed = ledger.fileAlerts(
      unreadIds(ledger),
      direction: EntryDirection.debit,
      accountId: accountId,
    );

    expect(filed, 1);
    expect(ledger.snapshot().transactions.single.accountId, accountId);
  });
}
