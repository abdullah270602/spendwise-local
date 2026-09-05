import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

/// A messaging app relays every bank's SMS. Treating it as "the source for
/// account X" files Meezan's alerts, UBL's alerts and the pizza place's
/// delivery text all into X. These lock in that a shared app routes on what
/// the alert says, and holds its hand up when it cannot tell.
void main() {
  const messages = 'com.google.android.apps.messaging';

  LocalLedger ledgerWithTwoBanks({bool attachMessagesToMeezan = true}) {
    final ledger = LocalLedger.openInMemoryForTests();
    ledger.rememberAndroidSources([
      {'packageName': messages, 'label': 'Messages', 'configured': true},
    ]);
    final sourceId = ledger.sources().single.id;
    ledger.addAccount(
      name: 'Meezan Debit',
      type: AccountType.bank,
      institutionName: 'Meezan Bank',
      accountSuffix: '9001',
      sourceIds: attachMessagesToMeezan ? [sourceId] : const [],
    );
    ledger.addAccount(
      name: 'UBL Current',
      type: AccountType.bank,
      institutionName: 'UBL',
      accountSuffix: '9003',
    );
    return ledger;
  }

  bool ingest(
    LocalLedger ledger,
    String text, {
    String key = 'sms:1',
    String sender = 'Unknown',
  }) => ledger.ingestNotification({
    'notificationKey': key,
    'snapshotHash': 'snapshot:$key',
    'packageName': messages,
    'postedAt': DateTime.utc(2026, 9, 6, 10).millisecondsSinceEpoch,
    'title': sender,
    'text': text,
  });

  test('a messaging app is shared even when attached to one account', () {
    final ledger = ledgerWithTwoBanks();
    addTearDown(ledger.close);
    expect(ledger.isSharedSource(messages), isTrue);
  });

  test('a bank app attached to one account is not shared', () {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    ledger.rememberAndroidSources([
      {'packageName': 'pk.meezan.app', 'label': 'Meezan', 'configured': true},
    ]);
    ledger.addAccount(
      name: 'Meezan Debit',
      type: AccountType.bank,
      sourceIds: [ledger.sources().single.id],
    );
    expect(ledger.isSharedSource('pk.meezan.app'), isFalse);
  });

  test('a UBL SMS delivered by Messages lands on UBL, not on Meezan', () {
    final ledger = ledgerWithTwoBanks();
    addTearDown(ledger.close);

    expect(
      ingest(
        ledger,
        'UBL: PKR 2,086.20 debited from your account ending 9003 at '
        'DEMO PHARMACY',
        sender: 'UBL',
      ),
      isTrue,
    );

    final accounts = ledger.snapshot().accounts;
    final ubl = accounts.firstWhere((a) => a.name == 'UBL Current');
    final transaction = ledger.snapshot().transactions.single;
    expect(transaction.accountId, ubl.id);
  });

  test(
    'an unroutable SMS is held for routing, never filed under the attached '
    'account',
    () {
      final ledger = ledgerWithTwoBanks();
      addTearDown(ledger.close);

      expect(
        ingest(ledger, 'PKR 4,500.00 debited at EXAMPLE CLINIC'),
        isTrue,
      );

      expect(
        ledger.snapshot().transactions,
        isEmpty,
        reason: 'guessing an account is worse than asking',
      );
      final pending = ledger.unroutedAlerts();
      expect(pending, hasLength(1));
      expect(pending.single.body, contains('EXAMPLE CLINIC'));
    },
  );

  test('routing held alerts files and re-reads them in one pass', () {
    final ledger = ledgerWithTwoBanks();
    addTearDown(ledger.close);

    ingest(ledger, 'PKR 4,500.00 debited at EXAMPLE CLINIC');
    ingest(ledger, 'PKR 300.00 debited at PSO', key: 'sms:2');
    final held = ledger.unroutedAlerts();
    expect(held, hasLength(2));

    final meezan = ledger
        .snapshot()
        .accounts
        .firstWhere((a) => a.name == 'Meezan Debit');
    final parsed = ledger.routeAlerts(
      held.map((alert) => alert.id),
      meezan.id,
    );

    expect(parsed, 2);
    expect(ledger.unroutedAlerts(), isEmpty);
    final transactions = ledger.snapshot().transactions;
    expect(transactions, hasLength(2));
    expect(
      transactions.every((item) => item.accountId == meezan.id),
      isTrue,
    );
  });
}
