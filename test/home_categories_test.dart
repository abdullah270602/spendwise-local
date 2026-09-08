import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/dashboard/home_categories.dart';
import 'package:spendwise/features/dashboard/home_preview.dart';
import 'package:spendwise/features/settings/home_categories_screen.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';
import 'package:spendwise/widgets/shape_kit.dart';

/// The breakdown under Home's figures is drawn to true proportion, so showing
/// only part of it is not a matter of taste -- drop the tail and the survivors
/// stretch to fill the bar, and a category worth a fifth of the month gets
/// drawn as though it were worth twice that.
void main() {
  CategorySpendViewData spend(String name, int minor) => CategorySpendViewData(
    category: name,
    amount: MoneyViewData(minor),
    fraction: minor / 100000,
  );

  final eight = [
    spend('Groceries', 5000000),
    spend('Bills', 3000000),
    spend('Transport', 2000000),
    spend('Food', 1500000),
    spend('Health', 1000000),
    spend('Travel', 600000),
    spend('Gifts', 400000),
    spend('Fees', 100000),
  ];

  int total(List<CategorySpendViewData> items) =>
      items.fold<int>(0, (sum, item) => sum + item.amount.minorUnits);

  group('the fold', () {
    test('every category is every category', () {
      final result = categoriesForHome(eight, HomeCategories.all);
      expect(result, hasLength(8));
      expect(total(result), total(eight));
    });

    test('nothing at all is nothing at all', () {
      expect(categoriesForHome(eight, HomeCategories.off), isEmpty);
    });

    test('the five biggest are named, and the rest are still counted', () {
      final result = categoriesForHome(eight, HomeCategories.top);

      expect(result, hasLength(topCategoryCount + 1));
      expect(result.take(5).map((i) => i.category), [
        'Groceries',
        'Bills',
        'Transport',
        'Food',
        'Health',
      ]);
      expect(result.last.category, everythingElse);
      expect(result.last.amount.minorUnits, 600000 + 400000 + 100000);
    });

    test('and the total is untouched, which is the whole point', () {
      // The bar above these rows divides this total. If folding lost money,
      // every remaining slice would be drawn wider than it is.
      expect(
        total(categoriesForHome(eight, HomeCategories.top)),
        total(eight),
        reason: 'the fold groups the tail, it does not discard it',
      );
    });

    test('largest first, whatever order they arrived in', () {
      final shuffled = [eight[4], eight[0], eight[7], eight[2]];
      final result = categoriesForHome(shuffled, HomeCategories.all);
      expect(result.first.category, 'Groceries');
      expect(result.last.category, 'Fees');
    });

    test('folding one category is not worth doing', () {
      // Six categories would become five plus "everything else" -- one real
      // name traded for a vaguer one, and not a single row saved.
      final six = eight.take(6).toList();
      final result = categoriesForHome(six, HomeCategories.top);
      expect(result, hasLength(6));
      expect(result.map((i) => i.category), isNot(contains(everythingElse)));
    });

    test('a short list is left alone', () {
      final three = eight.take(3).toList();
      expect(categoriesForHome(three, HomeCategories.top), hasLength(3));
    });

    test('nothing spent stays nothing spent', () {
      expect(categoriesForHome(const [], HomeCategories.top), isEmpty);
      expect(categoriesForHome(const [], HomeCategories.all), isEmpty);
    });

    test('the remainder is marked so it is not coloured like a category', () {
      final result = categoriesForHome(eight, HomeCategories.top);
      expect(isRemainder(result.last), isTrue);
      expect(result.take(5).any(isRemainder), isFalse);
    });
  });

  group('choosing it', () {
    test('the default draws everything', () {
      // Hiding the breakdown by default would answer a question nobody asked.
      expect(HomeCategories.fromId(null), HomeCategories.all);
      expect(HomeCategories.fromId('nonsense'), HomeCategories.all);
    });

    test('a stored choice wins', () {
      expect(HomeCategories.fromId('off'), HomeCategories.off);
      expect(HomeCategories.fromId('top'), HomeCategories.top);
    });

    test('each option is named after what it does, briefly', () {
      for (final style in HomeCategories.values) {
        expect(style.title, isNotEmpty);
        expect(style.detail, isNotEmpty, reason: style.id);
        expect(style.detail.length, lessThan(80), reason: style.id);
      }
    });

    testWidgets('the preview draws the real bar and the real rows', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: SpendWiseTheme.dark,
          home: Scaffold(body: HomeCategoriesScreen(viewModel: _Fake(eight))),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SegmentBar), findsOneWidget);
      for (final style in HomeCategories.values) {
        expect(find.text(style.title), findsOneWidget, reason: style.id);
      }
    });

    testWidgets('turning it off says so rather than going blank', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final viewModel = _Fake(eight);
      await tester.pumpWidget(
        MaterialApp(
          theme: SpendWiseTheme.dark,
          home: Scaffold(body: HomeCategoriesScreen(viewModel: viewModel)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(HomeCategories.off.title));
      await tester.pumpAndSettle();

      expect(viewModel.preferences['home_categories'], 'off');
      expect(find.byType(SegmentBar), findsNothing);
      expect(
        find.textContaining('Home ends after the figures'),
        findsOneWidget,
      );
    });

    testWidgets('the preview admits to the lines it could not draw', (
      tester,
    ) async {
      // A pinned preview cannot grow with the list, and stopping silently
      // would make the same claim the fold exists to avoid.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: SpendWiseTheme.dark,
          home: Scaffold(
            body: CategoryPreview(spending: eight, style: HomeCategories.all),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('more lines'), findsOneWidget);
    });
  });
}

class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  _Fake(this.spending);

  final List<CategorySpendViewData> spending;
  final Map<String, String> preferences = {};

  @override
  DashboardViewData get dashboard => DashboardViewData(
    netWorth: const MoneyViewData(0),
    incomeThisMonth: const MoneyViewData(18000000),
    spendingThisMonth: const MoneyViewData(13600000),
    monthlyChangePercent: 0,
    categorySpending: spending,
  );

  @override
  String? viewPreference(String key) => preferences[key];

  @override
  void setViewPreference(String key, String value) => preferences[key] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  /// The ledger's category list, which colour is now keyed to so a category
  /// holds one tone as its spending rank moves. Empty here: these fakes have
  /// no ledger, so tones fall back to the order of whatever is drawn, which
  /// is what every screen did before.
  @override
  List<CategoryViewData> get categories => const [];
}
