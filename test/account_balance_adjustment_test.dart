import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

void main() {
  test(
    'setting current balance preserves transactions and adjusts baseline',
    () {
      final ledger = LocalLedger.openInMemoryForTests();
      addTearDown(ledger.close);
      final account = ledger.addAccount(
        name: 'Current account',
        type: AccountType.bank,
        openingBalanceMinor: 100000,
      );
      ledger.addManualTransaction(
        kind: TransactionKind.expense,
        amountMinor: 10000,
        occurredAt: DateTime.utc(2026, 8, 22),
        accountId: account,
        description: 'Purchase',
      );

      final before = ledger.snapshot();
      expect(before.accountBalanceMinor(account), 90000);
      expect(before.transactions, hasLength(1));

      ledger.setAccountCurrentBalance(
        id: account,
        currentBalanceMinor: 90000,
        targetBalanceMinor: 125000,
      );

      final after = ledger.snapshot();
      expect(after.accountBalanceMinor(account), 125000);
      expect(after.transactions, hasLength(1));
      expect(after.transactions.single.description, 'Purchase');
    },
  );
}
