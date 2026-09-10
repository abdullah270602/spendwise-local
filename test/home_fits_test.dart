import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/dashboard/dashboard_screen.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// Home on the narrowest phone anyone still carries, at the largest system
/// font Android offers.
///
/// This project shipped a 108px header overflow because every widget test ran
/// at the 800x600 default and scale 1.0. The month legend was carrying the
/// same fault: the first two figures were flexible and the third was not, so
/// "Gone" claimed its intrinsic width before the others were measured and
/// pushed the row 101px off the right of a 360dp screen.
void main() {
  const width = 360.0;
  const height = 800.0;

  Future<void> pumpHome(
    WidgetTester tester,
    _Fake model, {
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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

  /// Every figure in the legend, by the eyebrow that names it.
  void expectLegendOnScreen(WidgetTester tester, List<String> labels) {
    expect(tester.takeException(), isNull, reason: 'the row overflowed');
    for (final label in labels) {
      final rect = tester.getRect(find.text(label));
      expect(
        rect.right,
        lessThanOrEqualTo(width),
        reason: '$label ran off the right edge',
      );
      expect(rect.left, greaterThanOrEqualTo(0), reason: '$label ran off left');
    }
  }

  testWidgets('the legend fits with the breakdown off', (tester) async {
    // The measured worst case: with nothing under it the figures are drawn
    // larger, because there is room for them at scale 1.0 and only then.
    await pumpHome(
      tester,
      _Fake(categories: 'off', savings: 'off'),
      textScale: 2.0,
    );
    expectLegendOnScreen(tester, ['STILL YOURS', 'GONE']);
  });

  testWidgets('and with the breakdown on', (tester) async {
    await pumpHome(
      tester,
      _Fake(categories: 'all', savings: 'off'),
      textScale: 2.0,
    );
    expectLegendOnScreen(tester, ['STILL YOURS', 'GONE']);
  });

  testWidgets('and with saving named as well, which makes it three', (
    tester,
  ) async {
    await pumpHome(
      tester,
      _Fake(categories: 'off', savings: 'siblings'),
      textScale: 2.0,
    );
    expectLegendOnScreen(tester, ['AVAILABLE', 'SAVED', 'GONE']);
  });

  testWidgets('and at the ordinary text size it is unchanged', (tester) async {
    await pumpHome(tester, _Fake(categories: 'off', savings: 'off'));
    expectLegendOnScreen(tester, ['STILL YOURS', 'GONE']);
  });

  testWidgets('everything on Home can be hit', (tester) async {
    // The category rows drew at 35px and the tray scan at 35; the offer of the
    // tour and its dismissal were smaller still.
    final handle = tester.ensureSemantics();
    await pumpHome(tester, _Fake(categories: 'all'));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('and can still be hit at double the text size', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpHome(tester, _Fake(categories: 'all'), textScale: 2.0);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });
}

class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  _Fake({String? categories, String? savings})
    : preferences = {'home_categories': ?categories, 'home_savings': ?savings};

  final Map<String, String> preferences;

  @override
  bool get notificationAccessGranted => true;

  @override
  List<SourceViewData> get sources => const [
    SourceViewData(
      packageName: 'com.example.bank',
      label: 'Example Bank',
      enabled: true,
    ),
  ];

  /// Figures wide enough to be worth measuring: seven digits and a comma is
  /// what a salary looks like here.
  @override
  DashboardViewData get dashboard => const DashboardViewData(
    netWorth: MoneyViewData(2500000000),
    incomeThisMonth: MoneyViewData(1800000000),
    spendingThisMonth: MoneyViewData(1360000000),
    monthlyChangePercent: 24,
    categorySpending: [
      CategorySpendViewData(
        category: 'Groceries',
        amount: MoneyViewData(500000000),
        fraction: 0.37,
      ),
      CategorySpendViewData(
        category: 'Bills',
        amount: MoneyViewData(400000000),
        fraction: 0.29,
      ),
      CategorySpendViewData(
        category: 'Transport',
        amount: MoneyViewData(460000000),
        fraction: 0.34,
      ),
    ],
  );

  /// The entries behind the figures above: a salary of 18,000,000, the three
  /// categories adding to the 13,600,000 spent, and one move into savings so
  /// the "Saved" figure has something to report and the legend draws all
  /// three entries.
  ///
  /// Home works every figure out from these, over the window it names, so a
  /// dashboard claiming a salary this list never received would draw an empty
  /// Home and measure nothing.
  @override
  List<TransactionViewData> get transactions => [
    TransactionViewData(
      id: 'salary',
      title: 'Salary',
      subtitle: 'Everyday',
      amount: const MoneyViewData(1800000000),
      kind: TransactionKind.income,
      occurredAt: DateTime.now(),
      category: 'Income',
      accountId: 'bank',
    ),
    TransactionViewData(
      id: 'groceries',
      title: 'Groceries',
      subtitle: 'Everyday',
      amount: const MoneyViewData(500000000),
      kind: TransactionKind.expense,
      occurredAt: DateTime.now(),
      category: 'Groceries',
      accountId: 'bank',
    ),
    TransactionViewData(
      id: 'bills',
      title: 'Bills',
      subtitle: 'Everyday',
      amount: const MoneyViewData(400000000),
      kind: TransactionKind.expense,
      occurredAt: DateTime.now(),
      category: 'Bills',
      accountId: 'bank',
    ),
    TransactionViewData(
      id: 'transport',
      title: 'Transport',
      subtitle: 'Everyday',
      amount: const MoneyViewData(460000000),
      kind: TransactionKind.expense,
      occurredAt: DateTime.now(),
      category: 'Transport',
      accountId: 'bank',
    ),
    TransactionViewData(
      id: 'put-away',
      title: 'To Emergency fund',
      subtitle: 'Own accounts',
      amount: const MoneyViewData(20000000),
      kind: TransactionKind.transfer,
      occurredAt: DateTime.now(),
      category: 'Savings',
      accountId: 'bank',
      toAccountId: 'fund',
    ),
  ];

  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'bank',
      name: 'Everyday',
      type: 'Bank',
      balance: MoneyViewData(2500000000),
    ),
    AccountViewData(
      id: 'fund',
      name: 'Emergency fund',
      type: 'Savings',
      balance: MoneyViewData(1000000000),
      isIncluded: false,
    ),
  ];

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
  String? viewPreference(String key) => preferences[key];

  @override
  void setViewPreference(String key, String value) => preferences[key] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
