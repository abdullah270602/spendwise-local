import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';

void main() {
  test(
    'dedup migration removes content-identical duplicate notification evidence',
    () {
      final ledger = LocalLedger.openInMemoryForTests();

      // Simulates the fixed bug: the same live notification captured three
      // times with a different (ranking-volatile) snapshotHash each time,
      // so each call looked like new evidence instead of a duplicate.
      const postedAt = 1700000000000;
      for (var i = 0; i < 3; i++) {
        ledger.ingestNotification({
          'id': i,
          'packageName': 'pk.example.bank',
          'notificationKey': 'key-$i',
          'snapshotHash': 'hash-$i',
          'title': 'Debit alert',
          'text': 'Rs. 500 debited',
          'postedAt': postedAt,
          'capturedAt': postedAt,
        });
      }

      final beforeCount = ledger.snapshot().unparsedCount;

      ledger.resetDedupMigrationForTests();
      ledger.rerunMigrationsForTests();

      final afterCount = ledger.snapshot().unparsedCount;
      expect(beforeCount, 3);
      expect(afterCount, 1);
    },
  );
}
