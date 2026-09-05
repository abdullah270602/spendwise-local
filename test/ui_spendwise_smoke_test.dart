import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/accounts/accounts_screen.dart';
import 'package:spendwise/features/import/import_csv_screen.dart';
import 'package:spendwise/features/insights/insights_screen.dart';
import 'package:spendwise/features/shell/spendwise_shell.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';
import 'package:spendwise/features/onboarding/onboarding_screen.dart';
import 'package:spendwise/features/review/review_inbox_screen.dart';
import 'package:spendwise/features/settings/export_screen.dart';
import 'package:spendwise/features/settings/settings_screen.dart';
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
    expect(find.text('Available to spend'), findsOneWidget);
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

  testWidgets('settings shows the installed version and GitHub repository', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'SpendWise',
      packageName: 'com.spendwise.app',
      version: '0.9.4',
      buildNumber: '19',
      buildSignature: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: SettingsScreen(viewModel: _EmptyViewModel()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('About SpendWise'), 400);
    await tester.pumpAndSettle();
    expect(find.text('v0.9.4 (19)'), findsOneWidget);
    expect(find.text('GitHub repository'), findsOneWidget);
    expect(
      find.text('github.com/abdullah270602/spendwise-local'),
      findsOneWidget,
    );
  });

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

  testWidgets('statement import advertises CSV and Excel support', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: ImportCsvScreen(viewModel: _FakeViewModel()),
      ),
    );

    expect(find.text('Choose CSV or Excel files'), findsOneWidget);
    expect(
      find.text('CSV, XLSX, or XLS · read only on this device'),
      findsNothing,
    );
  });

  testWidgets('review can recover currently visible notifications', (
    tester,
  ) async {
    final model = _BatchImportViewModel();
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: ReviewInboxScreen(viewModel: model),
      ),
    );

    final scanButton = find.widgetWithIcon(IconButton, Icons.refresh_rounded);
    expect(scanButton, findsOneWidget);
    await tester.tap(scanButton);
    await tester.pumpAndSettle();

    expect(model.trayScans, 1);
    expect(
      find.text('Recovered 2 new notifications from the tray.'),
      findsOneWidget,
    );
  });

  testWidgets('statement import selects every valid worksheet at once', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: ImportCsvScreen(viewModel: _BatchImportViewModel()),
      ),
    );

    await tester.tap(find.text('Choose CSV or Excel files'));
    await tester.pumpAndSettle();

    expect(find.textContaining('2 of 3 sheets'), findsOneWidget);
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.text('Current account'), findsOneWidget);
    expect(find.text('Wallet'), findsWidgets);
    expect(find.text('Summary'), findsOneWidget);
    expect(find.textContaining('No transaction table'), findsOneWidget);
    expect(find.text('Suggested from statement details'), findsNWidgets(2));
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
    expect(find.text('PKR 477,379'), findsWidgets);
  });

  testWidgets('account management exposes protected deletion', (tester) async {
    final viewModel = _AccountSourcesViewModel();
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: AccountsScreen(viewModel: viewModel),
      ),
    );
    expect(find.text('Enabled Bank'), findsNothing);
    await tester.tap(find.text('Everyday'));
    await tester.pumpAndSettle();
    expect(find.text('Enabled Bank'), findsOneWidget);
    expect(find.text('Disabled Bank'), findsNothing);
    expect(find.text('Adjust balance'), findsOneWidget);
    await tester.tap(find.byTooltip('Account actions'));
    await tester.pumpAndSettle();
    expect(find.text('Delete account'), findsOneWidget);
  });

  testWidgets('savings can be selected during account creation', (
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

    await tester.tap(find.widgetWithText(FilledButton, 'Add account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bank').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Savings').last);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Savings stay visible here, but are excluded from Available to spend.',
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Account name'),
      'Rainy day',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Opening balance'),
      '200000',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add account').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Rainy day'), findsOneWidget);
    expect(find.text('Everyday accounts'), findsNothing);
    expect(find.text('PKR 200,000'), findsWidgets);
  });

  testWidgets('savings stay visible but separate from spendable money', (
    tester,
  ) async {
    final viewModel = _SavingsViewModel();
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: AccountsScreen(viewModel: viewModel),
      ),
    );

    expect(find.text('Available to spend'), findsOneWidget);
    expect(find.text('PKR 25,000'), findsWidgets);
    expect(find.text('Savings'), findsWidgets);
    expect(find.text('PKR 100,000'), findsWidgets);
    expect(find.text('Everyday accounts'), findsOneWidget);
    expect(find.text('Emergency fund'), findsOneWidget);
  });

  testWidgets('dashboard hides savings by default', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: SpendWiseShell(viewModel: _SavingsViewModel()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Available to spend'), findsOneWidget);
    expect(find.text('PKR 25,000'), findsOneWidget);
    expect(find.text('PKR 100,000 saved separately'), findsNothing);
    expect(find.text('Emergency fund'), findsNothing);
    expect(find.text('PKR 125,000'), findsNothing);
  });

  testWidgets('Insights combines everyday and savings balances', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: InsightsScreen(viewModel: _SavingsViewModel()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Total tracked'), findsOneWidget);
    expect(find.text('PKR 125,000'), findsOneWidget);
    expect(find.text('PKR 25,000'), findsOneWidget);
    expect(find.text('PKR 100,000'), findsOneWidget);
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
        isIncluded: !type.toLowerCase().contains('saving'),
      ),
    ];
    notifyListeners();
  }
}

