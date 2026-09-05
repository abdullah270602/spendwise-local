import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/onboarding/onboarding_screen.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';
import 'package:spendwise/security/app_lock.dart';

/// First run is the only screen every single person sees, and the only one
/// they see before they trust the app with anything. These walk the whole
/// thing at the smallest screen the app supports, because a nine-page flow is
/// exactly the sort of thing that lays out beautifully on the phone it was
/// written on and overflows on everyone else's.
void main() {
  Future<_Recorder> pumpOnboarding(
    WidgetTester tester, {
    Size size = const Size(360, 640),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final model = _Recorder();
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: AppLockScope(
          lock: AppLockController(preferences: MapLockPreferences()),
          child: OnboardingScreen(viewModel: model),
        ),
      ),
    );
    return model;
  }

  /// Advances by the button rather than by swiping, which is the path that
  /// has to work; swiping is a shortcut for people who already know.
  Future<void> tapOn(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('it explains the app before it asks for anything', (
    tester,
  ) async {
    await pumpOnboarding(tester);

    // The opening claim, and no permission request anywhere near it.
    expect(
      find.text('Every payment you make already sends you a message.'),
      findsOneWidget,
    );
    expect(find.text('Turn on notification access'), findsNothing);

    await tapOn(tester, 'Show me');
    expect(find.text('It reads the alert, not just its number.'), findsOneWidget);

    await tapOn(tester, 'Good');
    expect(
      find.text('It cannot go online. Not "does not" — cannot.'),
      findsOneWidget,
    );
  });

  testWidgets('the worked example shows the trap, not just the answer', (
    tester,
  ) async {
    await pumpOnboarding(tester);
    await tapOn(tester, 'Show me');

    // The balance printed beside the amount is the single most common way to
    // read one of these alerts wrongly, so the example has to name it.
    expect(
      find.textContaining('Avl Bal Rs 61,300.00 is your balance'),
      findsOneWidget,
    );
    expect(find.text('Valley Mart'), findsOneWidget);
    expect(find.text('−2,450.00'), findsOneWidget);
  });

  testWidgets('every page lays out on a small screen', (tester) async {
    await pumpOnboarding(tester, size: const Size(320, 560));

    const labels = [
      'Show me',
      'Good',
      'Set it up',
      'Next',
      'Next',
      'Next',
      'Next',
      'Next',
    ];
    for (final label in labels) {
      expect(tester.takeException(), isNull);
      await tapOn(tester, label);
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Open SpendWise'), findsOneWidget);
  });

  testWidgets('the last page reports what is actually set up', (tester) async {
    final model = await pumpOnboarding(tester);
    for (final label in [
      'Show me',
      'Good',
      'Set it up',
      'Next',
      'Next',
      'Next',
      'Next',
      'Next',
    ]) {
      await tapOn(tester, label);
    }

    // The fake grants access and has one account, but no sources, no name and
    // no lock, so the summary must not claim a clean sweep.
    expect(find.text('Notification access on'), findsOneWidget);
    expect(find.text('1 account'), findsOneWidget);
    expect(find.text('No apps chosen'), findsOneWidget);
    expect(find.text('Your name is not set'), findsOneWidget);
    expect(find.text('No app lock'), findsOneWidget);

    expect(model.completed, isFalse);
    // Not pumpAndSettle: the button stays in its busy state because in the
    // real app the shell replaces this screen the moment onboarding is done,
    // and nothing here does that.
    await tester.tap(find.text('Open SpendWise'));
    await tester.pump();
    expect(model.completed, isTrue);
  });

  testWidgets('a tap on a summary line goes back to that step', (
    tester,
  ) async {
    await pumpOnboarding(tester);
    for (final label in [
      'Show me',
      'Good',
      'Set it up',
      'Next',
      'Next',
      'Next',
      'Next',
      'Next',
    ]) {
      await tapOn(tester, label);
    }

    await tapOn(tester, 'No apps chosen');
    expect(find.text('Which apps talk about money.'), findsOneWidget);
  });

  testWidgets('the permission step says what Android is about to warn about', (
    tester,
  ) async {
    await pumpOnboarding(tester);
    await tapOn(tester, 'Show me');
    await tapOn(tester, 'Good');
    await tapOn(tester, 'Set it up');

    // Access is already granted in the fake, so it should be reporting that
    // rather than asking again.
    expect(find.text('Notification access is on.'), findsOneWidget);
    expect(find.text('Turn on notification access'), findsNothing);
  });
}

class _Recorder extends ChangeNotifier implements SpendWiseViewModel {
  bool completed = false;

  @override
  Future<void> completeOnboarding() async {
    completed = true;
    notifyListeners();
  }

  @override
  bool get onboardingComplete => false;
  @override
  bool get notificationAccessGranted => true;
  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'bank',
      name: 'Everyday',
      type: 'Bank',
      balance: MoneyViewData(2500000),
      suffix: '4821',
    ),
  ];
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
  Future<void> setSourceEnabled(String packageName, bool enabled) async {}
}
