import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

/// Filing the same person under the same category over and over, and having
/// the app never notice, is the app failing to do its one job. But one filing
/// is a decision about one payment — it is repetition that earns the right to
/// answer for a payment the user has not seen yet.
void main() {
  ({LocalLedger ledger, String account}) openLedger() {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    ledger.rememberAndroidSources([
      {'packageName': 'pk.bank.app', 'label': 'Bank', 'configured': true},
    ]);
    final account = ledger.addAccount(
      name: 'Everyday',
      type: AccountType.bank,
      openingBalanceMinor: 0,
      sourceIds: [ledger.sources().single.id],
    );
    return (ledger: ledger, account: account);
  }

  /// One alert from the same person, each time with a different amount so
  /// they stay distinct transactions.
  String payTo(LocalLedger ledger, String who, {required int nth}) {
    ledger.ingestNotification({
      'id': '$who-$nth',
      'packageName': 'pk.bank.app',
      'notificationKey': '$who-$nth',
      'snapshotHash': '$who-$nth',
      'title': 'Transaction alert',
      'text': 'Rs. ${1000 + nth} debited from your account sent to $who',
      'postedAt': 1700000000000 + nth * 86400000,
      'capturedAt': 1700000000000 + nth * 86400000,
    });
    return ledger
        .snapshot()
        .transactions
        .firstWhere((item) => item.amount.minorUnits == (1000 + nth) * 100)
        .id;
  }

  String? categoryOf(LocalLedger ledger, int amountMinor) {
    final id = ledger
        .snapshot()
        .transactions
        .firstWhere((item) => item.amount.minorUnits == amountMinor)
        .id;
    return ledger.transactionCategories()[id];
  }

  String? categoryOfId(LocalLedger ledger, String id) =>
      ledger.transactionCategories()[id];

  test('the third confirmation is what starts the habit', () {
    final (:ledger, account: _) = openLedger();

    for (var nth = 1; nth <= LocalLedger.categoryRuleThreshold - 1; nth++) {
      final id = payTo(ledger, 'KASHIF ALI', nth: nth);
      ledger.categorizeTransactions([id], 'groceries');
    }

    // Two filings is not yet a habit: the next one still arrives unfiled.
    final beforeId = payTo(ledger, 'KASHIF ALI', nth: 90);
    expect(categoryOfId(ledger, beforeId), isNot('Groceries'));

    // The third one settles it.
    ledger.categorizeTransactions([beforeId], 'groceries');
    payTo(ledger, 'KASHIF ALI', nth: 91);

    expect(categoryOf(ledger, 109100), 'Groceries');
  });

  test('filing from Review teaches, exactly as an edit does', () {
    // This was the gap: Review is how most things get categorised, and it
    // taught nothing -- the same merchant could be filed by hand ten times
    // and still arrive uncategorised on the eleventh.
    final (:ledger, account: _) = openLedger();
    final ids = [
      for (var nth = 1; nth <= 3; nth++) payTo(ledger, 'VALLEY MART', nth: nth),
    ];

    ledger.categorizeTransactions(ids, 'groceries');
    payTo(ledger, 'VALLEY MART', nth: 92);

    expect(categoryOf(ledger, 109200), 'Groceries');
  });

  test('the habit is specific to that person', () {
    final (:ledger, account: _) = openLedger();
    final ids = [
      for (var nth = 1; nth <= 3; nth++) payTo(ledger, 'VALLEY MART', nth: nth),
    ];
    ledger.categorizeTransactions(ids, 'groceries');

    payTo(ledger, 'TOTAL LAHORE', nth: 93);
    expect(categoryOf(ledger, 109300), isNot('Groceries'));
  });

  test('disagreeing with the app stops it being wrong immediately', () {
    // The user must never have to correct the same wrong guess three times
    // to make it stop.
    final (:ledger, account: _) = openLedger();
    final ids = [
      for (var nth = 1; nth <= 3; nth++) payTo(ledger, 'VALLEY MART', nth: nth),
    ];
    ledger.categorizeTransactions(ids, 'groceries');

    final wrong = payTo(ledger, 'VALLEY MART', nth: 94);
    expect(categoryOf(ledger, 109400), 'Groceries');

    ledger.categorizeTransactions([wrong], 'food');

    // The old habit is retired at once -- the next payment is not filed as
    // groceries any more.
    payTo(ledger, 'VALLEY MART', nth: 95);
    expect(categoryOf(ledger, 109500), isNot('Groceries'));
  });

  test('and the replacement has to earn it too', () {
    final (:ledger, account: _) = openLedger();
    final ids = [
      for (var nth = 1; nth <= 3; nth++) payTo(ledger, 'VALLEY MART', nth: nth),
    ];
    ledger.categorizeTransactions(ids, 'groceries');

    for (var nth = 96; nth <= 98; nth++) {
      final id = payTo(ledger, 'VALLEY MART', nth: nth);
      ledger.categorizeTransactions([id], 'food');
    }

    payTo(ledger, 'VALLEY MART', nth: 99);
    expect(categoryOf(ledger, 109900), 'Food & dining');
  });

  test('a threshold everyone can see, rather than a magic number', () {
    expect(LocalLedger.categoryRuleThreshold, inInclusiveRange(3, 5));
  });
}
