import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/spendwise_controller.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart' as domain;
import 'package:spendwise/features/shell/spendwise_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('derived screen models are reused until ledger data changes', () async {
    final ledger = LocalLedger.openInMemoryForTests();
    final account = ledger.addAccount(
      name: 'Daily',
      type: domain.AccountType.bank,
      openingBalanceMinor: 100000,
    );
    final controller = SpendWiseController.forTests(ledger);
    addTearDown(controller.dispose);

    final accounts = controller.accounts;
    final transactions = controller.transactions;
    final dashboard = controller.dashboard;
    final reviews = controller.reviews;

    expect(identical(controller.accounts, accounts), isTrue);
    expect(identical(controller.transactions, transactions), isTrue);
    expect(identical(controller.dashboard, dashboard), isTrue);
    expect(identical(controller.reviews, reviews), isTrue);

    await controller.saveManualTransaction(
      ManualTransactionDraft(
        title: 'Coffee',
        amount: const MoneyViewData(5000),
        kind: TransactionKind.expense,
        accountId: account,
        category: 'Food & dining',
        occurredAt: DateTime.utc(2026, 8, 22),
      ),
    );

    expect(identical(controller.transactions, transactions), isFalse);
    expect(controller.transactions, hasLength(1));
    expect(identical(controller.dashboard, dashboard), isFalse);
  });
}
