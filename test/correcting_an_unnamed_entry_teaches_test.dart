import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

/// Filing the same shop under the same category, over and over, and the app
/// never learning it.
///
/// A correction is remembered against the name of whoever was paid, so an
/// entry that names nobody teaches nothing. That is what one wallet produced
/// for months: its alerts read "Money sent [emoji] Rs. 110 sent to A Shop",
/// and the word "sent" in the *title* matched the generic debit rule, which
/// is a verb and an amount and no name at all. The rule answered first, the
/// payee in the rest of the sentence was dropped, and every correction the
/// owner made was filed against an entry with nothing to key on.
///
/// The same wallet's other wording -- "Off it goes [emoji] Rs. 110 sent to
/// A Shop" -- has no debit verb before the amount, so it fell through to the
/// generic reader, which does look for "sent to". Two alerts a second apart,
/// one named, one not.
void main() {
  const wallet = 'com.example.wallet';

  test('a rule that only knows the direction does not erase the payee', () {
    final observation = RawObservation(
      id: 'obs-1',
      kind: ObservationKind.notification,
      observedAt: DateTime.utc(2026, 6, 1, 10),
      title: 'Money sent \u{1F4B8}',
      body: 'Money sent \u{1F4B8} Rs. 110 sent to Corner Grocer.',
      accountId: 'acct',
      sourcePackage: wallet,
    );

    final result = const NotificationParser().parseDetailed(observation);
    expect(result.status, ParseStatus.parsed);
    expect(
      result.candidate!.counterparty,
      'Corner Grocer',
      reason:
          'the rule settled the direction; the sentence still named a '
          'payee and the rule had no opinion about it',
    );
    expect(result.candidate!.description, 'Corner Grocer');
  });

  test('a correction on one of those entries is learned', () {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    ledger.rememberAndroidSources([
      {'packageName': wallet, 'label': 'Wallet', 'configured': true},
    ]);
    ledger.addAccount(
      name: 'Pocket',
      type: AccountType.wallet,
      accountSuffix: '9003',
      sourceIds: [ledger.sources().single.id],
    );

    void post(String key, int amount, int day) => ledger.ingestNotification({
      'notificationKey': key,
      'snapshotHash': 'snap:$key',
      'packageName': wallet,
      'postedAt': DateTime.utc(2026, 6, day, 10).millisecondsSinceEpoch,
      'title': 'Money sent \u{1F4B8}',
      'text': 'Money sent \u{1F4B8} Rs. $amount sent to Corner Grocer.',
    });

    for (var day = 1; day <= LocalLedger.categoryRuleThreshold; day++) {
      post('paid-$day', 100 + day, day);
    }
    for (final entry in ledger.snapshot().transactions) {
      ledger.updateTransaction(
        id: entry.id,
        kind: entry.kind,
        description: entry.description ?? 'Payment',
        occurredAt: entry.occurredAt,
        amountMinor: entry.amount.minorUnits,
        accountId: entry.accountId,
        categoryId: 'groceries',
      );
    }

    // The next one, worded identically, arrives without being asked about.
    post('paid-later', 999, 20);
    final arrived = ledger.snapshot().transactions.firstWhere(
      (item) => item.amount.minorUnits == 99900,
    );
    expect(
      ledger.transactionCategories()[arrived.id],
      'Groceries',
      reason: 'three corrections against one name is a habit',
    );
  });
}
