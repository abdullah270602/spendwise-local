import '../shell/spendwise_view_model.dart';

/// How saving appears on Home, if at all.
///
/// Home is a picture of flow over a period, and the two things a person might
/// want to see about saving are not the same question. What you *put away* is
/// a flow and belongs in the shape; what you *have set aside* is a balance and
/// does not — folding a balance into the shape would quietly change what the
/// figures beside it mean. So these are named after the question they answer,
/// never after what they draw.
enum HomeSavingsStyle {
  /// Home stays a picture of money you can spend.
  off(
    id: 'off',
    title: "Don't show savings",
    detail: 'Home stays a picture of money you can spend.',
  ),

  /// The total sitting in savings accounts, as a band under the shape. This is
  /// what the old on/off switch did.
  balance(
    id: 'balance',
    title: 'What I have set aside',
    detail:
        'The total in your savings accounts, as a band under the shape. A '
        'balance, not this period’s movement.',
  ),

  /// The same band, reporting movement instead of a balance.
  moved(
    id: 'moved',
    title: 'What I put away',
    detail:
        'Money moved into savings over the period Home covers, as a line '
        'under the shape.',
  ),

  /// Saving is taken out of the headline and out of the picture: two
  /// branches, available against gone. Choosing not to see savings should
  /// mean not seeing them.
  available(
    id: 'available',
    title: 'Only what I can spend',
    detail:
        'Saving comes out of the figure and is not itemised. Home answers '
        'one question: what is left to spend.',
  ),

  /// Received splits three ways at once.
  siblings(
    id: 'siblings',
    title: 'A third branch in the shape',
    detail:
        'Saving gets its own branch beside kept and gone. Note that “still '
        'yours” then means what is left liquid.',
  ),

  /// Kept keeps its meaning; the saved part is bracketed inside it.
  divided(
    id: 'divided',
    title: 'Marked inside “still yours”',
    detail:
        'Saved money is still yours, so it is shown as a division inside that '
        'figure rather than a rival to it.',
  ),

  /// The same division, drawn as a seam within the kept ribbon.
  seam(
    id: 'seam',
    title: 'A seam in the shape',
    detail: 'The same as above, drawn inside the ribbon instead of beneath it.',
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

  static HomeSavingsStyle fromId(String? id, {required bool legacyOn}) {
    for (final style in values) {
      if (style.id == id) return style;
    }
    // Before this was a choice it was a switch, and the switch drew a balance.
    // Anyone who had it on keeps seeing what they already had.
    return legacyOn ? balance : off;
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
}) {
  var total = 0;
  for (final item in transactions) {
    if (item.debtId == null) continue;
    if (item.kind != TransactionKind.expense) continue;
    final local = item.occurredAt.toLocal();
    if (local.isBefore(from) || !local.isBefore(to)) continue;
    total += item.amount.minorUnits.abs();
  }
  return total;
}
