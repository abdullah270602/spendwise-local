import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/review/review_inbox_screen.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// The loan question on the screen it is actually asked on. A rule that
/// builds correctly and never reaches the inbox is not a feature, and the
/// answer that matters here is the one that carries the loan: without it the
/// entry stays counted as income no matter what the loan says.
void main() {
  final opened = DateTime(2026, 9, 2);

  final loan = DebtViewData(
    id: 'loan',
    kind: DebtKind.lent,
    counterparty: 'Sana',
    principal: const MoneyViewData(5000000),
    settled: const MoneyViewData(0),
    outstanding: const MoneyViewData(5000000),
    openedAt: opened,
    isSettled: false,
  );

  TransactionViewData repayment() => TransactionViewData(
    id: 'back',
    title: 'From Sana',
    subtitle: 'Everyday',
    amount: const MoneyViewData(5000000),
    kind: TransactionKind.income,
    occurredAt: opened.add(const Duration(days: 18)),
    category: 'Uncategorised',
    accountName: 'Everyday',
    accountId: 'acc',
    isReviewed: false,
  );

  Widget host(_Fake model) => MaterialApp(
    theme: SpendWiseTheme.dark,
    home: Scaffold(
      body: AnimatedBuilder(
        animation: model,
        builder: (context, child) => ReviewInboxScreen(viewModel: model),
      ),
    ),
  );

  testWidgets('the loan question is asked, and it names the loan', (
    tester,
  ) async {
    final model = _Fake(transactions: [repayment()], debts: [loan]);
    await tester.pumpWidget(host(model));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sana has money out with you'), findsOneWidget);
    expect(find.text('Record it against the loan'), findsOneWidget);
    expect(find.text('No, it is ordinary money in'), findsOneWidget);
  });

  testWidgets('answering it sends the loan and the entry together', (
    tester,
  ) async {
    final model = _Fake(transactions: [repayment()], debts: [loan]);
    await tester.pumpWidget(host(model));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Record it against the loan'));
    await tester.pumpAndSettle();

    expect(model.applied, hasLength(1));
    expect(model.applied.single.kind, ReviewDecisionKind.settleLoan);
    expect(model.applied.single.debtId, 'loan');
    expect(model.applied.single.transactionIds, [
      'back',
    ], reason: 'the entry is what takes the money out of the month');
  });

  testWidgets('refusing it files the entry as ordinary money', (tester) async {
    final model = _Fake(transactions: [repayment()], debts: [loan]);
    await tester.pumpWidget(host(model));
    await tester.pumpAndSettle();

    await tester.tap(find.text('No, it is ordinary money in'));
    await tester.pumpAndSettle();

    expect(model.applied.single.kind, ReviewDecisionKind.confirm);
    expect(model.applied.single.debtId, isNull);
  });
}

/// Only what the inbox reads. `noSuchMethod` covers the rest.
class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  _Fake({required this.transactions, required List<DebtViewData> debts})
    // ignore: prefer_initializing_formals
    : _debts = debts;

  final List<DebtViewData> _debts;
  final List<ReviewDecision> applied = [];

  /// Capture is live in these tests. Review and Insights now say out loud
  /// when nothing is being read, and a fake that refuses the question would
  /// drop every test here into the capture-off state rather than the one it
  /// is about.
  @override
  bool get notificationAccessGranted => true;

  @override
  List<SourceViewData> get sources => const [
    SourceViewData(
      packageName: 'com.example.bank',
      label: 'Example Bank',
      enabled: true,
    ),
  ];

  @override
  List<TransactionViewData> transactions;

  @override
  List<DebtViewData> get debts => _debts;

  @override
  List<ReviewViewData> get reviews => const [];

  @override
  List<AlertViewData> get unroutedAlerts => const [];

  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'acc',
      name: 'Everyday',
      type: 'bank',
      balance: MoneyViewData(0),
    ),
  ];

  @override
  Future<void> applyReviewDecision(ReviewDecision decision) async {
    applied.add(decision);
    transactions = const [];
    notifyListeners();
  }

  @override
  Map<String, String> unresolvedAlertStatuses(String? packageName) => const {};

  @override
  bool get busy => false;

  @override
  String? get errorMessage => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
