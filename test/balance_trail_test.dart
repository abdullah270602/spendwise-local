import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/spendwise_controller.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart' as domain;
import 'package:spendwise/features/transactions/transaction_details_screen.dart';

/// Every figure in this app is worked out from another figure, and after
/// enough of those a person is entitled to stop believing them. The balance
/// either side of an entry is the one thing an owner can hold against a bank
/// statement and check without trusting a single sum SpendWise made.
///
/// Which means it is worth nothing unless the three numbers on the row agree
/// with each other and with the ledger: before, plus what moved, is after.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(
    WidgetTester tester,
    SpendWiseController controller,
    String id,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: TransactionDetailsScreen(
          viewModel: controller,
          transaction: controller.transactions.firstWhere(
            (item) => item.id == id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('before plus what moved is after, on every entry', () {
    // The property the whole feature rests on. Asserted over a ledger with
    // one of everything in it rather than on a chosen row.
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    final bank = ledger.addAccount(
      name: 'Everyday',
      type: domain.AccountType.bank,
      openingBalanceMinor: 10000000,
    );
    final pot = ledger.addAccount(
      name: 'Emergency fund',
      type: domain.AccountType.savings,
      openingBalanceMinor: 2500000,
    );
    ledger.addManualTransaction(
      kind: domain.TransactionKind.income,
      amountMinor: 20000000,
      occurredAt: DateTime(2026, 9, 1),
      accountId: bank,
      description: 'Salary',
    );
    ledger.addManualTransaction(
      kind: domain.TransactionKind.expense,
      amountMinor: 3000000,
      occurredAt: DateTime(2026, 9, 4),
      accountId: bank,
      description: 'Rent',
    );
    ledger.addManualTransaction(
      kind: domain.TransactionKind.transfer,
      amountMinor: 5000000,
      occurredAt: DateTime(2026, 9, 6),
      accountId: bank,
      fromAccountId: bank,
      toAccountId: pot,
      description: 'To the fund',
    );
    final controller = SpendWiseController.forTests(ledger);
    addTearDown(controller.dispose);

    for (final entry in controller.transactions) {
      for (final change in entry.balances) {
        expect(
          change.beforeMinor + change.deltaMinor,
          change.afterMinor,
          reason: 'the row must add up: ${entry.title}',
        );
      }
    }

    // And the last one for each account is that account's balance.
    expect(
      controller.accounts
          .firstWhere((account) => account.id == bank)
          .balance
          .minorUnits,
      22000000,
    );
  });

  testWidgets('the entry screen shows what the account held either side', (
    tester,
  ) async {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    final bank = ledger.addAccount(
      name: 'Everyday',
      type: domain.AccountType.bank,
      openingBalanceMinor: 10000000,
    );
    final id = ledger.addManualTransaction(
      kind: domain.TransactionKind.expense,
      amountMinor: 1500000,
      occurredAt: DateTime(2026, 9, 3),
      accountId: bank,
      description: 'Groceries',
    );
    final controller = SpendWiseController.forTests(ledger);
    addTearDown(controller.dispose);
    await pump(tester, controller, id);

    expect(find.text('BALANCE AROUND THIS'), findsOneWidget);
    expect(find.text('100,000'), findsWidgets, reason: 'before');
    expect(find.text('15,000'), findsWidgets, reason: 'what moved');
    expect(find.text('85,000'), findsWidgets, reason: 'after');
  });

  testWidgets('a transfer shows both accounts, not just the one it left', (
    tester,
  ) async {
    // Showing one side would leave the other account looking as though money
    // had appeared in it from nowhere.
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    final bank = ledger.addAccount(
      name: 'Everyday',
      type: domain.AccountType.bank,
      openingBalanceMinor: 10000000,
    );
    final pot = ledger.addAccount(
      name: 'Emergency fund',
      type: domain.AccountType.savings,
      openingBalanceMinor: 0,
    );
    final id = ledger.addManualTransaction(
      kind: domain.TransactionKind.transfer,
      amountMinor: 5000000,
      occurredAt: DateTime(2026, 9, 6),
      accountId: bank,
      fromAccountId: bank,
      toAccountId: pot,
      description: 'To the fund',
    );
    final controller = SpendWiseController.forTests(ledger);
    addTearDown(controller.dispose);
    await pump(tester, controller, id);

    expect(find.text('Everyday'), findsWidgets);
    expect(find.text('Emergency fund'), findsWidgets);
    expect(
      controller.transactions.firstWhere((item) => item.id == id).balances,
      hasLength(2),
    );
  });

  testWidgets('an entry that reached no account claims no balance', (
    tester,
  ) async {
    // An alert that matched nothing has no balance to have moved. Printing a
    // zero would be the app asserting something it cannot know.
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    ledger.addAccount(
      name: 'Everyday',
      type: domain.AccountType.bank,
      openingBalanceMinor: 10000000,
    );
    final orphan = ledger.addManualTransaction(
      kind: domain.TransactionKind.expense,
      amountMinor: 900000,
      occurredAt: DateTime(2026, 9, 7),
      description: 'Unattached',
    );
    final controller = SpendWiseController.forTests(ledger);
    addTearDown(controller.dispose);
    await pump(tester, controller, orphan);

    expect(find.text('BALANCE AROUND THIS'), findsNothing);
  });
}
