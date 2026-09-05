import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/onboarding/onboarding_screen.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// First run is the only screen every single person sees, and the only one
/// they see before they trust the app with anything. It is also the easiest
/// place in an app for prose to creep back in, so the word budget is a test
/// rather than an intention.
void main() {
  Future<_Recorder> pump(
    WidgetTester tester, {
    Size size = const Size(360, 640),
    _Recorder? model,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final viewModel = model ?? _Recorder();
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: OnboardingScreen(viewModel: viewModel),
      ),
    );
    return viewModel;
  }

  Future<void> tapOn(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('it opens by showing the app doing its job', (tester) async {
    await pump(tester);

    // No welcome, no mission statement, no privacy essay: the demo is the
    // pitch. The three cut explainer pages must not have crept back.
    expect(
      find.text('Your bank already tells you everything.'),
      findsOneWidget,
    );
    expect(find.text('Valley Mart'), findsOneWidget);
    expect(find.textContaining('cannot go online'), findsNothing);
  });

  testWidgets('it is four cards, and each one changes something', (
    tester,
  ) async {
    await pump(tester);
    await tapOn(tester, 'Set it up');
    expect(find.text('Done. It can see your alerts.'), findsOneWidget);

    await tapOn(tester, 'Next');
    expect(find.text('Which apps talk about money?'), findsOneWidget);

    await tapOn(tester, 'Next');
    expect(find.text('That is everything.'), findsOneWidget);

    // Four cards and then out: nothing further to page to.
    expect(find.text('Next'), findsNothing);
    expect(find.text('Open SpendWise'), findsOneWidget);
  });

  testWidgets('the permission card names the warning before Android does', (
    tester,
  ) async {
    await pump(tester, model: _Recorder(access: false));
    await tapOn(tester, 'Set it up');

    expect(find.text('Android is about to warn you.'), findsOneWidget);
    expect(
      find.textContaining('reads only the apps you pick next'),
      findsOneWidget,
    );
    // Something checkable beside the promise.
    expect(find.textContaining('No internet permission'), findsOneWidget);
    // And the dead end a sideloaded build walks into.
    expect(find.textContaining('Allow restricted settings'), findsOneWidget);
  });

  testWidgets('it ends on a result, not on a list of chores', (tester) async {
    final model = await pump(tester);
    for (final label in ['Set it up', 'Next', 'Next']) {
      await tapOn(tester, label);
    }

    // The old last page enumerated five unfinished things. Nothing here may
    // read as an unticked box.
    expect(find.text('No app lock'), findsNothing);
    expect(find.text('Your name is not set'), findsNothing);

    expect(model.completed, isFalse);
    await tester.tap(find.text('Open SpendWise'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(model.completed, isTrue);
  });

  testWidgets('nothing off the golden path is asked for', (tester) async {
    await pump(tester);
    for (final label in ['Set it up', 'Next', 'Next']) {
      await tapOn(tester, label);
    }
    // A PIN and your own name matter, but not before the app has done
    // anything for you. Both live in Settings now.
    expect(find.textContaining('PIN'), findsNothing);
    expect(find.textContaining('your bank writes it'), findsNothing);
  });

  testWidgets('every card lays out on a small screen', (tester) async {
    await pump(tester, size: const Size(320, 560));
    for (final label in ['Set it up', 'Next', 'Next']) {
      expect(tester.takeException(), isNull);
      await tapOn(tester, label);
    }
    expect(tester.takeException(), isNull);
  });

  test('the whole flow stays inside its word budget', () {
    // Elite consumer onboarding is often longer than this in screens and an
    // order of magnitude shorter in words; people read roughly a fifth of
    // what is on a screen. The previous version carried about 660 words,
    // which is close to three minutes of reading before any value at all.
    final words = _onboardingCopy
        .expand((line) => line.split(RegExp(r'\s+')))
        .where((word) => word.isNotEmpty)
        .length;
    expect(
      words,
      lessThanOrEqualTo(140),
      reason: 'onboarding prose has crept back up to $words words',
    );
  });
}

/// Every headline and sentence the four cards can show, kept here so the
/// budget is checkable. Labels on buttons and fields are not prose.
const _onboardingCopy = [
  'Your bank already tells you everything.',
  'Android is about to warn you.',
  'It will say SpendWise can read every notification. It reads only the apps '
      'you pick next.',
  'No internet permission, which the guide will show you',
  'Nothing syncs, uploads or backs up',
  'Toggle greyed out? App info, then the menu, then Allow restricted '
      'settings.',
  'Done. It can see your alerts.',
  'Which apps talk about money?',
  'Everything else on your phone stays invisible.',
  'Where should it all land?',
  'The last digits are how an alert finds the right account.',
  'That is everything.',
  'Nothing waiting yet. The next alert lands on its own.',
];

class _Recorder extends ChangeNotifier implements SpendWiseViewModel {
  _Recorder({this.access = true});

  final bool access;
  bool completed = false;

  @override
  Future<void> completeOnboarding() async {
    completed = true;
    notifyListeners();
  }

  @override
  bool get onboardingComplete => false;
  @override
  bool get notificationAccessGranted => access;
  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'bank',
      name: 'Everyday',
      type: 'Bank',
      balance: MoneyViewData(0),
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
