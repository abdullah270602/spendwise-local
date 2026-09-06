import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/accounts/accounts_screen.dart';
import 'package:spendwise/features/settings/settings_screen.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// A controller created before `showDialog` and disposed when its future
/// completes is disposed one animation too early: the route rebuilds on the
/// way out, hits the dead controller mid-build, and brings down the rest of
/// the frame with assertions that name `_dependents.isEmpty` or a duplicate
/// `GlobalKey` — neither of which points anywhere near the real mistake.
///
/// Both places that did this are covered here. Neither had a widget test;
/// adjusting a balance was only ever checked down at the ledger.
void main() {
  Future<void> openScreen(WidgetTester tester, _Fake viewModel) async {
    // A phone, not the 800x600 default: these sheets are tall and the save
    // button falls off the bottom of the default surface.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Scaffold(body: AccountsScreen(viewModel: viewModel)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('adjusting a balance closes cleanly, without an assertion', (
    tester,
  ) async {
    final viewModel = _Fake();
    await openScreen(tester, viewModel);

    await tester.tap(find.text('Everyday'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adjust balance'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current balance'),
      '31000',
    );
    await tester.tap(find.text('Update balance'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(viewModel.balanceSetTo, 3100000);
    expect(find.text('Adjust account balance'), findsNothing);
    expect(find.text('Manage account'), findsNothing);
  });

  testWidgets('renaming an account closes cleanly, without an assertion', (
    tester,
  ) async {
    final viewModel = _Fake();
    await openScreen(tester, viewModel);

    await tester.tap(find.text('Everyday'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Everyday'),
      'Salary account',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(viewModel.renamedTo, 'Salary account');
    expect(find.text('Manage account'), findsNothing);
  });

  testWidgets('saving your own name closes cleanly, without an assertion', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'SpendWise',
      packageName: 'com.spendwise.app',
      version: '0.9.9',
      buildNumber: '1',
      buildSignature: '',
    );
    final viewModel = _Fake();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: SettingsScreen(viewModel: viewModel),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Your name(s)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'A. Person, A Person');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Your name(s)'), findsOneWidget, reason: 'the tile');
    expect(viewModel.savedNames, ['A. Person', 'A Person']);
  });
}

class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  int? balanceSetTo;
  String? renamedTo;
  List<String>? savedNames;

  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'bank',
      name: 'Everyday',
      type: 'Bank',
      balance: MoneyViewData(2500000),
      suffix: '1234',
    ),
  ];

  @override
  List<SourceViewData> get sources => const [];

  @override
  List<DebtViewData> get debts => const [];

  @override
  DeletedAccountViewData? get lastDeletedAccount => null;

  @override
  String? viewPreference(String key) => null;

  @override
  void setViewPreference(String key, String value) {}

  @override
  bool isSharedSource(String packageName) => false;

  @override
  Future<void> setAccountCurrentBalance(
    String id,
    MoneyViewData balance,
  ) async {
    balanceSetTo = balance.minorUnits;
  }

  @override
  Future<void> updateDetailedAccount(
    String id,
    AccountUpdateDraft draft,
  ) async {
    renamedTo = draft.name;
  }

  @override
  bool get notificationAccessGranted => true;

  @override
  bool get demoDataEnabled => false;

  @override
  bool get showSavingsOnHome => false;

  @override
  HomePeriod get homePeriod => HomePeriod.calendarMonth;

  @override
  List<String> get ownNames => const [];

  @override
  Future<void> setOwnNames(List<String> names) async {
    savedNames = names;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
