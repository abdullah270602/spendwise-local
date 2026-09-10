import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/dashboard/dashboard_screen.dart';
import 'package:spendwise/features/dashboard/home_categories.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';
import 'package:spendwise/widgets/shape_kit.dart';

/// The fold was unit-tested and the preview was widget-tested, and the setting
/// still did nothing on Home. Neither test asked the only question that
/// mattered: does the screen it configures actually obey it.
/// Exposed so a sizing probe can build the same Home this file tests.
Widget buildHome(String? choice) => DashboardScreen(
  viewModel: _Fake(choice),
  onSeeLedger: () {},
  onOpenAccounts: () {},
);

void main() {
  /// [height] in logical pixels. The counting tests ask for a screen tall
  /// enough to hold every row, because the breakdown is a lazy sliver: a row
  /// that has not been built is not a row that is missing, and now that each
  /// one is 48px rather than 35 a phone-sized viewport stops building before
  /// the eighth.
  Future<void> pumpHome(
    WidgetTester tester,
    String? choice, {
    double height = 800,
  }) async {
    tester.view.physicalSize = Size(360 * 3, height * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Scaffold(
          body: DashboardScreen(
            viewModel: _Fake(choice),
            onSeeLedger: () {},
            onOpenAccounts: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Home draws its own flow ribbon as a SegmentBar too, so counting bars is
  /// not the test -- counting the named category rows is.
  int rowsOn(WidgetTester tester) =>
      tester.widgetList<CategoryRow>(find.byType(CategoryRow)).length;

  testWidgets('the tray scan sits low and centred when Home is quiet', (
    tester,
  ) async {
    // It is the one control on Home a person reaches for repeatedly, and it
    // used to sit wherever the content happened to end: high on a quiet
    // month, far down a busy one, never twice in the same place.
    await pumpHome(tester, 'off');

    // The button, not its label: the icon sits left of the text, so the
    // text's own centre is not the control's centre.
    final button = tester.getRect(
      find.ancestor(
        of: find.textContaining('SCAN THE TRAY'),
        matching: find.byType(InkWell),
      ),
    );
    final screen = tester.getRect(find.byType(DashboardScreen));

    expect(
      button.center.dx,
      closeTo(screen.center.dx, 1.0),
      reason: 'centred, not hanging off the left gutter',
    );
    expect(
      button.center.dy,
      greaterThan(screen.height * 0.55),
      reason: 'within thumb reach, not floating under the last line of text',
    );
  });

  testWidgets('and stays below the content, never among it', (tester) async {
    // With the breakdown drawn the button comes after every row of it. It is
    // the last thing on Home either way; what changes is only how much space
    // there was to fall through.
    await pumpHome(tester, 'all');

    // With every category drawn the page now runs past the fold, so the
    // button is genuinely below it rather than pinned -- exactly the
    // behaviour asked for. Reach it the way a person would.
    await tester.scrollUntilVisible(
      find.textContaining('SCAN THE TRAY'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final button = tester.getRect(
      find.ancestor(
        of: find.textContaining('SCAN THE TRAY'),
        matching: find.byType(InkWell),
      ),
    );
    final lastRow = tester
        .widgetList<CategoryRow>(find.byType(CategoryRow))
        .last;
    final lastRowRect = tester.getRect(find.byWidget(lastRow));

    expect(
      button.top,
      greaterThan(lastRowRect.bottom),
      reason: 'after the breakdown, not tangled in it',
    );
  });

  testWidgets('every category means every category', (tester) async {
    await pumpHome(tester, 'all', height: 1600);
    expect(rowsOn(tester), 8);
  });

  testWidgets('off means Home draws no breakdown at all', (tester) async {
    await pumpHome(tester, 'off');
    expect(rowsOn(tester), 0, reason: 'the whole point of a calmer Home');
    expect(find.text('Groceries'), findsNothing);
  });

  testWidgets('the five biggest means five, plus the line that keeps it '
      'honest', (tester) async {
    await pumpHome(tester, 'top');
    expect(rowsOn(tester), topCategoryCount + 1);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text(everythingElse), findsOneWidget);
    expect(
      find.text('Fees'),
      findsNothing,
      reason: 'the smallest is folded into the remainder',
    );
  });

  testWidgets('an unset choice draws no breakdown at all', (tester) async {
    // The out-of-the-box Home: the shape and the two figures, and nothing
    // underneath until somebody asks for it in Appearance.
    await pumpHome(tester, null, height: 1600);
    expect(rowsOn(tester), 0);
    expect(find.text('Groceries'), findsNothing);
  });

  testWidgets('the bar and the rows always agree', (tester) async {
    // They are drawn from one fold. If they ever diverge, the bar is dividing
    // a total the list does not add up to, and every slice is drawn wrong.
    for (final (choice, expected) in const [
      ('all', 8),
      ('top', topCategoryCount + 1),
      ('off', 0),
    ]) {
      await pumpHome(tester, choice, height: 1600);
      final rows = tester
          .widgetList<CategoryRow>(find.byType(CategoryRow))
          .toList();
      expect(rows, hasLength(expected), reason: choice);
      if (expected == 0) continue;
      // Home's flow ribbon is the first SegmentBar; the breakdown is the last.
      final bar = tester.widgetList<SegmentBar>(find.byType(SegmentBar)).last;
      expect(
        bar.weights,
        hasLength(expected),
        reason: 'the bar draws exactly the rows beneath it ($choice)',
      );
    }
  });
}

class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  _Fake._(this.preferences);

  /// An unset choice is genuinely a missing key, not an empty string -- the
  /// default only applies when nothing was ever stored.
  factory _Fake(String? choice) =>
      _Fake._(choice == null ? const {} : {'home_categories': choice});

  final Map<String, String> preferences;

  static const _spending = [
    CategorySpendViewData(
      category: 'Groceries',
      amount: MoneyViewData(5000000),
      fraction: 0.37,
    ),
    CategorySpendViewData(
      category: 'Bills',
      amount: MoneyViewData(3000000),
      fraction: 0.22,
    ),
    CategorySpendViewData(
      category: 'Transport',
      amount: MoneyViewData(2000000),
      fraction: 0.15,
    ),
    CategorySpendViewData(
      category: 'Food',
      amount: MoneyViewData(1500000),
      fraction: 0.11,
    ),
    CategorySpendViewData(
      category: 'Health',
      amount: MoneyViewData(1000000),
      fraction: 0.07,
    ),
    CategorySpendViewData(
      category: 'Travel',
      amount: MoneyViewData(600000),
      fraction: 0.04,
    ),
    CategorySpendViewData(
      category: 'Gifts',
      amount: MoneyViewData(400000),
      fraction: 0.03,
    ),
    CategorySpendViewData(
      category: 'Fees',
      amount: MoneyViewData(100000),
      fraction: 0.01,
    ),
  ];

  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'current',
      name: 'Everyday',
      type: 'Bank',
      balance: MoneyViewData(10000000),
    ),
  ];

  @override
  List<TransactionViewData> get transactions => const [];

  @override
  DashboardViewData get dashboard => const DashboardViewData(
    netWorth: MoneyViewData(10000000),
    incomeThisMonth: MoneyViewData(18000000),
    spendingThisMonth: MoneyViewData(13600000),
    monthlyChangePercent: 24,
    categorySpending: _spending,
  );

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
  Future<void> setShowSavingsOnHome(bool enabled) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  /// The ledger's category list, which colour is now keyed to so a category
  /// holds one tone as its spending rank moves. Empty here: these fakes have
  /// no ledger, so tones fall back to the order of whatever is drawn, which
  /// is what every screen did before.
  @override
  List<CategoryViewData> get categories => const [];
}
