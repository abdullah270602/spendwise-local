import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/insights/insights_screen.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

void main() {
  testWidgets('insights switches resolution and filters a category', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Scaffold(body: InsightsScreen(viewModel: _InsightsModel())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Insights'), findsOneWidget);
    // Detail is the default view now: thirty days of all spending is the
    // question people arrive with.
    expect(find.text('MONEY MOVING OVER TIME'), findsOneWidget);
    // Balances are not repeated here. Insights is about what money did over
    // a period; what is left in each account is what Accounts is for.
    expect(find.text('Total tracked'), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('WHERE YOUR MONEY WENT'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 1000));
    await tester.pumpAndSettle();

    await tester.tap(find.text('7 DAYS'));
    await tester.pumpAndSettle();
    expect(find.text('Average per day'), findsOneWidget);

    await tester.tap(find.text('Entertainment'));
    await tester.pumpAndSettle();
    expect(find.text('ENTERTAINMENT SPENDING OVER TIME'), findsOneWidget);
    expect(find.text('WHERE YOUR MONEY WENT'), findsNothing);
  });
}

class _InsightsModel extends ChangeNotifier implements SpendWiseViewModel {
  @override
  List<TransactionViewData> get transactions => [
    TransactionViewData(
      id: 'movie',
      title: 'Cinema',
      subtitle: 'Daily',
      amount: const MoneyViewData(-240000),
      kind: TransactionKind.expense,
      occurredAt: DateTime.now().subtract(const Duration(days: 1)),
      category: 'Entertainment',
    ),
    TransactionViewData(
      id: 'food',
      title: 'Groceries',
      subtitle: 'Daily',
      amount: const MoneyViewData(-150000),
      kind: TransactionKind.expense,
      occurredAt: DateTime.now().subtract(const Duration(days: 2)),
      category: 'Food & dining',
    ),
    TransactionViewData(
      id: 'income',
      title: 'Salary',
      subtitle: 'Daily',
      amount: const MoneyViewData(5000000),
      kind: TransactionKind.income,
      occurredAt: DateTime.now().subtract(const Duration(days: 3)),
      category: 'Income',
    ),
  ];

  @override
  bool get onboardingComplete => true;
  @override
  bool get notificationAccessGranted => true;
  @override
  DashboardViewData get dashboard => const DashboardViewData(
    netWorth: MoneyViewData(0),
    incomeThisMonth: MoneyViewData(0),
    spendingThisMonth: MoneyViewData(0),
    monthlyChangePercent: 0,
  );
  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'daily',
      name: 'Daily',
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
  Future<void> requestNotificationAccess() async {}
  @override
  Future<void> resolveReview(String id, {required bool merge}) async {}
  @override
  Future<void> saveManualTransaction(ManualTransactionDraft draft) async {}
  @override
  Future<void> setSourceEnabled(String packageName, bool enabled) async {}
}
