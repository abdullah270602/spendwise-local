import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/insights/spending_analytics.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// Two defects an adversarial review found, both of which were unreachable
/// before Insights was merged into one view, and both of which the tests
/// written alongside that merge would have sailed past.
void main() {
  // Pinned rather than relative to today. These windows are calendar-aligned
  // now, so "yesterday" falls outside this month on the 1st -- a test that
  // passes thirty days a month and fails on the thirty-first is worse than
  // no test at all.
  final anchor = DateTime(2026, 3, 15);

  TransactionViewData tx({
    required String id,
    required TransactionKind kind,
    required int minor,
    required String category,
    int daysAgo = 1,
  }) => TransactionViewData(
    id: id,
    title: id,
    subtitle: '',
    amount: MoneyViewData(kind == TransactionKind.income ? minor : -minor),
    kind: kind,
    occurredAt: anchor.subtract(Duration(days: daysAgo)),
    category: category,
    accountId: 'bank',
  );

  group('a filtered view has no income to report', () {
    // Income is not attributed to a category -- a salary is not "Groceries" --
    // so a filtered bucket carries none. The spine used to draw the usual
    // net figure from it anyway, which computes `0 - spending`: a confident
    // rust number saying the day lost money, on a day the salary landed.
    final ledger = [
      tx(
        id: 'salary',
        kind: TransactionKind.income,
        minor: 20000000,
        category: 'Income',
      ),
      tx(
        id: 'cinema',
        kind: TransactionKind.expense,
        minor: 240000,
        category: 'Entertainment',
      ),
    ];

    test('unfiltered, the buckets carry the income', () {
      final all = SpendingAnalytics.calculate(
        transactions: ledger,
        resolution: AnalyticsResolution.thisMonth,
        now: anchor,
      );
      expect(
        all.buckets.fold<int>(0, (sum, b) => sum + b.incomeMinor),
        20000000,
      );
    });

    test('filtered, they carry none — so no net may be drawn from them', () {
      final filtered = SpendingAnalytics.calculate(
        transactions: ledger,
        resolution: AnalyticsResolution.thisMonth,
        category: 'Entertainment',
        now: anchor,
      );

      expect(
        filtered.buckets.fold<int>(0, (sum, b) => sum + b.incomeMinor),
        0,
        reason: 'this is the fact the spine has to be told about',
      );
      expect(
        filtered.buckets.fold<int>(0, (sum, b) => sum + b.spendingMinor),
        240000,
      );

      // The figure the old code would have printed, and why it was wrong.
      final wouldHaveShown = filtered.buckets.fold<int>(
        0,
        (sum, b) => sum + (b.incomeMinor - b.spendingMinor),
      );
      expect(
        wouldHaveShown,
        -240000,
        reason: 'a "net loss" on a day 200,000 arrived',
      );
    });
  });

  group('every category gets its own tone', () {
    test('past the end of the ramp, colours stay distinct', () {
      // The ramp is eight. Home draws six, so wrapping was unreachable there.
      // Insights draws every category a person has, and the ninth used to be
      // handed the first colour again -- two categories drawn identically,
      // told apart only by their position in a list.
      final ramp = SpendWiseColors.categoryRamp.length;
      expect(ramp, greaterThan(0));

      final seen = <int>{};
      for (var i = 0; i < ramp * 3; i++) {
        final colour = SpendWiseColors.category(i);
        expect(
          seen.add(colour.toARGB32()),
          isTrue,
          reason: 'category $i repeats a tone already used',
        );
      }
    });

    test('and never fade into the ground they are drawn on', () {
      for (var i = 0; i < 60; i++) {
        expect(
          SpendWiseColors.category(i).a,
          greaterThanOrEqualTo(0.34),
          reason: 'category $i is too faint to see',
        );
      }
    });
  });
}
