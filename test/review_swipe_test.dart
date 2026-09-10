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
    accountName: 'NayaPay',
    isReviewed: false,
  );

  Widget host(_FakeReviewViewModel model) => MaterialApp(
    theme: SpendWiseTheme.dark,
    home: Scaffold(
      body: AnimatedBuilder(
        animation: model,
        builder: (context, child) => ReviewInboxScreen(viewModel: model),
      ),
    ),
  );

  testWidgets('one tap settles every alert a rule covers', (tester) async {
    final model = _FakeReviewViewModel([
      transaction('tx-1'),
      transaction('tx-2'),
      transaction('tx-3'),
    ]);
    await tester.pumpWidget(host(model));

    // Three alerts, one question -- the whole point of the redesign.
    expect(find.text('3 alerts, 1 decision.'), findsOneWidget);

    await tester.tap(find.text('Confirm all 3'));
    await tester.pumpAndSettle();

    expect(model.confirmed, containsAll(['tx-1', 'tx-2', 'tx-3']));
    // The answer is stated where the question was, and it states what the
    // ledger did rather than what the button offered. The rest state waits
    // its turn: the last answer is the one most worth reading, and it used to
    // be swallowed by an empty screen the instant it landed.
    expect(find.text('3 alerts settled.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Nothing needs you.'), findsOneWidget);
  });

  testWidgets('swiping right in the one-by-one sheet confirms an alert', (
    tester,
  ) async {
    final model = _FakeReviewViewModel([transaction('tx-1')]);
    await tester.pumpWidget(host(model));

    await tester.tap(find.text('Check them one by one'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-tx-1')), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('review-tx-1')),
      const Offset(600, 0),
    );
    await tester.pumpAndSettle();

    expect(model.confirmed, contains('tx-1'));
    expect(model.deleted, isNot(contains('tx-1')));
  });

  testWidgets('swiping left deletes, with an Undo that restores it', (
    tester,
  ) async {
    final model = _FakeReviewViewModel([transaction('tx-1')]);
    await tester.pumpWidget(host(model));

    await tester.tap(find.text('Check them one by one'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('review-tx-1')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();

    expect(model.deleted, contains('tx-1'));
    expect(find.text('Transaction deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(model.deleted, isNot(contains('tx-1')));
  });
}

/// Only the members Review actually reads are implemented; `noSuchMethod`
/// covers the rest so growing the view model does not break this test.
class _FakeReviewViewModel extends ChangeNotifier
    implements SpendWiseAdvancedViewModel {
  _FakeReviewViewModel(this._transactions);

  final List<TransactionViewData> _transactions;
  final Set<String> confirmed = {};
  final Set<String> deleted = {};

  @override
  List<TransactionViewData> get transactions => _transactions
      .where((item) => !deleted.contains(item.id))
      .map(
        (item) => confirmed.contains(item.id)
            ? TransactionViewData(
                id: item.id,
                title: item.title,
                subtitle: item.subtitle,
                amount: item.amount,
                kind: item.kind,
                occurredAt: item.occurredAt,
                category: item.category,
                accountName: item.accountName,
              )
            : item,
      )
      .toList();

  @override
  List<ReviewViewData> get reviews => const [];

  @override
  List<AccountViewData> get accounts => const [];

  @override
  List<AlertViewData> get unroutedAlerts => const [];

  @override
  List<AlertViewData> alerts({
    String? packageName,
    bool onlyUnresolved = true,
  }) => const [];

  @override
  Future<void> applyReviewDecision(ReviewDecision decision) async {
    confirmed.addAll(decision.transactionIds);
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
  bool get busy => false;

  @override
  String? get errorMessage => null;

  /// Review asks about loans coming home before it asks anything else, so
  /// it reads the open ones. None here: these tests are about the alert
  /// questions, and a loan question would claim their entries.
  @override
  List<DebtViewData> get debts => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  /// The ledger's category list, which colour is now keyed to so a category
  /// holds one tone as its spending rank moves. Empty here: these fakes have
  /// no ledger, so tones fall back to the order of whatever is drawn, which
  /// is what every screen did before.
  @override
  List<CategoryViewData> get categories => const [];
}
