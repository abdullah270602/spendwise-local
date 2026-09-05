import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/review/review_inbox_screen.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

void main() {
  TransactionViewData transaction(String id) => TransactionViewData(
    id: id,
    title: 'Cha-Ching!',
    subtitle: 'NayaPay',
    amount: const MoneyViewData(8000),
    kind: TransactionKind.income,
    occurredAt: DateTime.utc(2026, 8, 22, 22, 29),
    category: 'Income',
    isReviewed: false,
  );

  testWidgets('swiping right confirms the transaction and removes the card', (
    tester,
  ) async {
    final model = _FakeReviewViewModel(transaction('tx-1'));
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: AnimatedBuilder(
          animation: model,
          builder: (context, child) => ReviewInboxScreen(viewModel: model),
        ),
      ),
    );

    expect(find.text('Cha-Ching!'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('review-tx-1')),
      const Offset(600, 0),
    );
    await tester.pumpAndSettle();

    expect(model.confirmed, contains('tx-1'));
    expect(model.deleted, isNot(contains('tx-1')));
    expect(find.text('Cha-Ching!'), findsNothing);
    expect(find.text('You’re all caught up'), findsOneWidget);
  });

  testWidgets(
    'swiping left deletes the transaction, with an Undo snackbar that restores it',
    (tester) async {
      final model = _FakeReviewViewModel(transaction('tx-1'));
      await tester.pumpWidget(
        MaterialApp(
          theme: SpendWiseTheme.dark,
          home: AnimatedBuilder(
            animation: model,
            builder: (context, child) => ReviewInboxScreen(viewModel: model),
          ),
        ),
      );

      await tester.drag(
        find.byKey(const ValueKey('review-tx-1')),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();

      expect(model.deleted, contains('tx-1'));
      expect(find.text('Cha-Ching!'), findsNothing);
      expect(find.text('Transaction deleted'), findsOneWidget);
      expect(find.byKey(const ValueKey('review-tx-1')), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(model.deleted, isNot(contains('tx-1')));
      expect(find.text('Cha-Ching!'), findsOneWidget);
    },
  );
}

class _FakeReviewViewModel extends ChangeNotifier
    implements SpendWiseViewModel {
  _FakeReviewViewModel(this._transaction);
  final TransactionViewData _transaction;
  final Set<String> confirmed = {};
  final Set<String> deleted = {};

  @override
  List<ReviewViewData> get reviews {
    if (confirmed.contains(_transaction.id) ||
        deleted.contains(_transaction.id)) {
      return const [];
    }
    return [
      ReviewViewData(
        id: _transaction.id,
        reason: ReviewReason.lowConfidence,
        title: 'Review this transaction',
        description: 'The evidence was parsed, but needs confirmation.',
        transactions: [_transaction],
      ),
    ];
  }

  @override
  Future<void> resolveReview(String id, {required bool merge}) async {
    confirmed.add(id);
    notifyListeners();
  }

  @override
  Future<void> deleteTransaction(String id) async {
    deleted.add(id);
    notifyListeners();
  }

  @override
  Future<void> restoreTransaction(String id) async {
    deleted.remove(id);
    notifyListeners();
  }

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
  List<TransactionViewData> get transactions => const [];
  @override
  List<AccountViewData> get accounts => const [];
  @override
  List<SourceViewData> get sources => const [];
  @override
  Future<void> completeOnboarding() async {}
  @override
  Future<void> requestNotificationAccess() async {}
  @override
  Future<void> setSourceEnabled(String packageName, bool enabled) async {}
  @override
  Future<void> addAccount(
    String name,
    String type,
    MoneyViewData openingBalance,
  ) async {}
  @override
  Future<void> saveManualTransaction(ManualTransactionDraft draft) async {}
  @override
  Future<void> exportData() async {}
  @override
  Future<void> eraseAllData() async {}
}
