import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/shell/spendwise_shell.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

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
    expect(find.text('Total balance'), findsOneWidget);
    expect(find.text('Net cash flow'), findsOneWidget);
    expect(find.text('Spending by category'), findsOneWidget);
    expect(find.text('12.0% of income retained'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Account balances'), 300);
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
      expect(find.text('Finish setup'), findsOneWidget);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
    expect(find.text('Settings & privacy'), findsOneWidget);
    },
  );
}

class _EmptyViewModel extends _FakeViewModel {
  @override
  List<AccountViewData> get accounts => const [];
  @override
  List<TransactionViewData> get transactions => const [];
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
