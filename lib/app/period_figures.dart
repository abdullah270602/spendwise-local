import 'package:flutter/foundation.dart';

import '../features/shell/spendwise_view_model.dart';

/// What one window of time did to the owner's money, worked out once.
///
/// Home, the PDF report and Insights each used to answer this separately, and
/// they drifted -- not in some corner, but in the two figures the app leads
/// with. Home printed "Still yours" having subtracted a loan made that month;
/// the report printed the same two words having subtracted nothing, and was
/// 30,000 out on a 30,000 loan. All three used a phrase like "what came in"
/// for three different sums. A person who read two screens could not tell
/// which was lying, and neither could anybody reading the code, because each
/// version was locally reasonable.
///
/// So this is the only place these are worked out. A screen may choose not to
/// show a figure, but it may not compute one of its own with the same name.
@immutable
class PeriodFigures {
  const PeriodFigures({
    required this.received,
    required this.spent,
    required this.loanIn,
    required this.loanOut,
    required this.from,
    required this.to,
  });

  /// Money that arrived and is the owner's, over this window.
  ///
  /// Earnings, plus the net of any loan money that came back. Net, because a
  /// loan that goes out and returns inside the same window is one note
  /// leaving and arriving, not income -- counting both legs made a month read
  /// as twice its size and made the share drawn from it meaningless.
  final int received;

  /// Ordinary spending. Never includes a loan being made or repaid: that
  /// money is owed in one direction or the other, and calling it spending
  /// says it is gone.
  final int spent;

  /// Money that came back on loans over this window, net of any that went
  /// out. At most one of [loanIn] and [loanOut] is ever above zero: a loan
  /// that leaves and returns inside one window is a note moving, not money
  /// arriving, and counting both legs made a month read as twice its size.
  final int loanIn;

  /// Money that left on loans over this window, net of any that came back.
  ///
  /// Not spending, but not still in the owner's hands either, so it comes off
  /// what is kept without ever entering what was spent.
  final int loanOut;

  final DateTime from;
  final DateTime to;

  /// What is still the owner's at the end of it.
  ///
  /// The figure that has to agree with the balance, which is why it, and not
  /// [received], is the one nothing is allowed to redefine.
  int get kept => received - spent - loanOut;

  /// How much of what came in is still there, for a screen that draws a
  /// share. Zero when nothing came in, rather than a confident half.
  double get keptFraction =>
      received <= 0 ? 0 : (kept / received).clamp(0.0, 1.0);
}

/// Works out [PeriodFigures] for `[from, to)`.
///
/// [heldDebtIds] are loans of money that was never the owner's -- somebody
/// else's funds passing through. Both legs are dropped rather than netted:
/// netting would say the money arrived and left, and it was never theirs to
/// arrive.
///
/// Money put into savings is deliberately not here. `savedInWindow` already
/// owns that rule, including the awkward parts -- earnings paid straight into
/// a savings account, a transfer between two savings accounts cancelling
/// itself out -- and a second version of it living here would be the exact
/// duplication this file exists to end.
PeriodFigures periodFigures({
  required Iterable<TransactionViewData> transactions,
  required DateTime from,
  required DateTime to,
  Set<String> heldDebtIds = const {},
}) {
  var received = 0, spent = 0, loanIn = 0, loanRaw = 0;

  for (final item in transactions) {
    final at = item.occurredAt.toLocal();
    if (at.isBefore(from) || !at.isBefore(to)) continue;
    final amount = item.amount.minorUnits.abs();
    final debtId = item.debtId;

    if (debtId != null) {
      // Not the owner's on either leg, so neither leg is theirs to count.
      if (heldDebtIds.contains(debtId)) continue;
      switch (item.kind) {
        case TransactionKind.income:
          loanIn += amount;
        case TransactionKind.expense:
          loanRaw += amount;
        case TransactionKind.transfer:
          break;
      }
      continue;
    }

    switch (item.kind) {
      case TransactionKind.income:
        received += amount;
      case TransactionKind.expense:
        spent += amount;
      case TransactionKind.transfer:
        // A move between the owner's own accounts is neither earning nor
        // spending, whichever accounts it runs between.
        break;
    }
  }

  final net = loanIn - loanRaw;
  return PeriodFigures(
    received: received + (net > 0 ? net : 0),
    spent: spent,
    loanIn: net > 0 ? net : 0,
    loanOut: net < 0 ? -net : 0,
    from: from,
    to: to,
  );
}
