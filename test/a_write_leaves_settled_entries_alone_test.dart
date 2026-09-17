import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

/// What every write cost, and why it grew with the ledger.
///
/// Reconcile re-derives every automatic entry from the evidence on file. It
/// used to delete all of them and write them back on every ingest, every
/// correction, every filed review — classifying, inserting and re-linking
/// hundreds of rows that had not changed. Measured on a ledger of 500
/// entries: one write took 466ms on the isolate the screen waits on, and
/// building that ledger from its alerts took three and a half minutes.
///
/// Writing only what moved took the same write to about 50ms and the same
/// rebuild to ten seconds. This test is the cheap, deterministic half of
/// that claim: an entry nothing has changed about is not touched.
void main() {
  test('an entry nothing has changed about is not written again', () {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    ledger.rememberAndroidSources([
      {'packageName': 'com.example.bank', 'label': 'Bank', 'configured': true},
    ]);
    ledger.addAccount(
      name: 'Everyday',
      type: AccountType.bank,
      accountSuffix: '9001',
      sourceIds: [ledger.sources().single.id],
    );

    void post(String key, int amount, int day) => ledger.ingestNotification({
      'notificationKey': key,
      'snapshotHash': 'snap:$key',
      'packageName': 'com.example.bank',
      'postedAt': DateTime.utc(2026, 6, day, 10).millisecondsSinceEpoch,
      'title': 'Bank',
      'text': 'Bank PKR $amount charged at CORNER BAKERY from A/C xxx9001',
    });

    post('first', 250, 1);
    final first = ledger.snapshot().transactions.single;
    final touchedAt = ledger.updatedAtForTest(first.id);
    expect(touchedAt, isNotNull);

    // A second alert, a month later, about something else entirely.
    post('second', 990, 2);
    expect(ledger.snapshot().transactions, hasLength(2));
    expect(
      ledger.updatedAtForTest(first.id),
      touchedAt,
      reason:
          'the first entry was re-derived identically, so nothing about '
          'it needed writing',
    );
  });
}