class _SavingsViewModel extends _FakeViewModel {
  @override
  DashboardViewData get dashboard => const DashboardViewData(
    netWorth: MoneyViewData(12500000),
    spendableBalance: MoneyViewData(2500000),
    savingsBalance: MoneyViewData(10000000),
    incomeThisMonth: MoneyViewData(0),
    spendingThisMonth: MoneyViewData(0),
    monthlyChangePercent: 0,
  );

  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'daily',
      name: 'Everyday',
      type: 'bank',
      balance: MoneyViewData(2500000),
    ),
    AccountViewData(
      id: 'savings',
      name: 'Emergency fund',
      type: 'savings',
      balance: MoneyViewData(10000000),
      isIncluded: false,
    ),
  ];
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

class _BatchImportViewModel extends _FakeViewModel
    implements SpendWiseAdvancedViewModel {
  int trayScans = 0;
  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'bank',
      name: 'Meezan Current',
      type: 'Bank',
      balance: MoneyViewData(0),
    ),
    AccountViewData(
      id: 'wallet',
      name: 'NayaPay',
      type: 'Wallet',
      balance: MoneyViewData(0),
    ),
  ];

  @override
  bool get busy => false;
  @override
  bool get demoDataEnabled => false;
  @override
  String? get errorMessage => null;
  @override
  DeletedAccountViewData? get lastDeletedAccount => null;
  @override
  bool get showSavingsOnHome => false;
  @override
  List<String> get ownNames => const [];

  @override
  Future<StatementFileViewData?> pickStatementFile() async =>
      const StatementFileViewData(
        fileName: 'accounts.xlsx',
        sheets: [
          StatementSheetViewData(
            name: 'Current account',
            csvText: 'Date,Description,Debit,Credit\n2026-08-20,Food,100,\n',
            suggestedAccountId: 'bank',
            accountInferenceReason: 'Matched account name',
            accountInferenceConfidence: .9,
          ),
          StatementSheetViewData(
            name: 'Wallet',
            csvText:
                'Date,Description,Debit,Credit\n2026-08-20,Transfer,,100\n',
            suggestedAccountId: 'wallet',
            accountInferenceReason: 'Matched NayaPay',
            accountInferenceConfidence: .9,
          ),
          StatementSheetViewData(
            name: 'Summary',
            csvText: 'Monthly summary',
            importable: false,
            detectionError: 'No transaction table found',
          ),
        ],
      );

  @override
  Future<void> addDetailedAccount(AccountCreationDraft draft) async {}
  @override
  Future<void> archiveAccount(String id) async {}
  @override
  Future<void> commitCsvImport(CsvImportDraft draft) async {}
  @override
  Future<void> correctTransaction(
    String id,
    TransactionCorrectionDraft draft,
  ) async {}
  @override
  void dismissError() {}
  @override
  Future<void> exportLedger(ExportRequest request) async {}
  @override
  Future<CsvImportPreviewViewData> previewCsvImport(
    CsvImportDraft draft,
  ) async => const CsvImportPreviewViewData(
    rows: [],
    validCount: 0,
    errorCount: 0,
    duplicateCount: 0,
    sameFileAlreadyImported: false,
  );
  @override
  Future<void> restoreAccount(String id) async {}
  @override
  Future<NotificationTrayScanViewData> scanNotificationTray() async {
    trayScans++;
    return const NotificationTrayScanViewData(
      status: NotificationTrayScanViewStatus.completed,
      activeCount: 4,
      eligibleCount: 3,
      queuedCount: 2,
      duplicateCount: 1,
    );
  }

  @override
  Future<void> setDemoDataEnabled(bool enabled) async {}
  @override
  Future<void> setShowSavingsOnHome(bool enabled) async {}
  @override
  Future<void> setOwnNames(List<String> names) async {}
  @override
  Future<void> setAccountCurrentBalance(
    String id,
    MoneyViewData balance,
  ) async {}
  @override
  Future<void> updateDetailedAccount(
    String id,
    AccountUpdateDraft draft,
  ) async {}
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
  Future<void> restoreTransaction(String id) async {}
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
