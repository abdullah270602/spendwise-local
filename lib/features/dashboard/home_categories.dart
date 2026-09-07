import '../shell/spendwise_view_model.dart';

/// How much of the spending breakdown Home draws.
///
/// Home answers one question above the fold; the breakdown underneath answers
/// the next one. Some people want that second answer in full, some want only
/// the shape of it, and some would rather Home stopped at the first question
/// and stayed quiet.
enum HomeCategories {
  /// No bar, no rows. Home stops at what came in and what left.
  off(
    id: 'off',
    title: "Don't show the breakdown",
    detail: 'Home stops at what came in and what left.',
  ),

  /// The biggest few by name, everything after them as one line.
  top(
    id: 'top',
    title: 'The five biggest',
    detail: 'The rest are grouped into one line, so it still adds up.',
  ),

  /// Every category, however many there are.
  all(
    id: 'all',
    title: 'Every category',
    detail: 'The full breakdown, however long it runs.',
  );

  const HomeCategories({
    required this.id,
    required this.title,
    required this.detail,
  });

  final String id;
  final String title;
  final String detail;

  /// The default is [all]: the breakdown is what Home is for once the top
  /// figure is read, and hiding it by default would answer a question nobody
  /// asked.
  static HomeCategories fromId(String? id) {
    for (final style in values) {
      if (style.id == id) return style;
    }
    return all;
  }
}

/// How many are named before the rest are folded together.
const topCategoryCount = 5;

/// The row that stands for everything not named above it.
const everythingElse = 'Everything else';

/// True for the folded row, which is drawn in a neutral tone: it is not a
/// category, it is the absence of a list of them.
bool isRemainder(CategorySpendViewData item) => item.category == everythingElse;

/// The categories Home should draw, in order, largest first.
///
/// The fold is not a truncation. The bar above these rows is drawn to true
/// proportion, so dropping the tail would stretch the survivors to fill it --
/// a category worth a fifth of the month's spending would render as though it
/// were worth twice that, and the rows would stop summing to what left. So
/// the remainder is kept as one line: fewer names, same total, same shape.
///
/// Folding a single category would be worse than not folding at all, since it
/// replaces a real name with "everything else" and saves nobody a row. The
/// fold therefore only happens when it actually shortens the list.
List<CategorySpendViewData> categoriesForHome(
  Iterable<CategorySpendViewData> spending,
  HomeCategories style,
) {
  if (style == HomeCategories.off) return const [];

  final sorted = [...spending]
    ..sort((a, b) => b.amount.minorUnits.compareTo(a.amount.minorUnits));
  if (style == HomeCategories.all) return sorted;
  if (sorted.length <= topCategoryCount + 1) return sorted;

  final named = sorted.take(topCategoryCount).toList();
  final rest = sorted.skip(topCategoryCount);
  var remainderMinor = 0;
  var remainderFraction = 0.0;
  var currency = 'PKR';
  for (final item in rest) {
    remainderMinor += item.amount.minorUnits;
    remainderFraction += item.fraction;
    currency = item.amount.currency;
  }

  return [
    ...named,
    CategorySpendViewData(
      category: everythingElse,
      amount: MoneyViewData(remainderMinor, currency: currency),
      fraction: remainderFraction,
    ),
  ];
}
