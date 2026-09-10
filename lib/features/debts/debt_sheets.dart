import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../shell/spendwise_view_model.dart';
import 'debt_matching.dart';

/// The colour a debt kind is drawn in, wherever one is drawn.
///
/// Public rather than a private helper of this file: the transaction the
/// debt hangs off of is shown on a different screen, and that screen used to
/// guess at the colour with its own two-way lent/spend ternary -- which had
/// no way to spell "held", so held money got painted as spending. One
/// function, used everywhere a debt's tone is needed, is the only way that
/// stays impossible to get wrong twice.
Color toneForDebtKind(DebtKind kind) => switch (kind) {
  DebtKind.lent => SpendWiseColors.keep,
  DebtKind.borrowed => SpendWiseColors.spend,
  DebtKind.holding => SpendWiseColors.dim,
};

/// Marking a movement as somebody else's business.
///
/// A bank alert cannot tell lending from spending — "PKR 20,000 sent" reads
/// the same either way. Only the person knows, so this is the one thing the
/// app asks them to say out loud, and it asks for two facts: whose, and who.
Future<bool> markAsLoan(
  BuildContext context, {
  required SpendWiseViewModel viewModel,
  required TransactionViewData transaction,
  // Which of the three stories the sheet opens onto. Left to guess from the
  // transaction's direction where the caller has no better idea -- but the
  // caller now offers all three up front, so most calls pass the one the
  // person actually tapped rather than leaning on this guess.
  DebtKind? initialKind,
}) async {
  final outgoing = transaction.kind != TransactionKind.income;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => _MarkLoanSheet(
      viewModel: viewModel,
      transaction: transaction,
      kind: initialKind ?? (outgoing ? DebtKind.lent : DebtKind.borrowed),
    ),
  );
  return result ?? false;
}

class _MarkLoanSheet extends StatefulWidget {
  const _MarkLoanSheet({
    required this.viewModel,
    required this.transaction,
    required this.kind,
  });

  final SpendWiseViewModel viewModel;
  final TransactionViewData transaction;
  final DebtKind kind;

  @override
  State<_MarkLoanSheet> createState() => _MarkLoanSheetState();
}

class _MarkLoanSheetState extends State<_MarkLoanSheet> {
  late DebtKind kind = widget.kind;
  final who = TextEditingController();
  final note = TextEditingController();
  bool saving = false;

  @override
  void initState() {
    super.initState();
    // The counterparty the parser already found is nearly always the person.
    final guess = widget.transaction.title.trim();
    if (guess.isNotEmpty && !guess.toLowerCase().contains('payment')) {
      who.text = guess;
    }
  }

  @override
  void dispose() {
    who.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      SpendWiseTheme.gutter,
      0,
      SpendWiseTheme.gutter,
      MediaQuery.viewInsetsOf(context).bottom +
          MediaQuery.viewPaddingOf(context).bottom +
          24,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This was not spending', style: SpendWiseType.title),
          const SizedBox(height: 6),
          Text(
            kind == DebtKind.holding
                ? 'It is not yours, so it stays out of what you can spend.'
                : 'It stops counting as '
                      '${kind == DebtKind.lent ? 'spending' : 'income'}, '
                      'because it is coming back.',
            style: SpendWiseType.body.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 22),
          const Eyebrow('Whose money was it'),
          const SizedBox(height: 8),
          // Three stacked rather than side by side: a third option does not
          // fit across a 360dp phone without the labels turning to stumps,
          // and the difference between them lives in the detail line.
          for (final option in DebtKind.values)
            _KindRow(
              kind: option,
              selected: option == kind,
              onTap: () => setState(() => kind = option),
            ),
          const SizedBox(height: 14),
          Eyebrow(kind.partyLabel),
          const SizedBox(height: 8),
          TextField(
            controller: who,
            autofocus: who.text.isEmpty,
            textCapitalization: TextCapitalization.words,
            style: SpendWiseType.row,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'A name you will recognise later',
            ),
          ),
          const SizedBox(height: 16),
          const Eyebrow('Note, if it helps'),
          const SizedBox(height: 8),
          TextField(
            controller: note,
            style: SpendWiseType.row,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'What it was for, when it is due back…',
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.only(top: 13),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: SpendWiseColors.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.transaction.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SpendWiseType.body.copyWith(fontSize: 13),
                  ),
                ),
                Text(
                  formatAmount(widget.transaction.amount),
                  style: SpendWiseType.rowStrong.copyWith(
                    color: toneForDebtKind(kind),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PrimaryAction(label: kind.openLabel, busy: saving, onPressed: _save),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    final name = who.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A loan needs a name to be worth much.')),
      );
      return;
    }
    setState(() => saving = true);
    try {
      await widget.viewModel.uiOpenDebt(
        transactionId: widget.transaction.id,
        kind: kind,
        counterparty: name,
        note: note.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not record that: $error')));
    }
  }
}

