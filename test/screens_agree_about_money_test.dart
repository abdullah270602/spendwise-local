import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/period_figures.dart';
import 'package:spendwise/app/spendwise_controller.dart';
import 'package:spendwise/core/debt_kind.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart' as domain;
import 'package:spendwise/features/dashboard/home_savings.dart';
import 'package:spendwise/features/reports/report_hero.dart';
import 'package:spendwise/features/reports/spending_report.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// The test that would have caught every money bug found in this app.
///
/// Home, the PDF report and Insights each worked out what came in and what
/// was still yours, separately, and drifted. Not in a corner: in the two
/// figures the app leads with, printed under the same words. Home subtracted
/// a loan made that month from "Still yours"; the report printed the same two
/// words having subtracted nothing. Each version was locally reasonable,
/// which is why reading either file alone found nothing wrong.
///
/// So this does not test an implementation. It builds one month containing
/// every awkward thing at once and asserts the screens agree with each other
/// — which is the only property a person can actually check, by holding two
/// screens side by side.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// One month with all of it: earnings, ordinary spending, money lent out
  /// and not yet back, money held for somebody else, and a move into savings.
  ({SpendWiseController controller, LocalLedger ledger}) monthWithEverything({
    bool repayTheLoan = false,
  }) {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, 2, 12);

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

    ledger.addManualTransaction(
      kind: domain.TransactionKind.income,
      amountMinor: 20000000,
      occurredAt: day,
      accountId: bank,
      description: 'Salary',
    );
    ledger.addManualTransaction(
      kind: domain.TransactionKind.expense,
      amountMinor: 7000000,
      occurredAt: day,
      accountId: bank,
      description: 'Groceries',
    );

    // Lent out, and still out unless this run says otherwise.
    final lent = ledger.addManualTransaction(
      kind: domain.TransactionKind.expense,
      amountMinor: 3000000,
      occurredAt: day,
      accountId: bank,
      description: 'To Sana',
    );
    final loan = ledger.openDebt(
      transactionId: lent,
      kind: DebtKind.lent,
      counterparty: 'Sana',
    );
    if (repayTheLoan) {
      final back = ledger.addManualTransaction(
        kind: domain.TransactionKind.income,
        amountMinor: 3000000,
        occurredAt: day.add(const Duration(days: 3)),
        accountId: bank,
        description: 'From Sana',
      );
      ledger.settleDebt(
        debtId: loan.id,
        amountMinor: 3000000,
        transactionId: back,
      );
    }

    // Somebody else's money, passing through. Never the owner's on any leg.
    final held = ledger.addManualTransaction(
      kind: domain.TransactionKind.income,
      amountMinor: 4000000,
      occurredAt: day,
      accountId: bank,
      description: 'From Bilal',
    );
    ledger.openDebt(
      transactionId: held,
      kind: DebtKind.holding,
      counterparty: 'Bilal',
    );

    ledger.addManualTransaction(
      kind: domain.TransactionKind.transfer,
      amountMinor: 2000000,
      occurredAt: day,
      accountId: bank,
      toAccountId: pot,
      description: 'To Emergency fund',
    );

    final controller = SpendWiseController.forTests(ledger);
    addTearDown(controller.dispose);
    return (controller: controller, ledger: ledger);
  }

  ReportData reportFor(SpendWiseController controller, HomeFigures home) =>
      ReportData.gather(
        request: ReportRequest(
          from: home.from,
          // Home's window is half-open and the report's is inclusive of its
          // last day, so the same stretch of time is named differently by
          // each. This is the one place that difference is spelled out.
          to: home.to.subtract(const Duration(days: 1)),
          template: ReportTemplate.ribbon,
          label: 'Test window',
        ),
        transactions: controller.transactions,
        accounts: controller.accounts,
        debts: controller.debts,
      );

  test('Home and the report agree about what came in and what is kept', () {
    final (:controller, :ledger) = monthWithEverything();
    final home = homeFigures(controller);
    final report = reportFor(controller, home);

    expect(
      report.receivedMinor,
      home.received,
      reason: 'both screens print this under the words "came in"',
    );
    expect(
      report.keptMinor,
      home.kept,
      reason: 'both screens print this under the words "Still yours"',
    );
    expect(report.spentMinor, home.spent);
  });

  test('and still agree once the loan comes back', () {
    // The round trip: money that left and returned inside one window. It is
    // one note moving, not income, and counting both legs made the month read
    // as twice its size on whichever screen counted them.
    final (:controller, :ledger) = monthWithEverything(repayTheLoan: true);
    final home = homeFigures(controller);
    final report = reportFor(controller, home);

    expect(report.receivedMinor, home.received);
    expect(report.keptMinor, home.kept);
  });

  test('a loan still out is subtracted from what is kept, on both', () {
    final (:controller, :ledger) = monthWithEverything();
    final home = homeFigures(controller);
    final report = reportFor(controller, home);

    // Earned 200,000, spent 70,000, lent 30,000 that has not come back.
    expect(home.received, 20000000, reason: 'the loan going out is not income');
    expect(home.spent, 7000000, reason: 'lending is not spending');
    expect(
      home.kept,
      10000000,
      reason: 'the 30,000 lent out is not still yours',
    );
    expect(report.keptMinor, 10000000);
  });

  test('a round trip inflates neither screen', () {
    final (:controller, :ledger) = monthWithEverything(repayTheLoan: true);
    final home = homeFigures(controller);

    expect(
      home.received,
      20000000,
      reason: 'the same note leaving and returning is not money coming in',
    );
    expect(
      home.kept,
      13000000,
      reason: 'earned 200,000, spent 70,000, and the loan is home',
    );
    expect(reportFor(controller, home).keptMinor, 13000000);
  });

  test('money held for somebody is on neither screen, either way', () {
    final (:controller, :ledger) = monthWithEverything();
    final home = homeFigures(controller);
    final report = reportFor(controller, home);

    // 40,000 arrived and is in the account, and it is not theirs. It is
    // dropped rather than netted: netting would say it arrived and left, and
    // it never arrived as the owner's at all.
    expect(
      home.received,
      20000000,
      reason: 'not 240,000: the 40,000 never arrived as theirs',
    );
    expect(report.receivedMinor, 20000000);
  });

  test('the shared rules and Home reach the same place independently', () {
    // Home works every figure out from the shared rules over the one window
    // it names. It used to take earnings from the ledger's own dashboard
    // instead, which resolves a window of its own -- safe only while the two
    // windows were the same window, which is exactly the assumption that
    // broke.
    final (:controller, :ledger) = monthWithEverything();

    Set<String> heldDebtIds() => {
      for (final debt in controller.debts)
        if (debt.isHeld) debt.id,
    };

    final home = homeFigures(controller);
    final shared = periodFigures(
      transactions: controller.transactions,
      from: home.from,
      to: home.to,
      heldDebtIds: heldDebtIds(),
    );

    expect(shared.received, home.received);
    expect(shared.spent, home.spent);
    expect(shared.kept, home.kept);

    // The fixture dates everything to this month, so the window above is the
    // one the dashboard would resolve anyway and the two agreeing proves
    // little on its own. Ask about a month the fixture put nothing in, which
    // no cached "this month" can answer, and require the same agreement --
    // and that Home reports the empty month rather than this one.
    final month = home.from;
    final before = homeFigures(
      controller,
      now: DateTime(month.year, month.month - 1, 15, 12),
    );
    final sharedBefore = periodFigures(
      transactions: controller.transactions,
      from: before.from,
      to: before.to,
      heldDebtIds: heldDebtIds(),
    );

    expect(before.received, sharedBefore.received);
    expect(before.spent, sharedBefore.spent);
    expect(before.kept, sharedBefore.kept);
    expect(
      before.received,
      0,
      reason: 'nothing arrived in a month this fixture never wrote to',
    );
  });
}
