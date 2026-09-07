import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/spendwise_controller.dart';
import 'package:spendwise/data/local_ledger.dart';

/// Review asks questions about apps by name. When the name is
/// `com.google.android.apps.messaging` the question reads as being about
/// somebody else's phone, and the person cannot answer it.
///
/// The transaction path had always run app names through the normaliser. The
/// alert path had not — `_alertView` was static, so it could not reach the
/// live Android labels and simply passed the stored string through. The
/// result was one Review screen naming the same app two different ways: the
/// card built from a transaction said "Messages", the card built from a raw
/// alert said the package id.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const messages = 'com.google.android.apps.messaging';

  LocalLedger ledgerWithStuckAlert({required String storedLabel}) {
    final ledger = LocalLedger.openInMemoryForTests();
    ledger.rememberAndroidSources([
      {'packageName': messages, 'label': storedLabel, 'configured': true},
    ]);
    ledger.ingestNotification({
      'notificationKey': 'sms:promo',
      'snapshotHash': 'snapshot:promo',
      'packageName': messages,
      'postedAt': DateTime.utc(2026, 9, 6, 10).millisecondsSinceEpoch,
      'title': 'SIMOSA',
      'text': 'APP UPDATE pe unlock karien! FREE GBs, Mins aur Bohat Kuch!',
    });
    return ledger;
  }

  test('a raw alert is never described by its package id', () {
    // The stored name is the package id -- which is what a source captured
    // before Android could be asked for a label looks like.
    final ledger = ledgerWithStuckAlert(storedLabel: messages);
    addTearDown(ledger.close);
    final controller = SpendWiseController.forTests(ledger);
    addTearDown(controller.dispose);

    for (final alert in controller.alerts(onlyUnresolved: false)) {
      expect(
        alert.sourceLabel,
        isNot(contains('.')),
        reason: 'a package id in a question the user has to answer',
      );
      expect(alert.sourceLabel, 'Messaging');
    }
  });

  test('a real label is preferred over guessing at the package id', () {
    final ledger = ledgerWithStuckAlert(storedLabel: 'Messages');
    addTearDown(ledger.close);
    final controller = SpendWiseController.forTests(ledger);
    addTearDown(controller.dispose);

    final alert = controller.alerts(onlyUnresolved: false).first;
    expect(
      alert.sourceLabel,
      'Messages',
      reason: 'the stored name is right; do not prettify over it',
    );
  });

  test('the reviews built from those alerts agree with them', () {
    // Both halves of Review read the same app. They used to disagree, and
    // seeing one screen call an app two names is what made it obvious.
    final ledger = ledgerWithStuckAlert(storedLabel: messages);
    addTearDown(ledger.close);
    final controller = SpendWiseController.forTests(ledger);
    addTearDown(controller.dispose);

    for (final review in controller.reviews) {
      expect(
        review.title,
        isNot(contains(messages)),
        reason: 'the review title names the same app as the alert does',
      );
    }
  });
}
