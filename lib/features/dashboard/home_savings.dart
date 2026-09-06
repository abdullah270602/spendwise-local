import '../shell/spendwise_view_model.dart';

/// How saving appears on Home, if at all.
///
/// This used to be one list of seven, and it conflated two unrelated
/// decisions. Five of them changed the figure Home reports; two of them
/// changed nothing about it and simply added a line underneath. Reading a
/// single list you had to work out which was which from the wording, and
/// picking one meant giving up the other for no reason.
///
/// So it is two choices now. [HomeSavingsStyle] decides whether saving comes
/// out of the number and whether the shape draws it. [HomeSavingsExtra] adds
/// a line beneath, and composes freely with any of them.
enum HomeSavingsStyle {
  /// Home stays a picture of money you can spend, with saving left out of it.
  off(
    id: 'off',
    title: "Don't count savings",
    detail: 'Saving changes nothing about the figure.',
  ),

  /// Saving is taken out of the headline and out of the picture: two
  /// branches, available against gone. Choosing not to see savings should
  /// mean not seeing them.
  available(
    id: 'available',
    title: 'Only what I can spend',
    detail: 'Saving comes out of the figure and is not itemised.',
  ),

  /// Received splits three ways at once.
  siblings(
    id: 'siblings',
    title: 'Saving gets its own branch',
    detail: 'Beside kept and gone. "Still yours" then means what is liquid.',
  ),

  /// Kept keeps its meaning; the saved part is bracketed inside it.
  divided(
    id: 'divided',
    title: 'Marked inside what is still yours',
    detail: 'Saved money is yours, so it divides that figure, not rivals it.',
  ),

  /// The same division, drawn as a seam within the kept ribbon.
  seam(
    id: 'seam',
    title: 'A seam in the shape',
    detail: 'The same, drawn inside the ribbon instead of beneath it.',
  );

  const HomeSavingsStyle({
    required this.id,
    required this.title,
    required this.detail,
  });

  final String id;
  final String title;
  final String detail;

  /// Whether the shape itself has to draw the saved portion.
  bool get changesTheShape =>
      this == siblings || this == divided || this == seam;

  /// Whether saving is counted out of the headline figure, which is what
  /// turns "still yours" into "available".
  bool get setsSavingAside => this == available || this == siblings;

  /// Whether the saved amount is named beside the headline. Taking it out
  /// without naming it is a deliberate option, not an oversight.
  bool get namesTheSaving => this == siblings;

  /// The default is [available]: Home's one job is to say what is left, and
  /// money deliberately put away is not left.
  ///
  /// `balance` and `moved` were values here before the split. They never
  /// touched the figure, so anything stored under those names resolves to
  /// [off] and is picked up by [HomeSavingsExtra] instead.
  static HomeSavingsStyle fromId(String? id) {
    for (final style in values) {
      if (style.id == id) return style;
    }
    if (id == 'balance' || id == 'moved') return off;
    return available;
  }
}

/// A line beneath the shape, reporting something the figure does not.
///
/// These are additions, not alternatives. Neither changes the headline or the
/// ribbon, which is exactly why they were the wrong thing to have been
/// choosing *between* alongside the five that do.
enum HomeSavingsExtra {
  none(id: 'none', title: 'Nothing', detail: 'No extra line.'),

  /// The total sitting in savings accounts. This is what the original on/off
  /// switch drew.
  balance(
    id: 'balance',
    title: 'What I have set aside',
    detail: 'The total in your savings accounts. A balance, not a movement.',
  ),

  /// The same band, reporting movement over the window instead of a balance.
  moved(
    id: 'moved',
    title: 'What I put away',
    detail: 'Money moved into savings over the time Home covers.',
  );

  const HomeSavingsExtra({
    required this.id,
    required this.title,
    required this.detail,
  });

  final String id;
  final String title;
  final String detail;

  /// Resolves the stored choice, inheriting from the single setting these
  /// were split out of when this one has never been set.
  static HomeSavingsExtra resolve(
    String? extraId,
    String? styleId, {
    required bool legacyOn,
  }) {
    for (final extra in values) {
      if (extra.id == extraId) return extra;
    }
    if (extraId != null) return none;
    if (styleId == 'balance') return balance;
    if (styleId == 'moved') return moved;
    // Before any of this was a choice it was a switch, and the switch drew a
    // balance. Anyone who had it on keeps seeing what they already had.
    if (styleId == null && legacyOn) return balance;
    return none;
  }
}

/// What was moved into savings over [from]..[to].
///
/// Net, because moving money out of a savings account during the period is the
/// opposite of putting it away, and reporting only the inflow would let a
/// person who emptied their savings still be told they saved.
///
/// Clamped at zero for display: the shape divides money that *arrived*, and a
/// negative branch has no meaning there. The band styles report the signed
/// figure, which is why they take it from here rather than re-deriving it.
int savedInWindow({
  required Iterable<TransactionViewData> transactions,
  required Set<String> savingsAccountIds,
  required DateTime from,
  required DateTime to,
}) {
  if (savingsAccountIds.isEmpty) return 0;
  var net = 0;
  for (final item in transactions) {
    final local = item.occurredAt.toLocal();
    if (local.isBefore(from) || !local.isBefore(to)) continue;
    final amount = item.amount.minorUnits.abs();
    switch (item.kind) {
      case TransactionKind.transfer:
        // A transfer's `accountId` is the leg it left from; `toAccountId` is
        // where it landed. A transfer between two savings accounts therefore
        // cancels itself out, which is right -- nothing new was put away.
        if (savingsAccountIds.contains(item.toAccountId)) net += amount;
        if (savingsAccountIds.contains(item.accountId)) net -= amount;
      case TransactionKind.income:
        if (savingsAccountIds.contains(item.accountId)) net += amount;
      case TransactionKind.expense:
        if (savingsAccountIds.contains(item.accountId)) net -= amount;
    }
  }
  return net;
}

