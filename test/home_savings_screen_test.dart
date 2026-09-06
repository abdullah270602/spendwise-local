import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/dashboard/dashboard_screen.dart';
import 'package:spendwise/features/dashboard/home_savings.dart';
import 'package:spendwise/features/settings/home_savings_screen.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';
import 'package:spendwise/widgets/shape_kit.dart';

/// Saving is now a choice of which question Home answers, so the tests are
/// about which question got answered — not about pixels.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('on Home', () {
    testWidgets('off draws nothing about savings', (tester) async {
      await pump(
        tester,
        DashboardScreen(
          viewModel: _Fake('off'),
          onSeeLedger: () {},
          onOpenAccounts: () {},
        ),
      );
      expect(find.textContaining('put away'), findsNothing);
      expect(find.text('SAVINGS'), findsNothing);
      expect(
        tester.widget<FlowShape>(find.byType(FlowShape)).saved,
        SavedTreatment.none,
      );
    });

    testWidgets('the balance shows a band and leaves the shape alone', (
      tester,
    ) async {
      await pump(
        tester,
        DashboardScreen(
          viewModel: _Fake('balance'),
          onSeeLedger: () {},
          onOpenAccounts: () {},
        ),
      );
      expect(find.text('SAVINGS'), findsOneWidget);
      expect(
        tester.widget<FlowShape>(find.byType(FlowShape)).saved,
        SavedTreatment.none,
        reason: 'a balance must never enter the flow',
      );
    });

    testWidgets('what I put away is a line, not a change of shape', (
      tester,
    ) async {
      await pump(
        tester,
        DashboardScreen(
          viewModel: _Fake('moved'),
          onSeeLedger: () {},
          onOpenAccounts: () {},
        ),
      );
      expect(find.textContaining('put away this period'), findsOneWidget);
      expect(
        tester.widget<FlowShape>(find.byType(FlowShape)).saved,
        SavedTreatment.none,
      );
    });

    testWidgets('each shape treatment reaches the shape', (tester) async {
      for (final (id, expected) in const [
        ('siblings', SavedTreatment.branch),
        ('divided', SavedTreatment.inset),
        ('seam', SavedTreatment.seam),
      ]) {
        await pump(
          tester,
          DashboardScreen(
            viewModel: _Fake(id),
            onSeeLedger: () {},
            onOpenAccounts: () {},
          ),
        );
        final shape = tester.widget<FlowShape>(find.byType(FlowShape));
        expect(shape.saved, expected, reason: id);
        expect(shape.savedMinor, 4000000, reason: id);
        // The drawing is always accompanied by the figure it draws.
        expect(find.textContaining('put away'), findsOneWidget, reason: id);
      }
    });

    testWidgets('money taken back out is a different sentence', (tester) async {
      await pump(
        tester,
        DashboardScreen(
          viewModel: _Fake('moved', out: true),
          onSeeLedger: () {},
          onOpenAccounts: () {},
        ),
      );
      expect(find.textContaining('taken back out of savings'), findsOneWidget);
      expect(find.textContaining('put away'), findsNothing);
    });

    testWidgets('a period with no movement says nothing at all', (
      tester,
    ) async {
      await pump(
        tester,
        DashboardScreen(
          viewModel: _Fake('divided', none: true),
          onSeeLedger: () {},
          onOpenAccounts: () {},
        ),
      );
      expect(find.textContaining('put away'), findsNothing);
      expect(tester.widget<FlowShape>(find.byType(FlowShape)).savedMinor, 0);
    });
  });

  group('choosing it', () {
    testWidgets('every option is offered, named by its question', (
      tester,
    ) async {
      await pump(tester, HomeSavingsScreen(viewModel: _Fake('off')));
      for (final style in HomeSavingsStyle.values) {
        await tester.scrollUntilVisible(find.text(style.title), 120);
        expect(find.text(style.title), findsOneWidget, reason: style.id);
      }
    });

    testWidgets('picking one stores it', (tester) async {
      final viewModel = _Fake('off');
      await pump(tester, HomeSavingsScreen(viewModel: viewModel));
      await tester.scrollUntilVisible(
        find.text(HomeSavingsStyle.divided.title),
        120,
      );
      await tester.tap(find.text(HomeSavingsStyle.divided.title));
      await tester.pumpAndSettle();
      expect(viewModel.preferences['home_savings'], 'divided');
    });

    testWidgets('and it shows the real figures, not an abstraction', (
      tester,
    ) async {
      await pump(tester, HomeSavingsScreen(viewModel: _Fake('off')));
      expect(find.textContaining('40,000'), findsOneWidget);
    });
  });
}

class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  _Fake(String style, {this.out = false, this.none = false})
    : preferences = {'home_savings': style};

  final Map<String, String> preferences;
  final bool out;
  final bool none;

  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'current',
      name: 'Everyday',
      type: 'Bank',
      balance: MoneyViewData(10000000),
    ),
    AccountViewData(
      id: 'pot',
      name: 'Emergency fund',
      type: 'Savings',
      isIncluded: false,
      balance: MoneyViewData(25000000),
    ),
  ];

  @override
  List<TransactionViewData> get transactions => [
    if (!none)
      TransactionViewData(
        id: 't',
        title: 'To savings',
        subtitle: '',
        amount: const MoneyViewData(4000000),
        kind: TransactionKind.transfer,
        occurredAt: DateTime.now().subtract(const Duration(days: 1)),
        category: 'Between your accounts',
        accountId: out ? 'pot' : 'current',
        toAccountId: out ? 'current' : 'pot',
      ),
  ];

  @override
  DashboardViewData get dashboard => const DashboardViewData(
    netWorth: MoneyViewData(35000000),
    incomeThisMonth: MoneyViewData(18000000),
    spendingThisMonth: MoneyViewData(3500000),
    monthlyChangePercent: 80,
  );

  @override
  List<DebtViewData> get debts => const [];

  @override
  List<ReviewViewData> get reviews => const [];

  @override
  List<AlertViewData> get unroutedAlerts => const [];

  @override
  bool get showSavingsOnHome => preferences['home_savings'] != 'off';

  @override
  HomePeriod get homePeriod => HomePeriod.calendarMonth;

  @override
  String? viewPreference(String key) => preferences[key];

  @override
  void setViewPreference(String key, String value) => preferences[key] = value;

  @override
  Future<void> setShowSavingsOnHome(bool enabled) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