class _KindRow extends StatelessWidget {
  const _KindRow({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final DebtKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = toneForDebtKind(kind);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? tone : SpendWiseColors.edge,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(top: 3, right: 12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? tone : SpendWiseColors.edge,
                    width: 1.5,
                  ),
                  color: selected ? tone : Colors.transparent,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kind.title,
                      style: SpendWiseType.rowStrong.copyWith(
                        fontSize: 14,
                        color: selected ? tone : SpendWiseColors.fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      kind.detail,
                      style: SpendWiseType.body.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One loan, with what is left on it and the two ways it can end: money comes
/// back, or the user decides it never will.
Future<void> openDebt(
  BuildContext context, {
  required SpendWiseViewModel viewModel,
  required DebtViewData debt,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (sheetContext) => _DebtSheet(viewModel: viewModel, debt: debt),
);

class _DebtSheet extends StatefulWidget {
  const _DebtSheet({required this.viewModel, required this.debt});

  final SpendWiseViewModel viewModel;
  final DebtViewData debt;

  @override
  State<_DebtSheet> createState() => _DebtSheetState();
}

class _DebtSheetState extends State<_DebtSheet> {
  final amount = TextEditingController();
  bool working = false;

  DebtViewData get debt => widget.viewModel.uiDebts.firstWhere(
    (item) => item.id == widget.debt.id,
    orElse: () => widget.debt,
  );

  @override
  void initState() {
    super.initState();
    amount.text = (debt.outstanding.minorUnits / 100).toStringAsFixed(
      debt.outstanding.minorUnits % 100 == 0 ? 0 : 2,
    );
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = debt;
    final tone = toneForDebtKind(current.kind);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        SpendWiseTheme.gutter,
        0,
        SpendWiseTheme.gutter,
        MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.viewPaddingOf(context).bottom +
            24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow(switch (current.kind) {
              DebtKind.lent => 'Owed to you by',
              DebtKind.borrowed => 'You owe',
              DebtKind.holding => 'Holding for',
            }),
            const SizedBox(height: 5),
            Text(current.counterparty, style: SpendWiseType.title),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow(current.isSettled ? 'Settled' : 'Still out'),
                      const SizedBox(height: 3),
                      Text(
                        formatAmount(
                          current.isSettled
                              ? current.principal
                              : current.outstanding,
                          cents: false,
                        ),
                        style: SpendWiseType.figure.copyWith(
                          fontSize: 30,
                          color: current.isSettled ? SpendWiseColors.dim : tone,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'of ${formatAmount(current.principal, cents: false)}',
                      style: SpendWiseType.body.copyWith(fontSize: 12.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'since ${DateFormat('d MMM yyyy').format(current.openedAt)}',
                      style: SpendWiseType.metaTight,
                    ),
                  ],
                ),
              ],
            ),
            if (current.isPartlyPaid) ...[
              const SizedBox(height: 12),
              SegmentBar(
                weights: [
                  current.settled.minorUnits / current.principal.minorUnits,
                  current.outstanding.minorUnits / current.principal.minorUnits,
                ],
                colors: [tone, SpendWiseColors.line],
                height: 6,
                gap: 2,
              ),
              const SizedBox(height: 6),
              Text(
                '${formatAmount(current.settled, cents: false)} '
                '${current.lent ? 'back so far' : 'repaid so far'}',
                style: SpendWiseType.body.copyWith(fontSize: 12.5),
              ),
            ],
            if (current.note case final text? when text.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.only(left: 11),
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: SpendWiseColors.edge, width: 2),
                  ),
                ),
                child: Text(
                  text,
                  style: SpendWiseType.body.copyWith(fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 24),
            _MatchingEntries(
              viewModel: widget.viewModel,
              debt: current,
              onRecorded: () {
                if (!mounted) return;
                setState(() {
                  amount.text = (debt.outstanding.minorUnits / 100)
                      .toStringAsFixed(0);
                });
              },
            ),
            if (!current.isSettled) ...[
              Eyebrow(
                current.lent
                    ? 'Record money coming back in cash'
                    : 'Record a repayment in cash',
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: SpendWiseType.row,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixText: '${current.principal.currency} ',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: working ? null : _settle,
                    child: const Text('Record'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'For cash in hand. If the repayment arrived as a bank '
                'alert, open that entry and record it against this loan '
                'instead — that is what stops it counting twice.',
                style: SpendWiseType.body.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 18),
            ],
            const Eyebrow('Whose money was it'),
            const SizedBox(height: 8),
            // Re-filing, not re-entering. Anything recorded before the third
            // story existed is sitting under the nearest wrong answer, and
            // "your history is mis-filed but you cannot fix it" would be a
            // worse answer than never having offered the story.
            for (final option in DebtKind.values)
              _KindRow(
                kind: option,
                selected: option == current.kind,
                onTap: working || option == current.kind
                    ? () {}
                    : () => _refile(option),
              ),
            const SizedBox(height: 14),
            // It used to say "Call it settled", which reads as "mark this
            // repaid" and does nothing of the sort: it records no money
            // coming back and touches no entry, so a repayment that arrived
            // in an account goes on being counted as income while the loan
            // claims to be done. Naming it for what it does is the whole
            // fix -- somebody who wants the other thing wants the entry
            // above, or the amount box.
            if (!current.isSettled) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: working ? null : _close,
                  child: const Text('Write it off'),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Stops tracking it without recording any money coming back. '
                'What went out stays out.',
                style: SpendWiseType.body.copyWith(fontSize: 12),
              ),
            ] else
              Text(
                current.outstanding.minorUnits > 0
                    ? 'Written off${current.closedAt == null ? '' : ' on ${DateFormat('d MMM yyyy').format(current.closedAt!)}'}, with ${formatAmount(current.outstanding, cents: false)} never recorded as coming back.'
                    : 'Settled${current.closedAt == null ? '' : ' on ${DateFormat('d MMM yyyy').format(current.closedAt!)}'}.',
                style: SpendWiseType.body.copyWith(fontSize: 13),
              ),
            const SizedBox(height: 16),
            // Deliberately smaller and lower than "Write it off": that one
            // is a correction you can walk back by re-filing or recording a
            // repayment, this one throws the counterparty, note and
            // repayment history away and hands the amount back to ordinary
            // income or spending. Equal weight would have told the eye they
            // were equally safe to tap.
            Center(
              child: TextButton(
                onPressed: working ? null : _forget,
                style: TextButton.styleFrom(
                  foregroundColor: SpendWiseColors.spend,
                ),
                child: const Text('Not a loan'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refile(DebtKind kind) async {
    setState(() => working = true);
    try {
      await widget.viewModel.uiChangeDebtKind(
        debtId: widget.debt.id,
        kind: kind,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => working = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not re-file that: $error')));
    }
  }

  Future<void> _settle() async {
    final value = double.tryParse(amount.text.trim().replaceAll(',', ''));
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an amount to record.')),
      );
      return;
    }
    await _run(
      () => widget.viewModel.uiSettleDebt(
        debtId: debt.id,
        amount: MoneyViewData(
          (value * 100).round(),
          currency: debt.principal.currency,
        ),
      ),
    );
  }

  Future<void> _close() => _run(() => widget.viewModel.uiCloseDebt(debt.id));

  Future<void> _forget() async {
    // One tap used to be enough to discard a counterparty, a note and a
    // whole repayment history, and to move a figure on Home, with nothing to
    // undo it. A question first is the cheapest possible defence against a
    // slip of the thumb landing beside "Write it off".
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('This was never a loan?'),
        content: Text(
          'The record of ${debt.counterparty} and any repayments logged '
          'against it are dropped, and the amount counts as ordinary '
          'spending or income again, whichever way it moved. This cannot '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: SpendWiseColors.spend,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Not a loan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => widget.viewModel.uiRemoveDebt(debt.id), closeAfter: true);
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool closeAfter = false,
  }) async {
    setState(() => working = true);
    try {
      await action();
      if (!mounted) return;
      if (closeAfter) {
        Navigator.pop(context);
      } else {
        setState(() {
          working = false;
          amount.text = (debt.outstanding.minorUnits / 100).toStringAsFixed(0);
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => working = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not do that: $error')));
    }
  }
}

/// Attaching an entry the bank already reported to a loan that is still open.
///
/// The missing half of settling. Recording an amount on the loan alone is
/// right for cash that never touched an account, but when the repayment
/// arrived as an alert there are two records of the same money: the loan says
/// it came back, and the ledger still counts it as income. Stamping the entry
/// with the loan is what makes it stop counting -- the whole exclusion turns
/// on debtId, nothing else.
Future<bool> settleFromEntry(
  BuildContext context, {
  required SpendWiseViewModel viewModel,
  required TransactionViewData transaction,
  DebtViewData? debt,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => _SettleFromEntrySheet(
      viewModel: viewModel,
      transaction: transaction,
      preselected: debt,
    ),
  );
  return result ?? false;
}

class _SettleFromEntrySheet extends StatefulWidget {
  const _SettleFromEntrySheet({
    required this.viewModel,
    required this.transaction,
    this.preselected,
  });

  final SpendWiseViewModel viewModel;
  final TransactionViewData transaction;
  final DebtViewData? preselected;

  @override
  State<_SettleFromEntrySheet> createState() => _SettleFromEntrySheetState();
}

class _SettleFromEntrySheetState extends State<_SettleFromEntrySheet> {
  String? chosen;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    chosen = widget.preselected?.id;
  }

  /// The reasons the matcher found, so a suggested loan can say why it is
  /// near the top rather than appearing there by magic.
  Map<String, String> get _reasons => {
    for (final match in debtMatchesFor(
      transaction: widget.transaction,
      debts: widget.viewModel.uiDebts,
      limit: 99,
    ))
      match.debt.id: match.reason,
  };

  @override
  Widget build(BuildContext context) {
    final incoming = widget.transaction.kind == TransactionKind.income;
    final amount = widget.transaction.amount.minorUnits.abs();
    final reasons = _reasons;
    final loans =
        debtsOpenTo(
            transaction: widget.transaction,
            debts: widget.viewModel.uiDebts,
          )
          // Suggested loans first: the matcher already decided which ones look
          // like this entry, and burying them under an older loan would waste
          // the one thing this sheet knows.
          ..sort((a, b) {
            final suggested =
                (reasons.containsKey(b.id) ? 1 : 0) -
                (reasons.containsKey(a.id) ? 1 : 0);
            if (suggested != 0) return suggested;
            return b.openedAt.compareTo(a.openedAt);
          });
    final selected = loans.where((item) => item.id == chosen).firstOrNull;
    // Not asked of a loan settled by hand: nothing is out on one of those by
    // definition, and "more than is still out" would fire on every entry
    // while the sheet is busy explaining the opposite.
    final over = selected == null || selected.outstanding.minorUnits <= 0
        ? 0
        : amount - selected.outstanding.minorUnits;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        SpendWiseTheme.gutter,
        0,
        SpendWiseTheme.gutter,
        MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.viewPaddingOf(context).bottom +
            24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              incoming ? 'Money coming back' : 'Money going back',
              style: SpendWiseType.title,
            ),
            const SizedBox(height: 6),
            Text(
              'It stops counting as ${incoming ? 'income' : 'spending'} and '
              'comes off what is still out.',
              style: SpendWiseType.body.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 22),
            if (loans.isEmpty)
              Text(
                incoming
                    ? 'No open loan is waiting on money coming in.'
                    : 'Nothing open is waiting on money going out.',
                style: SpendWiseType.body.copyWith(fontSize: 13),
              )
            else ...[
              const Eyebrow('Which loan'),
              const SizedBox(height: 8),
              for (final loan in loans)
                _LoanChoice(
                  debt: loan,
                  reason: reasons[loan.id],
                  selected: loan.id == chosen,
                  onTap: () => setState(() => chosen = loan.id),
                ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.only(top: 13),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: SpendWiseColors.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.transaction.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SpendWiseType.body.copyWith(fontSize: 13),
                    ),
                  ),
                  Text(
                    formatAmount(widget.transaction.amount),
                    style: SpendWiseType.rowStrong.copyWith(
                      color: selected == null
                          ? SpendWiseColors.fg
                          : toneForDebtKind(selected.kind),
                    ),
                  ),
                ],
              ),
            ),
            if (selected != null && selected.outstanding.minorUnits <= 0) ...[
              const SizedBox(height: 12),
              Text(
                'This replaces the '
                '${formatAmount(selected.settledByHand, cents: false)} you '
                'recorded on this loan by hand.',
                style: SpendWiseType.body.copyWith(fontSize: 12.5),
              ),
            ],
            // The entry goes onto the loan whole or not at all. Recording a
            // smaller figure would still stamp the whole entry, so a payment
            // that was half repayment and half a gift would take the gift out
            // of the month as well, silently.
            if (over > 0) ...[
              const SizedBox(height: 12),
              Text(
                'That is '
                '${formatAmount(MoneyViewData(over, currency: widget.transaction.amount.currency), cents: false)} '
                'more than is still out. All of it stops counting as '
                '${incoming ? 'income' : 'spending'}, and the loan closes.',
                style: SpendWiseType.body.copyWith(
                  fontSize: 12.5,
                  color: SpendWiseColors.warning,
                ),
              ),
            ],
            const SizedBox(height: 16),
            PrimaryAction(
              label: 'Record it',
              busy: saving,
              onPressed: selected == null ? null : _record,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _record() async {
    final debtId = chosen;
    if (debtId == null) return;
    setState(() => saving = true);
    try {
      final loan = widget.viewModel.uiDebts
          .where((item) => item.id == debtId)
          .firstOrNull;
      await widget.viewModel.uiSettleDebt(
        debtId: debtId,
        amount: widget.transaction.amount,
        transactionId: widget.transaction.id,
        // Nothing left out means the loan was settled by hand. Without this
        // the loan would count the same money twice: once as the amount
        // somebody typed, and once as the entry that actually carried it.
        replacingByHand: (loan?.outstanding.minorUnits ?? 1) <= 0,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not record that: $error')));
    }
  }
}

class _LoanChoice extends StatelessWidget {
  const _LoanChoice({
    required this.debt,
    required this.selected,
    required this.onTap,
    this.reason,
  });

  final DebtViewData debt;
  final bool selected;
  final VoidCallback onTap;

  /// Why the matcher put this one forward, if it did.
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final tone = toneForDebtKind(debt.kind);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? tone : SpendWiseColors.edge,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(top: 3, right: 12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? tone : SpendWiseColors.edge,
                    width: 1.5,
                  ),
                  color: selected ? tone : Colors.transparent,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            debt.counterparty,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SpendWiseType.rowStrong.copyWith(
                              fontSize: 14,
                              color: selected ? tone : SpendWiseColors.fg,
                            ),
                          ),
                        ),
                        Text(
                          formatAmount(debt.outstanding, cents: false),
                          style: SpendWiseType.body.copyWith(fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reason == null
                          ? '${debt.kind.categoryName} - opened '
                                '${DateFormat('d MMM').format(debt.openedAt)}'
                          : 'Suggested: $reason',
                      style: SpendWiseType.body.copyWith(
                        fontSize: 12,
                        color: reason == null
                            ? SpendWiseColors.dim
                            : SpendWiseColors.keep,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Entries the ledger already holds that look like this loan coming home.
///
/// Drawn above the amount box on purpose. That box is where somebody would
/// otherwise type the figure by hand, which settles the loan and leaves the
/// same money still counted as income — the double count this whole path
/// exists to stop. Offering the entry first makes the right answer the
/// nearer one.
class _MatchingEntries extends StatelessWidget {
  const _MatchingEntries({
    required this.viewModel,
    required this.debt,
    required this.onRecorded,
  });

  final SpendWiseViewModel viewModel;
  final DebtViewData debt;

  /// The sheet around this one is not listening to the ledger, so recording
  /// an entry has to say so out loud or the loan goes on showing the money
  /// as still out.
  final VoidCallback onRecorded;

  @override
  Widget build(BuildContext context) {
    final entries = entriesMatching(
      debt: debt,
      transactions: viewModel.transactions,
    );
    if (entries.isEmpty) return const SizedBox.shrink();
    final tone = toneForDebtKind(debt.kind);
    // A loan with nothing left out was settled by typing the figure in. The
    // money is recorded twice over in that state -- the loan says it came
    // home, and the entry that brought it home is still in the month as
    // income -- and this is the only way back from it.
    final byHand = debt.outstanding.minorUnits <= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(
          byHand
              ? 'Was this the money?'
              : entries.length == 1
              ? 'This entry could be it'
              : 'These entries could be it',
        ),
        const SizedBox(height: 8),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () async {
                final recorded = await settleFromEntry(
                  context,
                  viewModel: viewModel,
                  transaction: entry,
                  debt: debt,
                );
                if (recorded) onRecorded();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: tone, width: 2),
                    top: const BorderSide(color: SpendWiseColors.line),
                    right: const BorderSide(color: SpendWiseColors.line),
                    bottom: const BorderSide(color: SpendWiseColors.line),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SpendWiseType.row,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('d MMM').format(entry.occurredAt),
                            style: SpendWiseType.metaTight,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formatAmount(entry.amount),
                      style: SpendWiseType.rowStrong.copyWith(color: tone),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 6),
        Text(
          byHand
              ? 'You recorded this loan as an amount, so the entry that '
                    'brought the money back is still counted as '
                    '${debt.lent ? 'income' : 'spending'}. Recording it here '
                    'replaces the amount you typed in and takes it out.'
              : 'Recording one of these stops it counting as '
                    '${debt.lent ? 'income' : 'spending'} as well as closing '
                    'the loan.',
          style: SpendWiseType.body.copyWith(fontSize: 12),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}
