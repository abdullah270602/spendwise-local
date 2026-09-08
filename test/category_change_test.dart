import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/insights/spending_analytics.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// A comparison has to be able to say "you stopped spending on this", and the
/// old shape could not: categories were built from this period's totals alone,
/// so a category that took money last month and none this month simply was not
/// in the list. Silence read as "no change" rather than "it went to zero".
void main() {
  TransactionViewData spend(String category, int minor, DateTime on) =>
      TransactionViewData(
        id: '$category-${on.day}',
        title: category,
        subtitle: '',
        amount: MoneyViewData(-minor),
        kind: TransactionKind.expense,
        occurredAt: on,
        category: category,
        accountId: 'bank',
      );

  // Wednesday the 18th of March: this month is the 1st to the 18th, and the
  // comparison is the 1st to the 18th of February.
  final anchor = DateTime(2026, 3, 18);

  SpendingAnalytics read({String? category}) => SpendingAnalytics.calculate(
    now: anchor,
    resolution: AnalyticsResolution.thisMonth,
    category: category,
    transactions: [
      spend('Groceries', 40000, DateTime(2026, 3, 4)),
      spend('Groceries', 30000, DateTime(2026, 2, 4)),
      spend('Transport', 12000, DateTime(2026, 3, 9)),
      spend('Travel', 90000, DateTime(2026, 2, 11)),
      // Late February, after the 18th: outside the matched window, so it must
      // not count towards what Travel cost last month.
      spend('Travel', 55000, DateTime(2026, 2, 25)),
    ],
  );

  test('a category that stopped is still reported', () {
    final analytics = read();

    expect(
      analytics.categories.map((item) => item.category),
      isNot(contains('Travel')),
      reason: 'nothing went to Travel this month',
    );

    final travel = analytics.categoryChanges.firstWhere(
      (item) => item.category == 'Travel',
    );
    expect(travel.amountMinor, 0);
    expect(travel.previousAmountMinor, 90000);
    expect(travel.isStopped, isTrue);
    expect(travel.changeMinor, -90000);
    expect(
      travel.changePercent,
      -100,
      reason: 'spending on it fell by all of it',
    );
  });

  test('a category first seen this period quotes no percentage', () {
    final transport = read().categoryChanges.firstWhere(
      (item) => item.category == 'Transport',
    );
    expect(transport.isNew, isTrue);
    expect(
      transport.changePercent,
      isNull,
      reason: 'a rise from nothing is infinite, which says nothing',
    );
  });

  test('changes are ordered by money moved, not by percentage', () {
    // Travel moved 90,000, Transport 12,000, Groceries 10,000. Ranked by
    // percentage instead, Transport would lead on an infinite rise from
    // nothing and Groceries' +33% would beat Travel's -100% for second --
    // an order in which the largest movement of money on the screen comes
    // last. That is the ordering this list deliberately does not use.
    expect(read().categoryChanges.map((item) => item.category).toList(), [
      'Travel',
      'Transport',
      'Groceries',
    ]);
  });

  test('the comparison window is cut to the same day of the month', () {
    final travel = read().categoryChanges.firstWhere(
      (item) => item.category == 'Travel',
    );
    expect(
      travel.previousAmountMinor,
      90000,
      reason: 'the 55,000 on 25 February is past the 18th and does not count',
    );
  });

  test('a category that only ever held money is not a spending category', () {
    // Held money arrives and leaves under a category like any other entry,
    // but it was never anybody's here, so it must not create a category the
    // rest of the screen has no figures for.
    final analytics = SpendingAnalytics.calculate(
      now: anchor,
      resolution: AnalyticsResolution.thisMonth,
      transactions: [
        spend('Groceries', 40000, DateTime(2026, 3, 4)),
        TransactionViewData(
          id: 'held-out',
          title: 'Passed on to a relative',
          subtitle: '',
          amount: const MoneyViewData(-200000),
          kind: TransactionKind.expense,
          occurredAt: DateTime(2026, 3, 5),
          category: 'Transfer',
          accountId: 'bank',
          debtId: 'debt-held',
        ),
      ],
    );

    expect(analytics.categories.map((item) => item.category), [
      'Groceries',
    ], reason: 'holding money for someone is not a way of spending it');
    expect(analytics.totalSpendingMinor, 40000);
  });

  test('filtering the screen does not narrow what changed', () {
    // The headline figure follows the filter; the breakdown of what moved
    // must not, or selecting one category would report every other category
    // as having dropped to zero.
    final filtered = read(category: 'Groceries');
    expect(
      filtered.categoryChanges.map((item) => item.category),
      containsAll(<String>['Groceries', 'Transport', 'Travel']),
    );
  });
}
