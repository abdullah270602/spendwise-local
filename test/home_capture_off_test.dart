import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/dashboard/dashboard_screen.dart';
import 'package:spendwise/features/settings/source_selection_screen.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// Notification access can be granted with every source switched off, and
/// capture is then as dead as it is with access refused. Home answered that
/// state with "the moment a bank alert arrives, this becomes the shape of your
/// month" -- the app's central promise, stated as fact in the one state where
/// it cannot be kept, over a screen that will stay empty forever.
void main() {
  Future<void> pumpHome(WidgetTester tester, _Fake model) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Scaffold(
          body: DashboardScreen(
            viewModel: model,
            onSeeLedger: () {},
            onOpenAccounts: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no source enabled is said out loud, not left to Settings', (
    tester,
  ) async {
    await pumpHome(tester, _Fake());

    expect(find.textContaining('No app is being read'), findsOneWidget);
    expect(
      find.textContaining('The moment a bank alert arrives'),
      findsNothing,
      reason: 'nothing is going to arrive',
    );
  });

  testWidgets('and the way back is a control, not a set of directions', (
    tester,
  ) async {
    await pumpHome(tester, _Fake());

    await tester.tap(find.text('Choose notification sources'));
    await tester.pumpAndSettle();

    expect(find.byType(SourceSelectionScreen), findsOneWidget);
  });

  testWidgets('with a source enabled the promise is made again', (
    tester,
  ) async {
    await pumpHome(tester, _Fake(enabled: true));

    expect(
      find.textContaining('The moment a bank alert arrives'),
      findsOneWidget,
    );
    expect(find.textContaining('No app is being read'), findsNothing);
  });

  testWidgets('and with access refused that is still the first thing to fix', (
    tester,
  ) async {
    // Two things can be wrong at once, and only one of them is worth saying
    // first: a source list is no use to somebody the listener cannot read for.
    await pumpHome(tester, _Fake(granted: false));

    expect(find.text('Turn on notification access'), findsOneWidget);
    expect(find.textContaining('No app is being read'), findsNothing);
  });

  testWidgets('the tray scan is offered on an empty month too', (tester) async {
    // It is the recovery for Android dropping an alert before the listener
    // wakes, so it was hidden in exactly the state that produces -- including
    // a new user's first hour, where a dropped alert looks like an app that
    // does not work.
    await pumpHome(tester, _Fake());

    expect(find.textContaining('SCAN THE TRAY'), findsOneWidget);
  });
}

class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  _Fake({this.granted = true, this.enabled = false});

  final bool granted;
  final bool enabled;

  @override
  bool get notificationAccessGranted => granted;

  @override
  List<SourceViewData> get sources => [
    SourceViewData(
      packageName: 'com.example.bank',
      label: 'Example Bank',
      enabled: enabled,
    ),
  ];

  /// Nothing has moved, which is the state Home makes its promise in.
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
  List<CategoryViewData> get categories => const [];

  @override
  List<DebtViewData> get debts => const [];

  @override
  List<ReviewViewData> get reviews => const [];

  @override
  List<AlertViewData> get unroutedAlerts => const [];

  @override
  bool get showSavingsOnHome => false;

  @override
  HomePeriod get homePeriod => HomePeriod.calendarMonth;

  @override
  String? viewPreference(String key) => null;

  @override
  void setViewPreference(String key, String value) {}

  @override
  Future<void> requestNotificationAccess() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
