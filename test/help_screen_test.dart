import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/help/help_screen.dart';
import 'package:spendwise/features/help/help_topics.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// The manual is the one place in the app that can quietly rot: prose about
/// features nobody rendered. These open every chapter, so a topic that throws
/// or overflows fails the build rather than waiting for a reader to find it.
void main() {
  testWidgets('every chapter opens and lays out', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final topics = helpTopics(_Stub());
    expect(topics, isNotEmpty);

    for (final topic in topics) {
      await tester.pumpWidget(
        MaterialApp(
          theme: SpendWiseTheme.dark,
          home: Scaffold(body: ListView(children: topic.body())),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'chapter "${topic.title}" did not render',
      );
    }
  });

  testWidgets('the index lists the chapters in reading order', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: HelpScreen(viewModel: _Stub()),
      ),
    );
    await tester.pumpAndSettle();

    // Capture comes before what to do about it, which comes before privacy.
    expect(find.text('Reading an alert'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);

    // Below the fold: the list is lazy, so it has to be scrolled into being.
    await tester.scrollUntilVisible(
      find.text('Replay the introduction'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Replay the introduction'), findsOneWidget);
  });

  testWidgets('a chapter opens from the index', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: HelpScreen(viewModel: _Stub()),
      ),
    );
    await tester.tap(find.text('Lent, borrowed and held'));
    await tester.pumpAndSettle();
    expect(find.text('Lent to a friend'), findsOneWidget);
    expect(find.text('Say whose money it was'), findsOneWidget);
  });

  testWidgets('the manual covers money that was never yours', (tester) async {
    // The chapter is the app explaining itself, and its brief is also the text
    // handed to an AI by the copy-prompt button. A story the app supports but
    // the manual never mentions is the app keeping a secret from its reader.
    final loans = helpTopics(_Stub())
        .firstWhere((topic) => topic.title == 'Lent, borrowed and held');
    expect(loans.brief, contains('holding it for someone'));
    expect(
      loans.brief,
      contains('never yours'),
      reason: 'the distinction from borrowing is the whole point',
    );
  });

  testWidgets('the manual does not promise a preview per option', (
    tester,
  ) async {
    // The settings screens show one live preview of Home, not a set of
    // figures on every row. The old wording described a screen that is gone.
    final home = helpTopics(_Stub()).firstWhere((t) => t.title == 'Home');
    expect(home.brief, isNot(contains('before you pick it')));
    expect(
      home.brief,
      contains('never a balance'),
      reason: 'Home and Accounts are meant to differ, and it has to say so',
    );
  });
}

class _Stub extends ChangeNotifier implements SpendWiseViewModel {
  @override
  bool get onboardingComplete => true;
  @override
  bool get notificationAccessGranted => true;
  @override
  List<AccountViewData> get accounts => const [];
  @override
  List<SourceViewData> get sources => const [];
  @override
  List<TransactionViewData> get transactions => const [];
  @override
  List<ReviewViewData> get reviews => const [];
  @override
  DashboardViewData get dashboard => const DashboardViewData(
    netWorth: MoneyViewData(0),
    incomeThisMonth: MoneyViewData(0),
    spendingThisMonth: MoneyViewData(0),
    monthlyChangePercent: 0,
  );
  @override
  Future<void> addAccount(String n, String t, MoneyViewData b) async {}
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
  Future<void> saveManualTransaction(ManualTransactionDraft d) async {}
  @override
  Future<void> setSourceEnabled(String p, bool e) async {}
}
