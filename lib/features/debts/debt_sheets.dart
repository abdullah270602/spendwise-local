import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../shell/spendwise_view_model.dart';

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
            if (!current.isSettled) ...[
              Eyebrow(
                current.lent
                    ? 'Record money coming back'
                    : 'Record a repayment',
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
                'If the repayment already arrived as a bank alert, open that '
                'entry instead and mark it against this loan — the money only '
                'counts once either way.',
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
            if (!current.isSettled)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: working ? null : _close,
                  child: const Text('Call it settled'),
                ),
              )
            else
              Text(
                'Settled${current.closedAt == null ? '' : ' on ${DateFormat('d MMM yyyy').format(current.closedAt!)}'}.',
                style: SpendWiseType.body.copyWith(fontSize: 13),
              ),
            const SizedBox(height: 16),
            // Deliberately smaller and lower than "Call it settled": that one
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
    // slip of the thumb landing beside "Call it settled".
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
