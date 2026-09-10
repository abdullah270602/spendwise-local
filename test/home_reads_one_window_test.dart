import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/period_figures.dart';
import 'package:spendwise/app/spendwise_controller.dart';
import 'package:spendwise/core/debt_kind.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart' as domain;
import 'package:spendwise/features/dashboard/home_savings.dart';

/// Home is a picture of one stretch of time, and every figure on it has to be
/// a figure about that stretch.
///
/// It was two stretches. Earnings and spending came from the controller's
/// `dashboard`, which resolves a window of its own against the clock at the
/// moment its cache is filled and then holds it until a reload; loans and
/// savings came from the window `homeFigures` resolves for itself. Whenever
/// those two windows were not the same window, Home added last month's
/// earnings to this month's savings and printed the total under one label.
///
/// Two ways they came apart, both reproduced:
///
/// * Every preview that passes an explicit `now` — the period chooser and the
///   dashboard itself — asked for one month and was answered about another.
///   Asking about a day last month returned 50,000,000 received where
///   10,000,000 was correct: last month 100,000 came in, not this month's
///   500,000.
/// * The app left open across midnight on the 1st. The dashboard cache still
///   held September while the window said October, so Home printed the old
///   month's earnings under the new month's name — 50,000,000 where the new
///   month's answer was 0.
///
/// So these tests never assert an implementation. They move `now` and require
/// every figure to move with it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Two months that share nothing: different earnings, different spending,
  /// a different loan out and a different amount put away. Every figure Home
  /// draws differs between them, so a figure taken from the wrong window
  /// cannot coincidentally look right.
  ///
  /// Both are dated to the 1st at midday. The 1st of the current month is
  /// never in the future, and the 1st of the previous month always exists,
  /// whatever today's date happens to be when this runs.
  ({SpendWiseController controller, DateTime earlier, DateTime later})
  twoMonths() {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    final today = DateTime.now();
    final later = DateTime(today.year, today.month, 1, 12);
    final earlier = DateTime(today.year, today.month - 1, 1, 12);

    final bank = ledger.addAccount(
      name: 'Everyday',
      type: domain.AccountType.bank,
      openingBalanceMinor: 0,
    );
    final pot = ledger.addAccount(
      name: 'Emergency fund',
      type: domain.AccountType.savings,
      openingBalanceMinor: 0,
    );

    void month({
      required DateTime day,
      required int earned,
      required int spent,
      required int lent,
      required int putAway,
      required String who,
    }) {
      ledger.addManualTransaction(
        kind: domain.TransactionKind.income,
        amountMinor: earned,
        occurredAt: day,
        accountId: bank,
        description: 'Salary',
      );
      ledger.addManualTransaction(
        kind: domain.TransactionKind.expense,
        amountMinor: spent,
        occurredAt: day,
        accountId: bank,
        description: 'Groceries',
      );
      final out = ledger.addManualTransaction(
        kind: domain.TransactionKind.expense,
        amountMinor: lent,
        occurredAt: day,
        accountId: bank,
        description: 'To $who',
      );
      ledger.openDebt(
        transactionId: out,
        kind: DebtKind.lent,
        counterparty: who,
      );
      ledger.addManualTransaction(
        kind: domain.TransactionKind.transfer,
        amountMinor: putAway,
        occurredAt: day,
        accountId: bank,
        toAccountId: pot,
        description: 'To Emergency fund',
      );
    }

    month(
      day: earlier,
      earned: 10000000,
      spent: 2000000,
      lent: 1000000,
      putAway: 500000,
      who: 'Sana',
    );
    month(
      day: later,
      earned: 50000000,
      spent: 7000000,
      lent: 3000000,
      putAway: 4000000,
      who: 'Bilal',
    );

    // It takes its snapshot on construction, so it is built after the ledger
    // is arranged.
    final controller = SpendWiseController.forTests(ledger);
    addTearDown(controller.dispose);
    return (controller: controller, earlier: earlier, later: later);
  }

  /// Midway through the day the fixture wrote to, so the window that contains
  /// it is unambiguous.
  DateTime middayOn(DateTime day) => DateTime(day.year, day.month, day.day, 18);

  test('Home answers about the month it was asked about', () {
    final (:controller, :earlier, :later) = twoMonths();

    // The current month, which is the only one Home could ever answer about,
    // because that is the one the dashboard happens to have resolved.
    final thisMonth = homeFigures(controller, now: middayOn(later));
    expect(thisMonth.received, 50000000);
    expect(thisMonth.spent, 7000000);
    expect(thisMonth.kept, 40000000);
    expect(thisMonth.saved, 4000000);

    // And the month before it, asked for by name -- which is what the period
    // chooser's preview does every time it is opened.
    final lastMonth = homeFigures(controller, now: middayOn(earlier));
    expect(
      lastMonth.received,
      10000000,
      reason: 'last month 100,000 came in, not this month\'s 500,000',
    );
    expect(lastMonth.spent, 2000000, reason: 'and 20,000 went, not 70,000');
    expect(
      lastMonth.kept,
      7000000,
      reason: 'earned 100,000, spent 20,000, and 10,000 is out on loan',
    );
    expect(lastMonth.saved, 500000, reason: 'the 5,000 put away that month');
  });

  test('every figure moves together when the window moves', () {
    // The bug was never that a figure was wrong on its own. Each was right
    // about *some* window; they were right about different ones, and Home
    // printed the mixture under a single month's name. So the property is
    // not any one number: it is that none of them stays behind.
    final (:controller, :earlier, :later) = twoMonths();

    final before = homeFigures(controller, now: middayOn(earlier));
    final after = homeFigures(controller, now: middayOn(later));

    expect(after.received, isNot(before.received));
    expect(after.spent, isNot(before.spent));
    expect(after.kept, isNot(before.kept));
    expect(after.saved, isNot(before.saved));

    // And every one of them belongs to the window Home says it is drawing --
    // the shared rules, asked directly, over Home's own dates.
    for (final home in [before, after]) {
      final shared = periodFigures(
        transactions: controller.transactions,
        from: home.from,
        to: home.to,
      );
      expect(
        home.received,
        shared.received,
        reason: 'received is measured over ${home.from} .. ${home.to}',
      );
      expect(home.spent, shared.spent, reason: 'and so is spent');
      expect(home.kept, shared.kept, reason: 'and so is what is kept');
      expect(
        home.saved,
        savedInWindow(
          transactions: controller.transactions,
          savingsAccountIds: {
            for (final account in controller.accounts)
              if (!account.isIncluded) account.id,
          },
          from: home.from,
          to: home.to,
        ),
        reason: 'and so is what was put away',
      );
    }
  });

  test('the clock crossing into a new month leaves the old month behind', () {
    // The app open across midnight on the 1st. The dashboard's cache is
    // filled while it is still the old month -- reading it here is what fills
    // it -- and is only ever invalidated by a reload or a period change, so
    // nothing about the new month clears it.
    final (:controller, :earlier, :later) = twoMonths();
    expect(
      controller.dashboard.incomeThisMonth.minorUnits,
      50000000,
      reason: 'the cache is filled against the current month, as it would be',
    );

    final next = DateTime(later.year, later.month + 1, 1, 0, 5);
    final home = homeFigures(controller, now: next);

    expect(
      home.received,
      0,
      reason: 'nothing has come in yet in the month Home now names',
    );
    expect(home.spent, 0);
    expect(home.kept, 0);
    expect(home.saved, 0);
  });
}
