import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/notification_noise.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

/// "Messages is doing work in the background" is Android's own paperwork. It
/// reports nothing, it never becomes a transaction, and because Android
/// re-posts it, dismissing it in Review achieved nothing — the same
/// non-question was back the next time the app opened.
void main() {
  group('recognising furniture', () {
    test('an ongoing notice is not an event', () {
      expect(
        isBackgroundServiceNotice({
          'packageName': 'com.google.android.apps.messaging',
          'title': 'Messages is doing work in the background',
          'statusBarNotification': {'ongoing': true, 'clearable': false},
        }),
        isTrue,
      );
    });

    test('so is anything the platform files under service or progress', () {
      for (final category in const ['service', 'progress', 'transport']) {
        expect(
          isBackgroundServiceNotice({'category': category}),
          isTrue,
          reason: category,
        );
      }
    });

    test('a bank alert is neither', () {
      // The distinction that matters: an alert reports something finished,
      // so it is dismissible and never ongoing.
      expect(
        isBackgroundServiceNotice({
          'packageName': 'pk.example.bank',
          'title': 'Transaction alert',
          'text': 'Rs. 500 debited from your account',
          'category': 'msg',
          'statusBarNotification': {'ongoing': false, 'clearable': true},
        }),
        isFalse,
      );
    });

    test('and an envelope with no flags at all is left alone', () {
      // Older capture paths do not carry the status metadata. Absence of
      // evidence is not evidence of noise.
      expect(isBackgroundServiceNotice({'text': 'Rs. 500 debited'}), isFalse);
    });
  });

  test('a background notice never reaches the review inbox', () {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    ledger.rememberAndroidSources([
      {
        'packageName': 'com.google.android.apps.messaging',
        'label': 'Messages',
        'configured': true,
      },
    ]);
    ledger.addAccount(
      name: 'Everyday',
      type: AccountType.bank,
      sourceIds: [ledger.sources().single.id],
    );

    // Android re-posts this; capture it twice, as the phone did.
    for (var i = 0; i < 2; i++) {
      ledger.ingestNotification({
        'id': 'notice-$i',
        'packageName': 'com.google.android.apps.messaging',
        'notificationKey': 'notice-$i',
        'snapshotHash': 'notice-$i',
        'title': 'Messages is doing work in the background',
        'text': 'Messages is doing work in the background',
        'postedAt': 1700000000000 + i,
        'capturedAt': 1700000000000 + i,
        'statusBarNotification': {'ongoing': true, 'clearable': false},
      });
    }

    expect(ledger.snapshot().unparsedCount, 0);
    expect(ledger.unparsedBySource(), isEmpty);
  });

  test('notices captured before the filter existed are cleared out', () {
    // Dismissing them never worked, so by the time the filter ships there is
    // a pile of them already on file. They have to go too, or the fix is
    // invisible to exactly the people who hit the bug.
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    ledger.rememberAndroidSources([
      {
        'packageName': 'com.google.android.apps.messaging',
        'label': 'Messages',
        'configured': true,
      },
    ]);
    ledger.addAccount(
      name: 'Everyday',
      type: AccountType.bank,
      sourceIds: [ledger.sources().single.id],
    );

    ledger.ingestNoticeBypassingFilterForTests({
      'id': 'legacy',
      'packageName': 'com.google.android.apps.messaging',
      'notificationKey': 'legacy',
      'snapshotHash': 'legacy',
      'title': 'Messages is doing work in the background',
      'text': 'Messages is doing work in the background',
      'postedAt': 1700000000000,
      'capturedAt': 1700000000000,
      'statusBarNotification': {'ongoing': true, 'clearable': false},
    });
    expect(ledger.snapshot().unparsedCount, 1, reason: 'stored, as it was');

    ledger.resetBackgroundNoticeCleanupForTests();
    ledger.rerunMigrationsForTests();

    expect(ledger.snapshot().unparsedCount, 0);
  });
}
