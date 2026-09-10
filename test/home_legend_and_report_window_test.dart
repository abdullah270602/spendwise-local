import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/dashboard/dashboard_screen.dart';
import 'package:spendwise/widgets/shape_kit.dart';
import 'package:spendwise/features/reports/report_hero.dart';
import 'package:spendwise/features/reports/spending_report.dart';
import 'package:spendwise/features/dashboard/home_savings.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// Two figures that were quietly wrong for anybody they happened to.
///
/// The first is the worst thing a money app can say: Home told somebody who
/// had just moved 300,000 into savings that they had overspent by 295,000,
/// while the shape drawn directly above those words showed an ordinary month.
/// The ribbon took saving out of what was kept only as far as there was kept
/// money to take it out of; the caption beside it subtracted the whole
/// figure. One clamp, present in one place and missing in the other.
///
/// The second is quieter and hit every monthly report: the previous period
/// was labelled "August 2026" and actually measured August 2nd onwards,
/// because a timestamp difference truncated a day. A salary landing on the
/// 1st vanished from the comparison, turning a fall in spending into what
/// read as a rise from nothing.
void main() {
  group('the legend and the shape set aside the same amount', () {
    Future<void> pumpHome(WidgetTester tester, _SavedMore model) async {
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

    testWidgets('saving more than was kept does not read as overspending', (
      tester,
    ) async {
      // 100,000 came in, 95,000 went out, and 300,000 of money that was
      // already in the account moved into savings. Nothing was overspent --
      // but the caption subtracted the whole 300,000 from the 5,000 that had
      // been kept and announced a 295,000 overspend, beside a shape drawing
      // an ordinary month.
      await pumpHome(tester, _SavedMore());

      expect(find.text('OVERSPENT'), findsNothing);
      expect(
        find.textContaining('-'),
        findsNothing,
        reason: 'nothing on Home should be negative in a month that saved',
      );
    });

    testWidgets('and the shape agrees with the words beside it', (
      tester,
    ) async {
      await pumpHome(tester, _SavedMore());

      // The ribbon has always clamped. The test is that the caption now
      // reaches the same place, so the picture and its own label cannot
      // describe two different months.
      final shape = tester.widget<FlowShape>(find.byType(FlowShape));
      expect(shape.keptMinor, 0);
      expect(find.text('AVAILABLE'), findsOneWidget);
    });
  });

  group('every savings style survives saving more than was kept', () {
    // The denominator is the whole point of the shape, and there are five
    // ways to draw what saving does to it. The clamp that stops a month
    // reading as overspent lives in the legend and in the ribbon separately,
    // and `setsSavingAside` is true for two styles while the ribbon only
    // reduced itself for one -- so "it works" had to be checked against each
    // of them rather than against the default.
    for (final style in HomeSavingsStyle.values) {
      testWidgets('${style.id}: nothing on Home reads as overspent', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: SpendWiseTheme.dark,
            home: Scaffold(
              body: DashboardScreen(
                viewModel: _SavedMore(style: style.id),
                onSeeLedger: () {},
                onOpenAccounts: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('OVERSPENT'),
          findsNothing,
          reason: 'a month that put money away did not overspend',
        );

        // The part is never bigger than the whole, whichever way saving is
        // drawn. A shape that says otherwise is worse than one that omits it.
        final shape = tester.widget<FlowShape>(find.byType(FlowShape));
        expect(
          shape.keptMinor,
          isNonNegative,
          reason: 'the ribbon cannot divide a negative',
        );
        expect(
          shape.keptMinor + shape.spentMinor,
          lessThanOrEqualTo(shape.receivedMinor),
          reason: 'the branches cannot add up to more than what came in',
        );
      });
    }

    testWidgets('and the denominator is the same figure in all five', (
      tester,
    ) async {
      // Whatever saving does to the picture, it does not change what came in.
      // If it did, the same month would be a different size depending on a
      // display setting.
      final denominators = <String, int>{};
      for (final style in HomeSavingsStyle.values) {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: SpendWiseTheme.dark,
            home: Scaffold(
              body: DashboardScreen(
                viewModel: _SavedMore(style: style.id),
                onSeeLedger: () {},
                onOpenAccounts: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        denominators[style.id] = tester
            .widget<FlowShape>(find.byType(FlowShape))
            .receivedMinor;
      }

      expect(denominators.values.toSet(), hasLength(1));
      expect(denominators.values.first, 10000000);
    });
  });

  group('a monthly report compares against the whole month before', () {
    ReportData reportOf(List<TransactionViewData> items) => ReportData.gather(
      request: ReportRequest(
        from: DateTime(2026, 9),
        to: DateTime(2026, 9, 30),
        template: ReportTemplate.ribbon,
        label: 'September 2026',
      ),
      transactions: items,
      accounts: const [],
    );

    TransactionViewData spend(DateTime when, int minor) => TransactionViewData(
      id: '$when-$minor',
      title: 'Shop',
      subtitle: '',
      amount: MoneyViewData(minor),
      kind: TransactionKind.expense,
      occurredAt: when,
      category: 'Groceries',
    );

    test('the first of the previous month is inside the comparison', () {
      // The bug in one line: this expense is dated the 1st, the report says
      // it is comparing against "August 2026", and it used to count nothing.
      final report = reportOf([
        spend(DateTime(2026, 8, 1, 10), 5000000),
        spend(DateTime(2026, 9, 12, 10), 1000000),
      ]);

      expect(report.previousLabel, 'August 2026');
      expect(
        report.previousSpentMinor,
        5000000,
        reason: 'August the 1st is in August',
      );
      expect(
        report.spentDeltaMinor,
        -4000000,
        reason: 'spending fell by 40,000; it used to read as a rise',
      );
    });

    test('and the last of the previous month still is too', () {
      final report = reportOf([spend(DateTime(2026, 8, 31, 23), 5000000)]);
      expect(report.previousSpentMinor, 5000000);
    });

    test('while July stays out of it', () {
      final report = reportOf([spend(DateTime(2026, 7, 31, 23), 5000000)]);
      expect(
        report.previousSpentMinor,
        0,
        reason: 'the window before September is August, not August and July',
      );
    });
  });
}

/// A month that kept a little and put away a lot: 100,000 in, 95,000 out,
/// and 300,000 of money that was already sitting there moved into savings.
///
/// Deliberately built from entries rather than handed-over totals, because a
/// fake that reports figures its own ledger cannot produce is a fake that
/// cannot catch a sum going wrong.
class _SavedMore extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  _SavedMore({this.style = 'available'});

  /// Which of the five ways of drawing saving this run is testing.
  final String style;

  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'current',
      name: 'Everyday',
      type: 'bank',
      balance: MoneyViewData(500000),
    ),
    AccountViewData(
      id: 'pot',
      name: 'Emergency fund',
      type: 'savings',
      isIncluded: false,
      balance: MoneyViewData(30000000),
    ),
  ];

  @override
  List<TransactionViewData> get transactions => [
    TransactionViewData(
      id: 'in',
      title: 'Salary',
      subtitle: '',
      amount: const MoneyViewData(10000000),
      kind: TransactionKind.income,
      occurredAt: DateTime.now().subtract(const Duration(days: 3)),
      category: 'Income',
      accountId: 'current',
    ),
    TransactionViewData(
      id: 'out',
      title: 'Rent',
      subtitle: '',
      amount: const MoneyViewData(9500000),
      kind: TransactionKind.expense,
      occurredAt: DateTime.now().subtract(const Duration(days: 2)),
      category: 'Bills',
      accountId: 'current',
    ),
    TransactionViewData(
      id: 'put-away',
      title: 'To Emergency fund',
      subtitle: '',
      amount: const MoneyViewData(30000000),
      kind: TransactionKind.transfer,
      occurredAt: DateTime.now().subtract(const Duration(days: 1)),
      category: 'Between your accounts',
      accountId: 'current',
      toAccountId: 'pot',
    ),
  ];

  @override
  DashboardViewData get dashboard => const DashboardViewData(
    netWorth: MoneyViewData(30500000),
    incomeThisMonth: MoneyViewData(10000000),
    spendingThisMonth: MoneyViewData(9500000),
    monthlyChangePercent: 5,
  );

  @override
  List<DebtViewData> get debts => const [];

  @override
  List<ReviewViewData> get reviews => const [];

  @override
  List<AlertViewData> get unroutedAlerts => const [];

  @override
  List<CategoryViewData> get categories => const [];

  @override
  bool get showSavingsOnHome => true;

  @override
  HomePeriod get homePeriod => HomePeriod.calendarMonth;

  @override
  String? viewPreference(String key) => key == 'home_savings' ? style : null;

  @override
  void setViewPreference(String key, String value) {}

  @override
  bool get busy => false;

  @override
  String? get errorMessage => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
