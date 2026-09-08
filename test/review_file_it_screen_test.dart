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
    expect(find.text('File all 2'), findsOneWidget);
    expect(find.text('Drop all 2'), findsOneWidget);
    expect(find.textContaining('Read them first'), findsOneWidget);
  });

  testWidgets('the two follow-up answers are one row of equal halves', (
    tester,
  ) async {
    // Stacked, the wider button read as the more important one purely because
    // its label was longer. Neither the width nor the emphasis should depend
    // on how many characters a label happens to have.
    await openInbox(tester, _Fake());

    final file = tester.getRect(
      find.widgetWithText(OutlinedButton, 'File all 2'),
    );
    final drop = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Drop all 2'),
    );

    expect(
      file.width,
      closeTo(drop.width, 0.5),
      reason: 'equal halves, whatever the labels say',
    );
    expect(file.top, closeTo(drop.top, 0.5), reason: 'one row, not two');
    expect(file.right, lessThanOrEqualTo(drop.left), reason: 'side by side');
    expect(
      file.height,
      closeTo(drop.height, 0.5),
      reason: 'and the same height, so neither sits proud of the other',
    );
  });

  testWidgets('no answer is written with an em dash', (tester) async {
    await openInbox(tester, _Fake());
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.data ?? '', isNot(contains('—')), reason: text.data);
    }
  });

  testWidgets('answering the direction files them', (tester) async {
    final viewModel = _Fake();
    await openInbox(tester, viewModel);

    await tester.tap(find.text('File all 2'));
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
    await tester.tap(find.text('File all 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Money in'));
    await tester.pumpAndSettle();

    expect(viewModel.applied.single.expense, isFalse);
  });

  testWidgets('backing out of the question files nothing', (tester) async {
    // A half-answered question must not become a decision.
    final viewModel = _Fake();
    await openInbox(tester, viewModel);
    await tester.tap(find.text('File all 2'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(viewModel.applied, isEmpty);
  });

  testWidgets('dropping them still works, and asks nothing', (tester) async {
    final viewModel = _Fake();
    await openInbox(tester, viewModel);

    await tester.tap(find.text('Drop all 2'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Which way'), findsNothing);
    expect(viewModel.applied.single.kind, ReviewDecisionKind.dismissSource);
  });

  testWidgets('dropping says so where the question was, and offers Undo', (
    tester,
  ) async {
    // Dismissing is a soft flag in the ledger, so the alerts survive it --
    // but nothing in the app shows an ignored alert, so without this the most
    // destructive answer on the screen was the only one with no way back.
    final viewModel = _Fake();
    await openInbox(tester, viewModel);

    await tester.tap(find.text('Drop all 2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('2 alerts settled.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('and Undo puts back exactly what was hidden', (tester) async {
    final viewModel = _Fake();
    await openInbox(tester, viewModel);

    await tester.tap(find.text('Drop all 2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(viewModel.restored, {
      'a1': 'review',
      'a2': 'error',
    }, reason: 'the prior state, not a uniform one');
  });

  testWidgets('an answer that is not destructive offers no Undo', (
    tester,
  ) async {
    // Filing and attaching are undone by editing the entry they created,
    // which the ledger already offers. Only dropping has no other way back.
    final viewModel = _Fake();
    await openInbox(tester, viewModel);

    await tester.tap(find.text('File all 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Money out'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('settled.'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
  });
}

class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  final applied = <ReviewDecision>[];
  Map<String, String>? restored;

  /// What a dismissal would hide, and what putting it back would restore.
  /// Two rows with different prior states, because restoring them all as
  /// "review" would quietly lose the ones that failed to parse.
  @override
  Map<String, String> unresolvedAlertStatuses(String? packageName) => const {
    'a1': 'review',
    'a2': 'error',
  };

  @override
  Future<void> restoreAlerts(Map<String, String> statuses) async {
    restored = statuses;
  }

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

  /// The ledger's category list, which colour is now keyed to so a category
  /// holds one tone as its spending rank moves. Empty here: these fakes have
  /// no ledger, so tones fall back to the order of whatever is drawn, which
  /// is what every screen did before.
  @override
  List<CategoryViewData> get categories => const [];
}
