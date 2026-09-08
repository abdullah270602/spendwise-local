import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/spendwise_controller.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';
import 'package:spendwise/features/review/review_inbox_screen.dart';

/// "File it" through the whole chain it actually runs on: the real screen,
/// the real controller, a real ledger.
///
/// The fault it exists to prevent: the answer collected the direction and
/// nothing else, the ledger refuses to write an entry that belongs to no
/// account, and the screen printed the rule's own count as if every alert had
/// been settled. Twelve alerts became twelve entries in the receipt and none
/// in the ledger. A receipt that overstates the work is worse than no receipt,
/// because it is the only thing the user has to go on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// An app SpendWise knows about but no account claims, so its alerts reach
  /// the ledger with nowhere to go -- the case that produced the empty answer.
  LocalLedger openLedger({bool withAccount = true}) {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    ledger.rememberAndroidSources([
      {'packageName': 'com.messages', 'label': 'Messages', 'configured': true},
    ]);
    if (withAccount) {
      ledger.addAccount(
        name: 'Everyday',
        type: AccountType.bank,
        openingBalanceMinor: 0,
      );
    }
    return ledger;
  }

  void alert(LocalLedger ledger, String body, {required String key}) {
    ledger.ingestNotification({
      'id': key,
      'packageName': 'com.messages',
      'notificationKey': key,
      'snapshotHash': key,
      'title': 'Alert',
      'text': body,
      'postedAt': 1700000000000,
      'capturedAt': 1700000000000,
    });
  }

  Future<SpendWiseController> openInbox(
    WidgetTester tester,
    LocalLedger ledger,
  ) async {
    final controller = SpendWiseController.forTests(ledger);
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Scaffold(body: ReviewInboxScreen(viewModel: controller)),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('filing alerts that reached no account still files them', (
    tester,
  ) async {
    final ledger = openLedger();
    // Readable amounts, no word anywhere saying which way the money went.
    alert(ledger, 'Mystery Merchant XYZ. Amount Rs. 250. Thank you.', key: 'a');
    alert(ledger, 'Mystery Merchant XYZ. Amount Rs. 410. Thank you.', key: 'b');
    await openInbox(tester, ledger);

    await tester.tap(find.text('File all 2'));
    await tester.pumpAndSettle();

    // The account is the other thing the parser could not supply, and an
    // entry without one cannot exist, so the answer has to ask for it.
    expect(find.text('Which account?'), findsOneWidget);
    await tester.tap(find.text('Everyday'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Money out'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(ledger.snapshot().transactions, hasLength(2));
    expect(
      ledger.snapshot().transactions.every(
        (item) => item.kind == TransactionKind.expense,
      ),
      isTrue,
    );
  });

  testWidgets('the receipt counts what happened, not what was asked', (
    tester,
  ) async {
    // One alert carries an amount; the other never did. Filing can rescue the
    // first and nothing on earth can rescue the second, so the number on
    // screen is one, not two.
    final ledger = openLedger();
    alert(ledger, 'Mystery Merchant XYZ. Amount Rs. 250. Thank you.', key: 'a');
    alert(
      ledger,
      'Your statement for Mystery Bank is ready to view.',
      key: 'b',
    );
    await openInbox(tester, ledger);

    await tester.tap(find.text('File all 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Everyday'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Money out'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(ledger.snapshot().transactions, hasLength(1));
    expect(find.text('1 of 2 alerts settled.'), findsOneWidget);
    expect(find.text('2 alerts settled.'), findsNothing);
  });

  testWidgets('an answer that settled nothing says nothing was settled', (
    tester,
  ) async {
    final ledger = openLedger();
    alert(
      ledger,
      'Your statement for Mystery Bank is ready to view.',
      key: 'a',
    );
    alert(ledger, 'Mystery Bank never asks for your PIN by phone.', key: 'b');
    await openInbox(tester, ledger);

    await tester.tap(find.text('File all 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Everyday'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Money out'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(ledger.snapshot().transactions, isEmpty);
    expect(find.text('Nothing settled.'), findsOneWidget);
    expect(find.textContaining('alerts settled.'), findsNothing);
  });

  testWidgets('with nowhere to file them, nothing is claimed', (tester) async {
    // No accounts at all. The answer cannot run, so it says so and reports
    // nothing rather than printing a receipt for work that never started.
    final ledger = openLedger(withAccount: false);
    alert(ledger, 'Mystery Merchant XYZ. Amount Rs. 250. Thank you.', key: 'a');
    await openInbox(tester, ledger);

    await tester.tap(find.text('File it'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Add an account first'), findsOneWidget);
    expect(find.textContaining('settled'), findsNothing);
    expect(ledger.snapshot().transactions, isEmpty);
  });
}
