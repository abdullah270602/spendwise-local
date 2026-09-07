import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/spendwise_controller.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart' as domain;
import 'package:spendwise/features/shell/spendwise_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('storing a view preference tells the screens that read it', () async {
    // The bug this exists to prevent, in full: "Categories on Home" wrote its
    // choice to the ledger and notified nobody, so Home -- already built --
    // kept the list it had computed and the setting appeared to do nothing at
    // all. It went unnoticed because every earlier setting also called
    // something that notified: the savings chooser called
    // setShowSavingsOnHome, the palette bumped its own repaint counter, the
    // period setter notified outright. The first setting to rely on this
    // alone was the first one that visibly failed.
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    final controller = SpendWiseController.forTests(ledger);
    addTearDown(controller.dispose);

    var notified = 0;
    controller.addListener(() => notified++);

    controller.setViewPreference('home_categories', 'top');
    expect(controller.viewPreference('home_categories'), 'top');
    expect(
      notified,
      1,
      reason:
          'a stored choice nobody is told about is a choice that did not '
          'happen',
    );

    controller.setViewPreference('home_categories', 'off');
    expect(notified, 2);

    // Storing what is already stored changed nothing, so it says nothing --
    // otherwise every rebuild that re-saves a preference repaints the app.
    controller.setViewPreference('home_categories', 'off');
    expect(notified, 2, reason: 'no change, no announcement');
  });

  test(
    'every choice a settings screen stores survives and announces',
    () async {
      // One guard for the whole family, so the next setting built on
      // setViewPreference cannot repeat this.
      final ledger = LocalLedger.openInMemoryForTests();
      addTearDown(ledger.close);
      final controller = SpendWiseController.forTests(ledger);
      addTearDown(controller.dispose);

      var notified = 0;
      controller.addListener(() => notified++);

      const stored = {
        'home_categories': 'top',
        'home_savings': 'available',
        'home_savings_extra': 'moved',
        'palette': 'dusk',
        'ledger_span': 'all',
      };
      for (final entry in stored.entries) {
        controller.setViewPreference(entry.key, entry.value);
        expect(
          controller.viewPreference(entry.key),
          entry.value,
          reason: entry.key,
        );
      }
      expect(
        notified,
        stored.length,
        reason: 'one announcement per real change',
      );
    },
  );

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
