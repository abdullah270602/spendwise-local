import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';
import 'package:spendwise/features/settings/settings_screen.dart';

/// Four gates, a typed word and a thirty-second countdown, and then the
/// screen simply closed onto a Settings list that looked untouched. Every
/// smaller action on these screens reports itself; the one that destroys
/// everything did not, which is how a completed wipe reads as a failed one --
/// and the obvious response to a wipe that looks like it did not happen is to
/// go round again.
void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'SpendWise',
      packageName: 'com.spendwise.app',
      version: '0.9.34',
      buildNumber: '49',
      buildSignature: '',
    );
  });

  testWidgets('Settings says the data is gone once it is', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final model = _Fake();
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: SettingsScreen(viewModel: model),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Erase all local data'), 400);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase all local data'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ERASE');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase everything'));
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();

    expect(model.erased, isTrue);
    expect(find.text('Everything on this device was erased.'), findsOneWidget);
  });

  testWidgets('and says nothing when the erase was called off', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final model = _Fake();
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: SettingsScreen(viewModel: model),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Erase all local data'), 400);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase all local data'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(model.erased, isFalse);
    expect(find.textContaining('was erased'), findsNothing);
  });
}

class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  bool erased = false;

  @override
  Future<void> eraseAllData() async => erased = true;

  @override
  List<AccountViewData> get accounts => const [];

  @override
  List<SourceViewData> get sources => const [];

  @override
  List<DebtViewData> get debts => const [];

  @override
  List<TransactionViewData> get transactions => const [];

  @override
  List<CategoryViewData> get categories => const [];

  @override
  DeletedAccountViewData? get lastDeletedAccount => null;

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
  String? viewPreference(String key) => null;

  @override
  void setViewPreference(String key, String value) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
