import '../shell/spendwise_view_model.dart';

/// How far back a reading looks, and how finely it is cut.
///
/// The two day windows are aligned to the calendar rather than rolling back
/// from today, because that is what their names claim. A rolling thirty days
/// labelled "This month" would, on the 3rd, be showing you almost all of last
/// month under this month's name — the exact class of quiet mismatch this
/// app exists to not produce.
enum AnalyticsResolution { thisWeek, thisMonth, months, years }

extension AnalyticsResolutionCopy on AnalyticsResolution {
  String get shortLabel => switch (this) {
    AnalyticsResolution.thisWeek => 'This week',
    AnalyticsResolution.thisMonth => 'This month',
    AnalyticsResolution.months => 'Months',
    AnalyticsResolution.years => 'Years',
  };

  /// The unit one bar covers.
  String get cadence => switch (this) {
    AnalyticsResolution.thisWeek || AnalyticsResolution.thisMonth => 'day',
    AnalyticsResolution.months => 'month',
    AnalyticsResolution.years => 'year',
  };
}

final class AnalyticsBucket {
  const AnalyticsBucket({
    required this.start,
    required this.label,
    required this.spendingMinor,
    required this.incomeMinor,
  });

  final DateTime start;
  final String label;
  final int spendingMinor;
  final int incomeMinor;
}

final class CategoryAnalytics {
  const CategoryAnalytics({
    required this.category,
    required this.amountMinor,
    required this.fraction,
    this.previousAmountMinor = 0,
  });

  final String category;
  final int amountMinor;
  final double fraction;

  /// What this category cost over the comparison window.
  ///
  /// Zero means one of two different things — nothing was spent, or the
  /// category did not exist yet — and the difference matters, so ask
  /// [isNew] rather than reading a percentage off a zero.
  final int previousAmountMinor;

  int get changeMinor => amountMinor - previousAmountMinor;

  /// First seen this period. There is no percentage to quote: everything is
  /// an infinite rise from nothing, which is a true statement that tells a
  /// reader nothing.
  bool get isNew => previousAmountMinor == 0 && amountMinor > 0;

  /// Spent on last period and not this one.
  bool get isStopped => amountMinor == 0 && previousAmountMinor > 0;

  /// Null where no honest percentage exists.
  double? get changePercent {
    if (previousAmountMinor == 0) return null;
    return changeMinor / previousAmountMinor * 100;
  }
}

final class SpendingAnalytics {
  const SpendingAnalytics({
    required this.resolution,
    required this.category,
    required this.buckets,
    required this.categories,
    required this.categoryChanges,
    required this.weekdaySpending,
    required this.totalSpendingMinor,
    required this.totalIncomeMinor,
    required this.previousSpendingMinor,
    required this.averagePerBucketMinor,
    required this.currency,
  });

  final AnalyticsResolution resolution;
  final String? category;
  final List<AnalyticsBucket> buckets;

  /// What this period cost, by category, largest first. Only categories with
  /// spending in it — this answers "where your money went", and a category
  /// nothing went to did not receive any.
  final List<CategoryAnalytics> categories;

  /// The same categories seen against the period before, largest movement in
  /// money first. This is a different list on purpose: it must include a
  /// category that was spent on last period and abandoned this one, which is
  /// exactly the thing [categories] cannot contain.
  final List<CategoryAnalytics> categoryChanges;

  final List<int> weekdaySpending;
  final int totalSpendingMinor;
  final int totalIncomeMinor;
  final int previousSpendingMinor;
  final int averagePerBucketMinor;
  final String currency;

  double? get spendingChangePercent {
    if (previousSpendingMinor == 0) return null;
    return (totalSpendingMinor - previousSpendingMinor) /
        previousSpendingMinor *
        100;
  }

  int get netMinor => totalIncomeMinor - totalSpendingMinor;

