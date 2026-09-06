import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

/// Deleting an automatic transaction has to outlast the next reconcile.
///
/// Reconcile rebuilds every unlocked automatic transaction from the evidence
/// that produced it, and it does so by deleting the rows outright first --
/// which took the `deleted_at` marker with them. The next alert, or the next
/// app launch, put the transaction straight back, and no number of deletions
/// made it stay gone.
void main() {
  LocalLedger openLedger() {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    ledger.rememberAndroidSources([
      {
        'packageName': 'pk.example.bank',
        'label': 'Example Bank',
        'configured': true,
      },
    ]);
    ledger.addAccount(
      name: 'Everyday',
      type: AccountType.bank,
      openingBalanceMinor: 0,
      sourceIds: [ledger.sources().single.id],
    );
    return ledger;
  }

  void alert(
    LocalLedger ledger, {
    required String key,
    required String body,
    required int postedAt,
  }) {
    ledger.ingestNotification({
      'id': key,
      'packageName': 'pk.example.bank',
      'notificationKey': key,
      'snapshotHash': key,
      'title': 'Transaction alert',
      'text': body,
      'postedAt': postedAt,
      'capturedAt': postedAt,
    });
  }

  test('a deleted transaction does not come back on the next reconcile', () {
    final ledger = openLedger();
    alert(
      ledger,
      key: 'one',
      body: 'Rs. 500 debited from your account at SHOP ONE',
      postedAt: 1700000000000,
    );

    final created = ledger.snapshot().transactions;
    expect(created, hasLength(1), reason: 'the alert became a transaction');
    final id = created.single.id;

    ledger.deleteTransaction(id);
    expect(ledger.snapshot().transactions, isEmpty);

    // Any later alert reconciles the whole ledger again. Before the fix this
    // is the moment the deleted row reappeared.
    alert(
      ledger,
      key: 'two',
      body: 'Rs. 900 debited from your account at SHOP TWO',
      postedAt: 1700000600000,
    );

    final after = ledger.snapshot().transactions;
    expect(after.map((item) => item.id), isNot(contains(id)));
    expect(after, hasLength(1), reason: 'only the new one survives');
  });

  test('and it stays gone when the same alert is captured again', () {
    // The same notification really can arrive twice -- Android re-posts, and
    // the dedup key is per capture. Deleting has to mean "not this money",
    // not merely "not this row".
    final ledger = openLedger();
    alert(
      ledger,
      key: 'first-capture',
      body: 'Rs. 500 debited from your account at SHOP ONE',
      postedAt: 1700000000000,
    );
    ledger.deleteTransaction(ledger.snapshot().transactions.single.id);

    alert(
      ledger,
      key: 'second-capture',
      body: 'Rs. 500 debited from your account at SHOP ONE',
      postedAt: 1700000000000,
    );

    expect(ledger.snapshot().transactions, isEmpty);
  });

  test('undo still works, because a restore lifts the tombstone', () {
    final ledger = openLedger();
    alert(
      ledger,
      key: 'one',
      body: 'Rs. 500 debited from your account at SHOP ONE',
      postedAt: 1700000000000,
    );
    final id = ledger.snapshot().transactions.single.id;

    ledger.deleteTransaction(id);
    ledger.restoreTransaction(id);

    expect(ledger.snapshot().transactions.map((item) => item.id), [id]);

    // And it survives the next reconcile, rather than being deleted again by
    // a tombstone nobody cleared.
    alert(
      ledger,
      key: 'two',
      body: 'Rs. 900 debited from your account at SHOP TWO',
      postedAt: 1700000600000,
    );
    expect(ledger.snapshot().transactions.map((item) => item.id), contains(id));
  });

  test('a deleted manual entry is unaffected by any of this', () {
    // Manual rows are not rebuilt by reconcile, so they must not acquire a
    // tombstone that outlives them.
    final ledger = openLedger();
    final accountId = ledger.snapshot().accounts.single.id;
    final id = ledger.addManualTransaction(
      kind: TransactionKind.expense,
      amountMinor: 2500,
      occurredAt: DateTime.utc(2026, 9, 6),
      accountId: accountId,
      description: 'Cash',
    );

    ledger.deleteTransaction(id);
    expect(ledger.snapshot().transactions, isEmpty);
    ledger.restoreTransaction(id);
    expect(ledger.snapshot().transactions.map((item) => item.id), [id]);
  });
}
