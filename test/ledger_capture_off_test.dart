import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/settings/source_selection_screen.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';
import 'package:spendwise/features/transactions/ledger_screen.dart';

/// The Ledger made Home's promise in Home's words: alerts land here once
/// notification access is on. With access on and every source switched off
/// that is a description of an app that is not running, and the register that
/// prints it is the screen the person is staring at.
void main() {
  Future<void> pumpLedger(WidgetTester tester, _Fake model) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Scaffold(body: LedgerScreen(viewModel: model)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an empty register says why it is empty', (tester) async {
    await pumpLedger(tester, _Fake());

    expect(find.textContaining('No app is being read'), findsOneWidget);
    expect(find.textContaining('land here automatically'), findsNothing);
  });

  testWidgets('and offers the same way back Home does', (tester) async {
    await pumpLedger(tester, _Fake());

    await tester.tap(find.text('Choose notification sources'));
    await tester.pumpAndSettle();

    expect(find.byType(SourceSelectionScreen), findsOneWidget);
  });

  testWidgets('with a source enabled it goes back to describing capture', (
    tester,
  ) async {
    await pumpLedger(tester, _Fake(enabled: true));

    expect(find.textContaining('land here automatically'), findsOneWidget);
  });

  testWidgets('a month with nothing in it is a different emptiness', (
    tester,
  ) async {
    // Entries exist, so capture is plainly working; what is empty is this
    // month. Nothing about sources belongs in that answer.
    await pumpLedger(tester, _Fake(recorded: true));

    expect(find.textContaining('No app is being read'), findsNothing);
    expect(find.textContaining('show every month'), findsOneWidget);
  });
}

class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  _Fake({this.enabled = false, this.recorded = false});

  final bool enabled;

  /// Whether the ledger has anything in it at all, in a month that is not
  /// this one.
  final bool recorded;

  @override
  bool get notificationAccessGranted => true;

  @override
  List<SourceViewData> get sources => [
    SourceViewData(
      packageName: 'com.example.bank',
      label: 'Example Bank',
      enabled: enabled,
    ),
  ];

  @override
  List<TransactionViewData> get transactions => recorded
      ? [
          TransactionViewData(
            id: 'old',
            title: 'Grocer',
            subtitle: 'Everyday',
            amount: const MoneyViewData(-150000),
            kind: TransactionKind.expense,
            occurredAt: DateTime(DateTime.now().year - 2, 3, 5),
            category: 'Groceries',
            accountId: 'bank',
          ),
        ]
      : const [];

  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'bank',
      name: 'Everyday',
      type: 'Bank',
      balance: MoneyViewData(0),
    ),
  ];

  @override
  List<CategoryViewData> get categories => const [];

  @override
  DashboardViewData get dashboard => const DashboardViewData(
    netWorth: MoneyViewData(0),
    incomeThisMonth: MoneyViewData(0),
    spendingThisMonth: MoneyViewData(0),
    monthlyChangePercent: 0,
  );

  @override
  List<DebtViewData> get debts => const [];

  @override
  HomePeriod get homePeriod => HomePeriod.calendarMonth;

  @override
  String? viewPreference(String key) => null;

  @override
  void setViewPreference(String key, String value) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
