import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/review/review_inbox_screen.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// The reported dead end, driven through the real screen: an alert SpendWise
/// could not read offered exactly one button, and that button threw the alert
/// away. If it was a real payment — which it usually is — there was nowhere
/// to go.
void main() {
  Future<void> openInbox(WidgetTester tester, _Fake viewModel) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Scaffold(body: ReviewInboxScreen(viewModel: viewModel)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('keeping an alert is offered, and it is offered first', (
    tester,
  ) async {
    await openInbox(tester, _Fake());
    expect(find.textContaining('file all 2'), findsOneWidget);
    expect(find.textContaining('Not transactions'), findsOneWidget);
    expect(find.textContaining('Read them first'), findsOneWidget);
  });

  testWidgets('answering the direction files them', (tester) async {
    final viewModel = _Fake();
    await openInbox(tester, viewModel);

    await tester.tap(find.textContaining('file all 2'));
    await tester.pumpAndSettle();

    // It asks the one thing it could not read, rather than guessing.
    expect(find.text('Which way did the money go, for all 2?'), findsOneWidget);
    await tester.tap(find.text('Money out'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final decision = viewModel.applied.single;
    expect(decision.kind, ReviewDecisionKind.fileAlerts);
    expect(decision.expense, isTrue);
    expect(decision.packageName, 'pk.wallet');
  });

  testWidgets('money in is reachable too, and is not the default', (
    tester,
  ) async {
    final viewModel = _Fake();
    await openInbox(tester, viewModel);
    await tester.tap(find.textContaining('file all 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Money in'));
    await tester.pumpAndSettle();

    expect(viewModel.applied.single.expense, isFalse);
  });

  testWidgets('backing out of the question files nothing', (tester) async {
    // A half-answered question must not become a decision.
    final viewModel = _Fake();
    await openInbox(tester, viewModel);
    await tester.tap(find.textContaining('file all 2'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(viewModel.applied, isEmpty);
  });

  testWidgets('dropping them still works, and asks nothing', (tester) async {
    final viewModel = _Fake();
    await openInbox(tester, viewModel);

    await tester.tap(find.textContaining('Not transactions'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Which way'), findsNothing);
    expect(viewModel.applied.single.kind, ReviewDecisionKind.dismissSource);
  });
}

class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  final applied = <ReviewDecision>[];

  @override
  List<TransactionViewData> get transactions => const [];

  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'wallet',
      name: 'Wallet',
      type: 'Wallet',
      balance: MoneyViewData(0),
    ),
  ];

  @override
  List<ReviewViewData> get reviews => const [
    ReviewViewData(
      id: 'unparsed:pk.wallet',
      reason: ReviewReason.parseFailed,
      title: '2 unread alerts from Wallet',
      description: 'Nothing here says which way the money went.',
      transactions: [],
    ),
  ];

  @override
  List<AlertViewData> get unroutedAlerts => const [];

  @override
  List<AlertViewData> alerts({
    String? packageName,
    bool onlyUnresolved = true,
  }) => const [];

  @override
  Future<void> applyReviewDecision(ReviewDecision decision) async {
    applied.add(decision);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
