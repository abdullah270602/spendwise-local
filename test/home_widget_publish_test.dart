import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/spendwise_controller.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/app/palette.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart' as domain;
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// The controller is the only thing on the Dart side that ever speaks to the
/// widget's channel -- everything it sends is asserted here, both what does
/// cross (a fraction, two colours, a flag) and how rarely it crosses (never
/// for a notify that changed nothing the widget draws, which is the whole of
/// the battery argument for not polling).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.spendwise.app/home_widget');

  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    // Every other test in the suite constructs a fresh app on the default
    // palette; leaving a different one applied here would leak into
    // whichever test happens to run next.
    SpendWiseColors.apply(SpendWisePalette.sage);
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a fresh ledger with nothing in it publishes hasData: false', () async {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    final controller = SpendWiseController.forTests(ledger);
    addTearDown(controller.dispose);
    final accountId = ledger.addAccount(
      name: 'Daily',
      type: domain.AccountType.bank,
      openingBalanceMinor: 0,
    );

    // Opening an account with a zero balance still notifies -- Accounts
    // reads the new row -- but there is nothing for Home to have drawn yet.
    controller.setViewPreference('home_categories', 'off');
    await settle();

    expect(calls, isNotEmpty);
    final last = calls.last;
    expect(last.method, 'publish');
    expect(last.arguments['hasData'], isFalse);
    expect(last.arguments['hasSavedBranch'], isFalse);
    // The account exists only so the transaction below has somewhere to
    // land; asserting on it here would fail the analyzer's unused-variable
    // check for a value that is genuinely only a setup detail.
    expect(accountId, isNotEmpty);
  });

  test(
    'a transaction changes the fraction, and that is what gets published',
    () async {
      final ledger = LocalLedger.openInMemoryForTests();
      addTearDown(ledger.close);
      final controller = SpendWiseController.forTests(ledger);
      addTearDown(controller.dispose);
      final accountId = ledger.addAccount(
        name: 'Daily',
        type: domain.AccountType.bank,
        openingBalanceMinor: 0,
      );

      await controller.saveManualTransaction(
        ManualTransactionDraft(
          title: 'Salary',
          amount: const MoneyViewData(400000),
          kind: TransactionKind.income,
          accountId: accountId,
          category: 'Salary',
          occurredAt: DateTime.now(),
        ),
      );
      await settle();

      expect(calls, isNotEmpty);
      var published = calls.last;
      expect(published.arguments['hasData'], isTrue);
      expect(published.arguments['keptFraction'], closeTo(1.0, 1e-9));

      calls.clear();
      await controller.saveManualTransaction(
        ManualTransactionDraft(
          title: 'Rent',
          amount: const MoneyViewData(150000),
          kind: TransactionKind.expense,
          accountId: accountId,
          category: 'Housing',
          occurredAt: DateTime.now(),
        ),
      );
      await settle();

      expect(calls, isNotEmpty);
      published = calls.last;
      expect(
        published.arguments['keptFraction'],
        closeTo(250000 / 400000, 1e-9),
      );
    },
  );

  test(
    'a notify that changes nothing the widget draws never touches the '
    'channel -- the whole point of not polling is not calling out either',
    () async {
      final ledger = LocalLedger.openInMemoryForTests();
      addTearDown(ledger.close);
      final controller = SpendWiseController.forTests(ledger);
      addTearDown(controller.dispose);
      final accountId = ledger.addAccount(
        name: 'Daily',
        type: domain.AccountType.bank,
        openingBalanceMinor: 0,
      );
      await controller.saveManualTransaction(
        ManualTransactionDraft(
          title: 'Salary',
          amount: const MoneyViewData(400000),
          kind: TransactionKind.income,
          accountId: accountId,
          category: 'Salary',
          occurredAt: DateTime.now(),
        ),
      );
      await settle();
      calls.clear();

      // Ledger chart/plain is a real, notifying preference change, and has
      // nothing to do with the ribbon's proportion or its colours.
      controller.setViewPreference('ledger_view', 'chart');
      await settle();

      expect(
        calls,
        isEmpty,
        reason: 'this preference does not change the fraction or the colours',
      );
    },
  );

  test('a palette change republishes the two colours, even with the same '
      'fraction', () async {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    final controller = SpendWiseController.forTests(ledger);
    addTearDown(controller.dispose);
    final accountId = ledger.addAccount(
      name: 'Daily',
      type: domain.AccountType.bank,
      openingBalanceMinor: 0,
    );
    await controller.saveManualTransaction(
      ManualTransactionDraft(
        title: 'Salary',
        amount: const MoneyViewData(400000),
        kind: TransactionKind.income,
        accountId: accountId,
        category: 'Salary',
        occurredAt: DateTime.now(),
      ),
    );
    await settle();
    calls.clear();

    SpendWiseColors.apply(SpendWisePalette.byId('slate'));
    controller.setViewPreference('palette', 'slate');
    await settle();

    expect(calls, isNotEmpty);
    final published = calls.last;
    expect(published.arguments['keepColor'], SpendWisePalette.byId('slate').keep.toARGB32());
    expect(published.arguments['spendColor'], SpendWisePalette.byId('slate').spend.toARGB32());
  });

  test(
    'switching Home to "saving gets its own branch" republishes a third '
    'branch, sized against what was actually put away, in the palette\'s '
    '"mine" tone -- the same setting Home\'s own screen reads, not one the '
    'widget keeps of its own',
    () async {
      final ledger = LocalLedger.openInMemoryForTests();
      addTearDown(ledger.close);
      final controller = SpendWiseController.forTests(ledger);
      addTearDown(controller.dispose);
      final bank = ledger.addAccount(
        name: 'Daily',
        type: domain.AccountType.bank,
        openingBalanceMinor: 0,
      );
      final savings = ledger.addAccount(
        name: 'Savings',
        type: domain.AccountType.savings,
        openingBalanceMinor: 0,
      );
      await controller.saveManualTransaction(
        ManualTransactionDraft(
          title: 'Salary',
          amount: const MoneyViewData(400000),
          kind: TransactionKind.income,
          accountId: bank,
          category: 'Salary',
          occurredAt: DateTime.now(),
        ),
      );
      await controller.saveManualTransaction(
        ManualTransactionDraft(
          title: 'Put away',
          amount: const MoneyViewData(100000),
          kind: TransactionKind.transfer,
          accountId: bank,
          toAccountId: savings,
          category: 'Transfer',
          occurredAt: DateTime.now(),
        ),
      );
      await settle();
      calls.clear();

      controller.setViewPreference('home_savings', 'siblings');
      await settle();

      expect(calls, isNotEmpty);
      final published = calls.last;
      expect(published.arguments['hasSavedBranch'], isTrue);
      expect(
        published.arguments['savedFraction'],
        closeTo(100000 / 400000, 1e-9),
      );
      expect(
        published.arguments['mineColor'],
        SpendWisePalette.sage.mine.toARGB32(),
      );
    },
  );

  test(
    'moving off "siblings" republishes the plain two-branch snapshot -- '
    'the branch was Home\'s choice, not a fact this widget remembers on its '
    'own once the setting moves on',
    () async {
      final ledger = LocalLedger.openInMemoryForTests();
      addTearDown(ledger.close);
      final controller = SpendWiseController.forTests(ledger);
      addTearDown(controller.dispose);
      final bank = ledger.addAccount(
        name: 'Daily',
        type: domain.AccountType.bank,
        openingBalanceMinor: 0,
      );
      final savings = ledger.addAccount(
        name: 'Savings',
        type: domain.AccountType.savings,
        openingBalanceMinor: 0,
      );
      await controller.saveManualTransaction(
        ManualTransactionDraft(
          title: 'Salary',
          amount: const MoneyViewData(400000),
          kind: TransactionKind.income,
          accountId: bank,
          category: 'Salary',
          occurredAt: DateTime.now(),
        ),
      );
      await controller.saveManualTransaction(
        ManualTransactionDraft(
          title: 'Put away',
          amount: const MoneyViewData(100000),
          kind: TransactionKind.transfer,
          accountId: bank,
          toAccountId: savings,
          category: 'Transfer',
          occurredAt: DateTime.now(),
        ),
      );
      controller.setViewPreference('home_savings', 'siblings');
      await settle();
      calls.clear();

      controller.setViewPreference('home_savings', 'off');
      await settle();

      expect(calls, isNotEmpty);
      expect(calls.last.arguments['hasSavedBranch'], isFalse);
    },
  );
}
