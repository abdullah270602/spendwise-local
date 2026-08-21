import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/accounts/accounts_screen.dart';
import 'package:spendwise/features/shell/spendwise_shell.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';
import 'package:spendwise/features/onboarding/onboarding_screen.dart';
import 'package:spendwise/features/settings/export_screen.dart';
import 'package:spendwise/features/transactions/transaction_details_screen.dart';

void main() {
  testWidgets('shell renders cash-flow dashboard and local privacy state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: SpendWiseShell(viewModel: _FakeViewModel()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Private. Local. Yours.'), findsOneWidget);
    expect(find.byTooltip('Open settings'), findsNothing);
    expect(find.text('Total balance'), findsOneWidget);
    expect(find.text('Net cash flow'), findsOneWidget);
    expect(find.text('12.0% of income retained'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Spending by category'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Account balances'), findsOneWidget);
  });

  testWidgets(
    'settings is a primary destination and manual entry is account-gated',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SpendWiseTheme.dark,
          home: SpendWiseShell(viewModel: _EmptyViewModel()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('Finish setup'), findsOneWidget);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings & privacy'), findsOneWidget);
    },
  );

  testWidgets('onboarding explains the local ledger before completion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: OnboardingScreen(viewModel: _FakeViewModel()),
      ),
    );
    expect(find.text('One trustworthy ledger'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Duplicates become context'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Private by design'), findsOneWidget);
    expect(find.text('Start privately'), findsOneWidget);
  });

  testWidgets('transaction with no evidence uses accurate source copy', (
    tester,
  ) async {
    final transaction = TransactionViewData(
      id: 'manual',
      title: 'Cash purchase',
      subtitle: 'Everyday',
      amount: const MoneyViewData(-1000),
      kind: TransactionKind.expense,
      occurredAt: DateTime(2026, 8, 22),
      category: 'Other',
      evidenceCount: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: TransactionDetailsScreen(
          viewModel: _FakeViewModel(),
          transaction: transaction,
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('No linked evidence'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No linked evidence'), findsOneWidget);
    expect(find.textContaining('one supporting observation'), findsNothing);
    expect(find.text('Expense'), findsOneWidget);
  });

  testWidgets('transaction edit recovers from a stale account assignment', (
    tester,
  ) async {
    final transaction = TransactionViewData(
      id: 'notification-entry',
      title: 'Card purchase',
      subtitle: 'Deleted account',
      amount: const MoneyViewData(-2500),
      kind: TransactionKind.expense,
      occurredAt: DateTime(2026, 8, 22),
      category: 'Shopping',
      accountId: 'no-longer-active',
      evidenceCount: 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: TransactionDetailsScreen(
          viewModel: _FakeViewModel(),
          transaction: transaction,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Edit classification'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Edit classification'), findsOneWidget);
    expect(find.text('Everyday'), findsOneWidget);
  });

  testWidgets('export labels transaction types for people, not enums', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: ExportScreen(viewModel: _FakeViewModel()),
      ),
    );
    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);
    expect(find.text('expense'), findsNothing);
  });

  testWidgets('first account accepts grouped balance and closes cleanly', (
    tester,
  ) async {
    final viewModel = _AccountCreateViewModel();
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: AnimatedBuilder(
          animation: viewModel,
          builder: (_, _) => AccountsScreen(viewModel: viewModel),
        ),
      ),
    );

    expect(
      find.ancestor(
        of: find.text('Add your first account'),
        matching: find.byType(Center),
      ),
      findsWidgets,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add account'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Account name'),
      'UBL',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Opening balance'),
      '477379',
    );
    expect(find.text('477,379'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add account').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('UBL'), findsOneWidget);
    expect(find.text('PKR 477,379'), findsOneWidget);
  });

  testWidgets('account management exposes protected deletion', (tester) async {
    final viewModel = _AccountSourcesViewModel();
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: AccountsScreen(viewModel: viewModel),
      ),
    );
    await tester.tap(find.text('Everyday'));
    await tester.pumpAndSettle();
    expect(find.text('Delete account'), findsOneWidget);
    expect(find.text('Enabled Bank'), findsOneWidget);
    expect(find.text('Disabled Bank'), findsNothing);
  });
}

class _AccountCreateViewModel extends _FakeViewModel {
  List<AccountViewData> _accounts = const [];

  @override
  List<AccountViewData> get accounts => _accounts;

  @override
  Future<void> addAccount(
    String name,
    String type,
    MoneyViewData openingBalance,
  ) async {
    _accounts = [
      AccountViewData(
        id: 'created',
        name: name,
        type: type,
        balance: openingBalance,
      ),
    ];
    notifyListeners();
  }
}

class _EmptyViewModel extends _FakeViewModel {
  @override
  List<AccountViewData> get accounts => const [];
  @override
  List<TransactionViewData> get transactions => const [];
}

class _AccountSourcesViewModel extends _FakeViewModel {
  @override
  List<SourceViewData> get sources => const [
    SourceViewData(
      packageName: 'pk.enabled.bank',
      label: 'Enabled Bank',
      enabled: true,
    ),
    SourceViewData(
      packageName: 'pk.disabled.bank',
      label: 'Disabled Bank',
      enabled: false,
    ),
  ];
}

class _FakeViewModel extends ChangeNotifier implements SpendWiseViewModel {
  @override
  bool get onboardingComplete => true;
  @override
  bool get notificationAccessGranted => true;
  @override
  DashboardViewData get dashboard => const DashboardViewData(
    netWorth: MoneyViewData(2500000),
    incomeThisMonth: MoneyViewData(400000),
    spendingThisMonth: MoneyViewData(150000),
    monthlyChangePercent: 12,
  );
  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'bank',
      name: 'Everyday',
      type: 'Bank',
      balance: MoneyViewData(2500000),
      suffix: '1234',
    ),
  ];
  @override
  List<TransactionViewData> get transactions => [
    TransactionViewData(
      id: '1',
      title: 'Groceries',
      subtitle: 'Everyday',
      amount: const MoneyViewData(-150000),
      kind: TransactionKind.expense,
      occurredAt: DateTime.now(),
      category: 'Food & dining',
      accountId: 'bank',
    ),
  ];
  @override
  List<ReviewViewData> get reviews => const [];
  @override
  List<SourceViewData> get sources => const [];
  @override
  Future<void> addAccount(
    String name,
    String type,
    MoneyViewData openingBalance,
  ) async {}
  @override
  Future<void> completeOnboarding() async {}
  @override
  Future<void> deleteTransaction(String id) async {}
  @override
  Future<void> eraseAllData() async {}
  @override
  Future<void> exportData() async {}
  @override
  Future<void> importCsv(String csvText) async {}
  @override
  Future<String?> pickCsvFile() async => null;
  @override
  Future<void> requestNotificationAccess() async {}
  @override
  Future<void> resolveReview(String id, {required bool merge}) async {}
  @override
  Future<void> saveManualTransaction(ManualTransactionDraft draft) async {}
  @override
  Future<void> setSourceEnabled(String packageName, bool enabled) async {}
}