  static SpendingAnalytics calculate({
    required List<TransactionViewData> transactions,
    required AnalyticsResolution resolution,
    String? category,
    DateTime? now,
  }) {
    final anchor = now ?? DateTime.now();
    final localNow = DateTime(anchor.year, anchor.month, anchor.day);
    final starts = _bucketStarts(resolution, localNow, transactions);
    final start = starts.first;
    final endExclusive = localNow.add(const Duration(days: 1));
    // The comparison period is the same stretch of the previous calendar
    // unit, cut to the number of days that have elapsed in this one -- so on
    // the 3rd, "this month" is measured against the first three days of last
    // month, not against the whole of it. Comparing three days against thirty
    // would report a collapse in spending at the start of every month.
    final elapsedDays = starts.length;
    final previousStart = switch (resolution) {
      AnalyticsResolution.thisWeek => DateTime(
        start.year,
        start.month,
        start.day - 7,
      ),
      AnalyticsResolution.thisMonth => DateTime(start.year, start.month - 1),
      AnalyticsResolution.months => DateTime(start.year - 1, start.month),
      AnalyticsResolution.years => start,
    };
    final previousEndExclusive = switch (resolution) {
      AnalyticsResolution.thisWeek || AnalyticsResolution.thisMonth =>
        _matchingLength(resolution, previousStart, elapsedDays),
      AnalyticsResolution.months => DateTime(
        endExclusive.year - 1,
        endExclusive.month,
        endExclusive.day,
      ),
      AnalyticsResolution.years => start,
    };
    final spending = List<int>.filled(starts.length, 0);
    final income = List<int>.filled(starts.length, 0);
    final weekdays = List<int>.filled(7, 0);
    final categoryTotals = <String, int>{};
    final previousCategoryTotals = <String, int>{};
    var previousSpending = 0;
    var currency = transactions.firstOrNull?.amount.currency ?? 'PKR';

    for (final transaction in transactions) {
      // Lending is not spending and borrowing is not income, on this screen
      // for the same reason as on Home: the money is coming back.
      if (transaction.isLoanMovement) continue;
      final occurred = transaction.occurredAt.toLocal();
      final amount = transaction.amount.minorUnits.abs();
      currency = transaction.amount.currency;
      final categoryMatches =
          category == null || transaction.category == category;
      if (transaction.kind == TransactionKind.expense &&
          !occurred.isBefore(previousStart) &&
          occurred.isBefore(previousEndExclusive)) {
        // Per category, the comparison period is collected whole, exactly as
        // the current one is: a screen filtered to Groceries still has to be
        // able to say what everything else did.
        previousCategoryTotals.update(
          transaction.category,
          (value) => value + amount,
          ifAbsent: () => amount,
        );
        if (categoryMatches) previousSpending += amount;
      }
      if (occurred.isBefore(start) || !occurred.isBefore(endExclusive)) {
        continue;
      }
      final index = _bucketIndex(occurred, starts, resolution);
      if (index < 0) continue;
      if (transaction.kind == TransactionKind.expense) {
        categoryTotals.update(
          transaction.category,
          (value) => value + amount,
          ifAbsent: () => amount,
        );
        if (categoryMatches) {
          spending[index] += amount;
          weekdays[occurred.weekday - 1] += amount;
        }
      } else if (transaction.kind == TransactionKind.income &&
          category == null) {
        income[index] += amount;
      }
    }

    final totalSpending = spending.fold<int>(0, (sum, value) => sum + value);
    final totalIncome = income.fold<int>(0, (sum, value) => sum + value);
    final allCategorySpending = categoryTotals.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    final categories =
        categoryTotals.entries
            .map(
              (entry) => CategoryAnalytics(
                category: entry.key,
                amountMinor: entry.value,
                fraction: allCategorySpending == 0
                    ? 0
                    : entry.value / allCategorySpending,
              ),
            )
            .toList()
          ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));

    // Every category that took money in either period. A category that was
    // spent on last month and abandoned this one is absent from
    // `categoryTotals` entirely, and "you stopped spending on this" is one of
    // the few things a comparison exists to say.
    final movingNames = <String>{
      ...categoryTotals.keys,
      ...previousCategoryTotals.keys,
    };
    final categoryChanges =
        movingNames
            .map(
              (name) => CategoryAnalytics(
                category: name,
                amountMinor: categoryTotals[name] ?? 0,
                previousAmountMinor: previousCategoryTotals[name] ?? 0,
                fraction: allCategorySpending == 0
                    ? 0
                    : (categoryTotals[name] ?? 0) / allCategorySpending,
              ),
            )
            .toList()
          // By money moved, not by percentage. A category that went from 350
          // to 900 has risen further in percent than one that rose by 6,500
          // rupees, and only one of those is worth the top of a list.
          ..sort((a, b) => b.changeMinor.abs().compareTo(a.changeMinor.abs()));

    return SpendingAnalytics(
      resolution: resolution,
      category: category,
      buckets: [
        for (var index = 0; index < starts.length; index++)
          AnalyticsBucket(
            start: starts[index],
            label: _label(starts[index], resolution),
            spendingMinor: spending[index],
            incomeMinor: income[index],
          ),
      ],
      categories: categories,
      categoryChanges: categoryChanges,
      weekdaySpending: weekdays,
      totalSpendingMinor: totalSpending,
      totalIncomeMinor: totalIncome,
      previousSpendingMinor: previousSpending,
      averagePerBucketMinor: starts.isEmpty
          ? 0
          : (totalSpending / starts.length).round(),
      currency: currency,
    );
  }

  static List<DateTime> _bucketStarts(
    AnalyticsResolution resolution,
    DateTime now,
    List<TransactionViewData> transactions,
  ) => switch (resolution) {
    AnalyticsResolution.thisWeek || AnalyticsResolution.thisMonth => [
      for (
        var day = _windowStart(resolution, now);
        !day.isAfter(now);
        day = DateTime(day.year, day.month, day.day + 1)
      )
        day,
    ],
    AnalyticsResolution.months => [
      for (var offset = 11; offset >= 0; offset--)
        DateTime(now.year, now.month - offset),
    ],
    AnalyticsResolution.years => [
      for (
        var year = _firstYear(transactions, now.year);
        year <= now.year;
        year++
      )
        DateTime(year),
    ],
  };

  /// The first day of the calendar window: Monday for a week, the 1st for a
  /// month. Days are stepped through by date rather than by adding durations,
  /// so a clock change cannot land a bucket an hour either side of midnight.
  static DateTime _windowStart(AnalyticsResolution resolution, DateTime now) =>
      resolution == AnalyticsResolution.thisWeek
      ? DateTime(now.year, now.month, now.day - (now.weekday - 1))
      : DateTime(now.year, now.month);

  /// The end of the comparison window: the same number of days into the
  /// previous unit, but never past the end of it. A reading taken on the 31st
  /// cannot look at thirty-one days of February, so it stops at the 1st of
  /// March and compares the whole of the shorter month instead.
  static DateTime _matchingLength(
    AnalyticsResolution resolution,
    DateTime previousStart,
    int elapsedDays,
  ) {
    final wanted = DateTime(
      previousStart.year,
      previousStart.month,
      previousStart.day + elapsedDays,
    );
    if (resolution == AnalyticsResolution.thisWeek) return wanted;
    final unitEnd = DateTime(previousStart.year, previousStart.month + 1);
    return wanted.isAfter(unitEnd) ? unitEnd : wanted;
  }

  static int _firstYear(List<TransactionViewData> transactions, int fallback) {
    final years = transactions.map((item) => item.occurredAt.toLocal().year);
    if (years.isEmpty) return fallback;
    final earliest = years.reduce((a, b) => a < b ? a : b);
    // Clamped at both ends. The lower bound keeps a very old import from
    // drawing thirty near-empty columns. The upper bound stops a year that
    // has not happened yet from starting the window: the loop that builds
    // the buckets counts up to the current year, so an earliest year in the
    // future produced no buckets at all and `starts.first` threw. The manual
    // entry sheet accepts tomorrow's date, so this is reachable by anyone
    // filing an entry on New Year's Eve, and it crashed the whole tab.
    if (earliest > fallback) return fallback;
    return earliest < fallback - 5 ? fallback - 5 : earliest;
  }

  static int _bucketIndex(
    DateTime value,
    List<DateTime> starts,
    AnalyticsResolution resolution,
  ) {
    for (var index = starts.length - 1; index >= 0; index--) {
      if (!value.isBefore(starts[index])) return index;
    }
    return -1;
  }

  static String _label(DateTime value, AnalyticsResolution resolution) =>
      switch (resolution) {
        // A week reads by weekday; a month of days needs the date, or every
        // label repeats four times over.
        AnalyticsResolution.thisWeek => const [
          'Mon',
          'Tue',
          'Wed',
          'Thu',
          'Fri',
          'Sat',
          'Sun',
        ][value.weekday - 1],
        AnalyticsResolution.thisMonth => '${value.day}',
        AnalyticsResolution.months => const [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ][value.month - 1],
        AnalyticsResolution.years => '${value.year}',
      };
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