/// Money that left the spendable accounts over [from]..[to] for reasons that
/// are not spending: lending it out, and handing back something borrowed.
///
/// [heldDebtIds] names debts that were never the user's money. Both legs of
/// those are skipped here and in [debtInflowInWindow], because money that only
/// passed through never belonged to the picture Home draws. Counting it would
/// show a windfall in the period it arrived and a loss in the period it left,
/// and neither ever happened to the user.
///
/// Home's headline used to be `received - spent`, which quietly assumes
/// spending is the only way money leaves. It is not, and when it is not the
/// figure drifts from reality by exactly the amount ignored — far enough that
/// Home and Accounts cannot be reconciled by hand.
///
/// Both directions are expenses carrying a debt: lending money out, and
/// paying money back. Both leave the account, and neither is spending.
int debtOutflowInWindow({
  required Iterable<TransactionViewData> transactions,
  required DateTime from,
  required DateTime to,
  Set<String> heldDebtIds = const {},
}) {
  var total = 0;
  for (final item in transactions) {
    if (item.debtId == null) continue;
    if (heldDebtIds.contains(item.debtId)) continue;
    if (item.kind != TransactionKind.expense) continue;
    final local = item.occurredAt.toLocal();
    if (local.isBefore(from) || !local.isBefore(to)) continue;
    total += item.amount.minorUnits.abs();
  }
  return total;
}

/// Money that arrived in the spendable accounts over [from]..[to] for reasons
/// that are not income: a loan being repaid to you, and money handed to you to
/// pass on.
///
/// The mirror of [debtOutflowInWindow], and the half that was missing. Home
/// excludes debt-linked movement from income so a repayment is not mistaken
/// for earnings -- correct, but it was then counted nowhere at all, while the
/// matching outflow *was* counted. Money leaving moved the headline and the
/// same money arriving did not, so the two sides no longer met: a repayment
/// left the headline flat while the balance rose, and money passed straight
/// through showed as a loss the accounts never took.
///
/// It belongs in "what came in" rather than beside it. The figure it feeds is
/// the change in the spendable balance, and this money genuinely arrived; what
/// it is not is *earnings*, which is a different question that income answers.
int debtInflowInWindow({
  required Iterable<TransactionViewData> transactions,
  required DateTime from,
  required DateTime to,
  Set<String> heldDebtIds = const {},
}) {
  var total = 0;
  for (final item in transactions) {
    if (item.debtId == null) continue;
    if (heldDebtIds.contains(item.debtId)) continue;
    if (item.kind != TransactionKind.income) continue;
    final local = item.occurredAt.toLocal();
    if (local.isBefore(from) || !local.isBefore(to)) continue;
    total += item.amount.minorUnits.abs();
  }
  return total;
}

/// Everything Home needs to draw itself.
///
/// One function, so the settings previews cannot drift from Home. They used
/// to each assemble the figures separately -- Home from the dashboard, the
/// savings preview from the same numbers minus a term, the period screen
/// straight from the ledger -- and three implementations of one sum is three
/// chances for a picture to disagree with the thing it is a picture of.
///
/// Earnings and spending come from the controller, which is the authority on
/// what counts as either. Re-deriving them here would be a second copy of
/// those rules, free to drift from the first.
class HomeFigures {
  const HomeFigures({
    required this.received,
    required this.spent,
    required this.kept,
    required this.saved,
    required this.held,
    required this.from,
    required this.to,
  });

  /// Everything that arrived: earnings, plus debt money that genuinely landed
  /// in the account without being earnings.
  final int received;
  final int spent;

  /// What is left once everything that left has left.
  final int kept;

  /// Net movement into savings accounts over the window.
  final int saved;

  /// The balance held in savings accounts right now. A stock, not a flow,
  /// which is why it is reported separately and never enters the shape.
  final int held;

  final DateTime from;
  final DateTime to;
}

HomeFigures homeFigures(SpendWiseViewModel viewModel, {DateTime? now}) {
  final (from, to) = viewModel.uiHomePeriod.resolve(now ?? DateTime.now());
  final heldDebtIds = {
    for (final debt in viewModel.uiDebts)
      if (debt.isHeld) debt.id,
  };

  final dashboard = viewModel.dashboard;
  final received =
      dashboard.incomeThisMonth.minorUnits +
      debtInflowInWindow(
        transactions: viewModel.transactions,
        from: from,
        to: to,
        heldDebtIds: heldDebtIds,
      );
  final spent = dashboard.spendingThisMonth.minorUnits;
  final outflow = debtOutflowInWindow(
    transactions: viewModel.transactions,
    from: from,
    to: to,
    heldDebtIds: heldDebtIds,
  );

  return HomeFigures(
    received: received,
    spent: spent,
    kept: received - spent - outflow,
    saved: savedInWindow(
      transactions: viewModel.transactions,
      savingsAccountIds: {
        for (final account in viewModel.accounts)
          if (!account.isIncluded) account.id,
      },
      from: from,
      to: to,
    ),
    held: viewModel.accounts
        .where((account) => !account.isIncluded)
        .fold<int>(0, (sum, account) => sum + account.balance.minorUnits),
    from: from,
    to: to,
  );
}
