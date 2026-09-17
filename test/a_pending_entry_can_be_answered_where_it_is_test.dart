import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';
import 'package:spendwise/features/transactions/transaction_details_screen.dart';

/// An entry the app is unsure of, opened from the register, used to be read
/// a paragraph and sent somewhere else.
///
/// The flag said: "It is in your ledger and counted in the month. Below 80%
/// SpendWise marks the entry rather than trusting it. Review is where it
/// gets confirmed; Edit is where it gets corrected." Forty-two words naming
/// two verbs, on a screen that had neither control — and the pending mark in
/// the register is exactly what makes a pending row the one you tap.
///
/// The two verbs are the two controls now. The one fact in that paragraph
/// nobody could have guessed — that an unconfirmed entry is counted anyway —
/// is what survived of it.
void main() {
  TransactionViewData pending() => TransactionViewData(
    id: 'tx-1',
    title: 'Corner Grocer',
    subtitle: 'Pocket · wallet',
    amount: const MoneyViewData(-34800),
    kind: TransactionKind.expense,
    occurredAt: DateTime(2026, 9, 9, 18, 42),
    category: 'Groceries',
    accountName: 'Pocket',
    accountId: 'acct-wallet',
    evidenceCount: 0,
    isReviewed: false,
  );

  Future<void> pump(WidgetTester tester, _Fake model) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: TransactionDetailsScreen(
          viewModel: model,
          transaction: pending(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('it can be confirmed without leaving the entry', (tester) async {
    final model = _Fake();
    await pump(tester, model);

    expect(find.text('Confirm'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(model.confirmed, ['tx-1']);
  });

  testWidgets('and the paragraph that sent you elsewhere is gone', (
    tester,
  ) async {
    await pump(tester, _Fake());

    expect(
      find.textContaining('Review is where it gets confirmed'),
      findsNothing,
    );
    expect(find.textContaining('Below 80%'), findsNothing);
    expect(
      find.text('Counted in the month already.'),
      findsOneWidget,
      reason:
          'the one thing in that paragraph a reader could not have '
          'worked out for themselves',
    );
  });
}

class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  final confirmed = <String>[];

  @override
  List<TransactionViewData> get transactions => const [];

  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'acct-wallet',
      name: 'Pocket',
      type: 'wallet',
      balance: MoneyViewData(120000),
    ),
  ];

  @override
  List<DebtViewData> get debts => const [];

  @override
  bool get busy => false;

  @override
  String? get errorMessage => null;

  @override
  Future<void> applyReviewDecision(ReviewDecision decision) async {
    expect(decision.kind, ReviewDecisionKind.confirm);
    confirmed.addAll(decision.transactionIds);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
