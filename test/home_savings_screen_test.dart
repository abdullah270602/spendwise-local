import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/dashboard/dashboard_screen.dart';
import 'package:spendwise/features/dashboard/home_savings.dart';
import 'package:spendwise/features/settings/home_savings_screen.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';
import 'package:spendwise/widgets/chooser_kit.dart';
import 'package:spendwise/widgets/shape_kit.dart';

/// Saving is two choices now -- whether it comes out of the figure, and what
/// line sits underneath -- so the tests are about which question got answered
/// and whether the two stay independent. Never about pixels.
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

  Future<void> choose(WidgetTester tester, String label) async {
    final option = find.text(label);
    // scrollUntilVisible stops as soon as the finder matches, and a lazy list
    // builds a little beyond the viewport -- so the row can be "found" while
    // still sitting below the fold, and the tap lands on nothing. ensureVisible
    // is the one that actually brings it into view.
    await tester.scrollUntilVisible(option, 120);
    await tester.ensureVisible(option);
    await tester.pumpAndSettle();
    await tester.tap(option);
    await tester.pumpAndSettle();
  }

  group('on Home', () {
    testWidgets('off draws nothing about savings', (tester) async {
      await pump(
        tester,
        DashboardScreen(
          viewModel: _Fake(style: 'off'),
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

    testWidgets('a balance is a band and never enters the shape', (
      tester,
    ) async {
      await pump(
        tester,
        DashboardScreen(
          viewModel: _Fake(style: 'off', extra: 'balance'),
          onSeeLedger: () {},
          onOpenAccounts: () {},
        ),
      );
      expect(find.text('SAVINGS'), findsOneWidget);
      expect(
        tester.widget<FlowShape>(find.byType(FlowShape)).saved,
        SavedTreatment.none,
        reason: 'a balance must never enter a picture of flow',
      );
    });

    testWidgets('what I put away is a line, not a change of shape', (
      tester,
    ) async {
      await pump(
        tester,
        DashboardScreen(
          viewModel: _Fake(style: 'off', extra: 'moved'),
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
            viewModel: _Fake(style: id),
            onSeeLedger: () {},
            onOpenAccounts: () {},
          ),
        );
        final shape = tester.widget<FlowShape>(find.byType(FlowShape));
        expect(shape.saved, expected, reason: id);
        expect(shape.savedMinor, 4000000, reason: id);
      }
    });

    testWidgets('the two choices compose', (tester) async {
      // The whole reason for the split: this combination was unreachable.
      await pump(
        tester,
        DashboardScreen(
          viewModel: _Fake(style: 'available', extra: 'moved'),
          onSeeLedger: () {},
          onOpenAccounts: () {},
        ),
      );
      expect(find.text('AVAILABLE'), findsOneWidget);
      expect(find.textContaining('put away this period'), findsOneWidget);
    });

    testWidgets('only what I can spend hides the saved figure entirely', (
      tester,
    ) async {
      // The money is yours; it is simply not available to you, and you would
      // rather not be shown a number for it.
      await pump(
        tester,
        DashboardScreen(
          viewModel: _Fake(style: 'available'),
          onSeeLedger: () {},
          onOpenAccounts: () {},
        ),
      );
      expect(find.text('AVAILABLE'), findsOneWidget);
      expect(find.text('SAVED'), findsNothing);
      expect(find.textContaining('put away'), findsNothing);
      final shape = tester.widget<FlowShape>(find.byType(FlowShape));
      expect(shape.saved, SavedTreatment.none);
      expect(shape.keptMinor, (18000000 - 3500000) - 4000000);
    });

    testWidgets('"nothing underneath" means nothing', (tester) async {
      // Even where the shape draws the saved slice. If you want the figure as
      // well, you ask for it -- otherwise the group label is a lie.
      await pump(
        tester,
        DashboardScreen(
          viewModel: _Fake(style: 'seam'),
          onSeeLedger: () {},
          onOpenAccounts: () {},
        ),
      );
      expect(find.textContaining('put away'), findsNothing);
      expect(find.text('SAVINGS'), findsNothing);
    });

    testWidgets('money taken back out is a different sentence', (tester) async {
      await pump(
        tester,
        DashboardScreen(
          viewModel: _Fake(style: 'off', extra: 'moved', out: true),
          onSeeLedger: () {},
          onOpenAccounts: () {},
        ),
      );
      expect(find.textContaining('taken back out of savings'), findsOneWidget);
      expect(find.textContaining('put away this'), findsNothing);
    });
  });

  group('choosing it', () {
    testWidgets('both questions are asked, and named apart', (tester) async {
      await pump(tester, HomeSavingsScreen(viewModel: _Fake(style: 'off')));
      expect(find.text('IN THE FIGURE'), findsOneWidget);
      for (final style in HomeSavingsStyle.values) {
        await tester.scrollUntilVisible(find.text(style.title), 120);
        expect(find.text(style.title), findsOneWidget, reason: style.id);
      }
      await tester.scrollUntilVisible(find.text('UNDERNEATH'), 120);
      expect(find.text('UNDERNEATH'), findsOneWidget);
      for (final extra in HomeSavingsExtra.values) {
        await tester.scrollUntilVisible(find.text(extra.title), 120);
        expect(find.text(extra.title), findsOneWidget, reason: extra.id);
      }
    });

    testWidgets('picking a treatment stores it', (tester) async {
      final viewModel = _Fake(style: 'off');
      await pump(tester, HomeSavingsScreen(viewModel: viewModel));
      await choose(tester, HomeSavingsStyle.divided.title);
      expect(viewModel.preferences['home_savings'], 'divided');
    });

    testWidgets('picking a line underneath stores it separately', (
      tester,
    ) async {
      final viewModel = _Fake(style: 'off');
      await pump(tester, HomeSavingsScreen(viewModel: viewModel));
      await choose(tester, HomeSavingsExtra.moved.title);
      expect(viewModel.preferences['home_savings_extra'], 'moved');
      expect(
        viewModel.preferences['home_savings'],
        'off',
        reason: 'the figure treatment is a different question',
      );
    });

    testWidgets('choosing a treatment does not silently drop the line', (
      tester,
    ) async {
      // The failure the split exists to prevent: picking one and losing the
      // other without being told.
      final viewModel = _Fake(style: 'off', extra: 'moved');
      await pump(tester, HomeSavingsScreen(viewModel: viewModel));
      await choose(tester, HomeSavingsStyle.seam.title);
      expect(viewModel.preferences['home_savings'], 'seam');
      expect(viewModel.preferences['home_savings_extra'], 'moved');
    });

    testWidgets('one preview, at Home size, not a thumbnail per row', (
      tester,
    ) async {
      await pump(tester, HomeSavingsScreen(viewModel: _Fake(style: 'off')));
      expect(find.byType(FlowShape), findsOneWidget);
      expect(find.byType(ChooserScreen), findsOneWidget);
    });

    testWidgets('the preview stays put while you scroll the options', (
      tester,
    ) async {
      // It used to sit at the top of the same list, so reaching an option
      // scrolled the answer off screen and the choice became a guess.
      await pump(tester, HomeSavingsScreen(viewModel: _Fake(style: 'off')));
      await tester.scrollUntilVisible(
        find.text(HomeSavingsExtra.moved.title),
        120,
      );
      expect(find.byType(FlowShape), findsOneWidget);
    });

    testWidgets('the preview follows the selection', (tester) async {
      final viewModel = _Fake(style: 'off');
      await pump(tester, HomeSavingsScreen(viewModel: viewModel));
      expect(find.text('STILL YOURS'), findsOneWidget);
      expect(find.text('AVAILABLE'), findsNothing);

      await choose(tester, HomeSavingsStyle.available.title);

      expect(find.text('AVAILABLE'), findsOneWidget);
      expect(find.text('STILL YOURS'), findsNothing);
    });

    testWidgets('the figure travels to its new value rather than snapping', (
      tester,
    ) async {
      // The shape and the figure are one statement. A ribbon that redraws
      // beside a number that jumps reads as two unrelated things happening.
      final viewModel = _Fake(style: 'off');
      await pump(tester, HomeSavingsScreen(viewModel: viewModel));
      final before = formatMinor(18000000 - 3500000, cents: false);
      final after = formatMinor(18000000 - 3500000 - 4000000, cents: false);
      expect(find.text(before), findsOneWidget);

      final option = find.text(HomeSavingsStyle.available.title);
      await tester.ensureVisible(option);
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text(after),
        findsNothing,
        reason: 'still on its way there a tenth of a second in',
      );
      expect(
        find.text(before),
        findsNothing,
        reason: 'and no longer where it was',
      );

      await tester.pumpAndSettle();
      expect(find.text(after), findsOneWidget);
    });

    testWidgets('and the ribbon redraws with it', (tester) async {
      // A fresh key each time, so the shape draws itself in again instead of
      // blinking into its new arrangement.
      final viewModel = _Fake(style: 'off');
      await pump(tester, HomeSavingsScreen(viewModel: viewModel));
      final first = tester.widget<FlowShape>(find.byType(FlowShape)).key;

      await choose(tester, HomeSavingsStyle.seam.title);

      final second = tester.widget<FlowShape>(find.byType(FlowShape)).key;
      expect(second, isNot(first));
      expect(second, isNotNull);
    });

    testWidgets('and it shows the real figures, not an abstraction', (
      tester,
    ) async {
      await pump(tester, HomeSavingsScreen(viewModel: _Fake(style: 'off')));
      expect(find.textContaining('180,000'), findsWidgets);
    });
  });
}

class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  _Fake({required String style, String extra = 'none', this.out = false})
    : preferences = {'home_savings': style, 'home_savings_extra': extra};

  final Map<String, String> preferences;
  final bool out;

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

  /// Real entries, because the figures are derived from them now rather than
  /// handed over ready-made. A fake that reports totals its own ledger does
  /// not support cannot catch a sum going wrong.
  @override
  List<TransactionViewData> get transactions => [
    TransactionViewData(
      id: 'in',
      title: 'Salary',
      subtitle: '',
      amount: const MoneyViewData(18000000),
      kind: TransactionKind.income,
      occurredAt: DateTime.now().subtract(const Duration(days: 3)),
      category: 'Income',
      accountId: 'current',
    ),
    TransactionViewData(
      id: 'out',
      title: 'Groceries',
      subtitle: '',
      amount: const MoneyViewData(3500000),
      kind: TransactionKind.expense,
      occurredAt: DateTime.now().subtract(const Duration(days: 2)),
      category: 'Groceries',
      accountId: 'current',
    ),
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
