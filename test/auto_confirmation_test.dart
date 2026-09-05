import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

/// A clean notification -- one explicit amount, one unambiguous direction --
/// is a deterministic read. Sending every one of those to the Review inbox
/// made the inbox the whole workflow instead of the exception, so these lock
/// in which captures post on their own and which still ask.
void main() {
  LocalLedger ledgerWithBankAccount() {
    final ledger = LocalLedger.openInMemoryForTests();
    ledger.rememberAndroidSources([
      {
        'packageName': 'pk.example.bank',
        'label': 'Example Bank',
        'configured': true,
      },
    ]);
    ledger.addAccount(
      name: 'Current account',
      type: AccountType.bank,
      sourceIds: [ledger.sources().single.id],
    );
    return ledger;
  }

  bool ingest(LocalLedger ledger, String text, {String key = 'bank:1'}) =>
      ledger.ingestNotification({
        'notificationKey': key,
        'snapshotHash': 'snapshot:$key',
        'packageName': 'pk.example.bank',
        'postedAt': DateTime.utc(2026, 8, 24, 10).millisecondsSinceEpoch,
        'title': 'Transaction alert',
        'text': text,
      });

  test('a clearly parsed debit posts without asking for confirmation', () {
    final ledger = ledgerWithBankAccount();
    addTearDown(ledger.close);

    expect(
      ingest(
        ledger,
        'Your account was debited PKR 1,500 at IMTIAZ SUPERMARKET',
      ),
      isTrue,
    );

    final transaction = ledger.snapshot().transactions.single;
    expect(transaction.kind, TransactionKind.expense);
    expect(
      transaction.needsReview,
      isFalse,
      reason: 'one amount plus one direction word is a deterministic read',
    );
  });

  test('a clearly parsed credit posts without asking for confirmation', () {
    final ledger = ledgerWithBankAccount();
    addTearDown(ledger.close);

    expect(ingest(ledger, 'PKR 25,000 credited to your account'), isTrue);

    final transaction = ledger.snapshot().transactions.single;
    expect(transaction.kind, TransactionKind.income);
    expect(transaction.needsReview, isFalse);
  });

  test('batched ingest yields the same ledger as one-at-a-time ingest', () {
    List<Map<String, Object?>> envelopes() => [
      for (var index = 0; index < 6; index++)
        {
          'notificationKey': 'bank:$index',
          'snapshotHash': 'snapshot:bank:$index',
          'packageName': 'pk.example.bank',
          'postedAt': DateTime.utc(
            2026,
            8,
            24,
            10,
            index,
          ).millisecondsSinceEpoch,
          'title': 'Transaction alert',
          'text':
              'Your account was debited PKR ${index + 1},500 at SHOP $index',
        },
    ];

    final sequential = ledgerWithBankAccount();
    addTearDown(sequential.close);
    for (final envelope in envelopes()) {
      sequential.ingestNotification(envelope);
    }

    final batched = ledgerWithBankAccount();
    addTearDown(batched.close);
    final flags = batched.ingestNotifications(envelopes());

    expect(flags, everyElement(isTrue));
    expect(
      batched.snapshot().transactions.map((t) => t.amount.minorUnits).toList(),
      sequential
          .snapshot()
          .transactions
          .map((t) => t.amount.minorUnits)
          .toList(),
    );
    expect(
      batched.snapshot().transactions.map((t) => t.needsReview).toList(),
      sequential.snapshot().transactions.map((t) => t.needsReview).toList(),
    );
  });

  test('re-deriving stored evidence is safe to repeat and keeps clean '
      'captures out of review', () {
    final ledger = ledgerWithBankAccount();
    addTearDown(ledger.close);
    ingest(ledger, 'Your account was debited PKR 1,500 at IMTIAZ SUPERMARKET');
    ingest(ledger, 'PKR 9,000 credited to your account', key: 'bank:2');

    final before = ledger.snapshot().transactions;
    ledger.resetEvidenceRefreshForTests();
    ledger.rerunMigrationsForTests();
    final after = ledger.snapshot().transactions;

    expect(after, hasLength(before.length));
    expect(after.every((item) => !item.needsReview), isTrue);
  });

  test('a bank SMS quoting a balance becomes a transaction, not a stuck '
      'observation', () {
    final ledger = ledgerWithBankAccount();
    addTearDown(ledger.close);

    ingest(
      ledger,
      'Your a/c ****1234 has been debited with PKR 80.00. Avl Bal: PKR 12,345.67',
    );

    final snapshot = ledger.snapshot();
    expect(
      snapshot.unparsedCount,
      0,
      reason: 'a quoted balance must not make the alert unreadable',
    );
    expect(snapshot.transactions.single.amount.minorUnits, 8000);
    expect(ledger.unparsedBySource(), isEmpty);
  });

  test('an alert with no amount is not treated as pending work', () {
    final ledger = ledgerWithBankAccount();
    addTearDown(ledger.close);

    // An enabled source carries everything that app posts. None of this is a
    // transaction, and none of it is actionable, so it must not accumulate
    // in the Review inbox.
    ingest(ledger, 'Your one-time passcode is 123456', key: 'otp');
    ingest(ledger, 'Your parcel is out for delivery', key: 'parcel');

    final snapshot = ledger.snapshot();
    expect(snapshot.unparsedCount, 0);
    expect(snapshot.transactions, isEmpty);
    expect(ledger.unparsedBySource(), isEmpty);
  });

  test('an alert with two amounts still asks, because it may be a payment', () {
    final ledger = ledgerWithBankAccount();
    addTearDown(ledger.close);

    ingest(ledger, 'Paid PKR 100 and PKR 20 fee', key: 'two-amounts');

    expect(ledger.snapshot().unparsedCount, 1);
  });

  test('marketing copy that reads like a transaction still asks first', () {
    final ledger = ledgerWithBankAccount();
    addTearDown(ledger.close);

    expect(
      ingest(
        ledger,
        'Congratulations! PKR 5,000 cashback will be credited on your next spend. T&C apply',
      ),
      isTrue,
    );

    final transaction = ledger.snapshot().transactions.single;
    expect(
      transaction.needsReview,
      isTrue,
      reason: 'promotional copy must never post to the ledger unreviewed',
    );
  });
}
