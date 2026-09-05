import '../shell/spendwise_view_model.dart';

enum AnalyticsResolution { days, months, years }

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
  });

  final String category;
  final int amountMinor;
  final double fraction;
}

final class SpendingAnalytics {
  const SpendingAnalytics({
    required this.resolution,
    required this.category,
    required this.buckets,
    required this.categories,
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
  final List<CategoryAnalytics> categories;
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
    final previousStart = switch (resolution) {
      AnalyticsResolution.days => start.subtract(const Duration(days: 7)),
      AnalyticsResolution.months => DateTime(start.year - 1, start.month),
      AnalyticsResolution.years => start,
    };
    final previousEndExclusive = switch (resolution) {
      AnalyticsResolution.days => start,
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
          categoryMatches &&
          !occurred.isBefore(previousStart) &&
          occurred.isBefore(previousEndExclusive)) {
        previousSpending += amount;
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
    AnalyticsResolution.days => [
      for (var offset = 6; offset >= 0; offset--)
        now.subtract(Duration(days: offset)),
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

  static int _firstYear(List<TransactionViewData> transactions, int fallback) {
    final years = transactions.map((item) => item.occurredAt.toLocal().year);
    if (years.isEmpty) return fallback;
    final earliest = years.reduce((a, b) => a < b ? a : b);
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
        AnalyticsResolution.days => const [
          'Mon',
          'Tue',
          'Wed',
          'Thu',
          'Fri',
          'Sat',
          'Sun',
        ][value.weekday - 1],
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
