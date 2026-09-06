import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/spendwise_controller.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

/// Moving money to yourself is not one event. Putting it into savings is a
/// decision worth seeing in the register; taking it back out is a different
/// decision again. "Account transfer" hid both behind one word.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Builds a ledger, runs [move] against it, then wraps it in a controller —
  /// the controller snapshots on construction, so the entries have to exist
  /// first.
  String titleOfSingle(
    String Function(
      LocalLedger ledger,
      String current,
      String pot,
      String wallet,
    )
    move,
  ) {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    final current = ledger.addAccount(
      name: 'Everyday',
      type: AccountType.bank,
      openingBalanceMinor: 10000000,
    );
    final pot = ledger.addAccount(
      name: 'UBL',
      type: AccountType.savings,
      openingBalanceMinor: 0,
    );
    final wallet = ledger.addAccount(
      name: 'NayaPay',
      type: AccountType.wallet,
      openingBalanceMinor: 0,
    );
    final id = move(ledger, current, pot, wallet);
    // Not disposed: dispose() closes the ledger, which the tear-down above
    // already does, and double-closing throws.
    final app = SpendWiseController.forTests(ledger);
    return app.transactions.firstWhere((item) => item.id == id).title;
  }

  String transfer(
    LocalLedger ledger, {
    required String from,
    required String to,
    String? description,
  }) => ledger.addManualTransaction(
    kind: TransactionKind.transfer,
    amountMinor: 4000000,
    occurredAt: DateTime.utc(2026, 9, 7),
    fromAccountId: from,
    toAccountId: to,
    description: description,
    categoryId: 'transfer',
  );

  test('money moved into savings says so', () {
    expect(
      titleOfSingle(
        (ledger, current, pot, wallet) =>
            transfer(ledger, from: current, to: pot),
      ),
      'Moved into savings',
    );
  });

  test('and money taken back out is a different sentence', () {
    expect(
      titleOfSingle(
        (ledger, current, pot, wallet) =>
            transfer(ledger, from: pot, to: current),
      ),
      'Taken out of savings',
    );
  });

  test('a transfer between two everyday accounts is still just that', () {
    expect(
      titleOfSingle(
        (ledger, current, pot, wallet) =>
            transfer(ledger, from: current, to: wallet),
      ),
      'Account transfer',
    );
  });

  test('a description the alert gave still wins', () {
    expect(
      titleOfSingle(
        (ledger, current, pot, wallet) => transfer(
          ledger,
          from: current,
          to: pot,
          description: 'Monthly standing order',
        ),
      ),
      'Monthly standing order',
    );
  });
}
