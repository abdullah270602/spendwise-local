import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../shell/spendwise_view_model.dart';

/// Marking a movement as a loan.
///
/// A bank alert cannot tell lending from spending — "PKR 20,000 sent" reads
/// the same either way. Only the person knows, so this is the one thing the
/// app asks them to say out loud, and it asks for exactly one fact: who.
Future<bool> markAsLoan(
  BuildContext context, {
  required SpendWiseViewModel viewModel,
  required TransactionViewData transaction,
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
      lent: outgoing,
    ),
  );
  return result ?? false;
}

class _MarkLoanSheet extends StatefulWidget {
  const _MarkLoanSheet({
    required this.viewModel,
    required this.transaction,
    required this.lent,
  });

  final SpendWiseViewModel viewModel;
  final TransactionViewData transaction;
  final bool lent;

  @override
  State<_MarkLoanSheet> createState() => _MarkLoanSheetState();
}

class _MarkLoanSheetState extends State<_MarkLoanSheet> {
  late bool lent = widget.lent;
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
          Text('This was a loan', style: SpendWiseType.title),
          const SizedBox(height: 6),
          Text(
            'It stops counting as ${widget.lent ? 'spending' : 'income'}, '
            'because it is coming back.',
            style: SpendWiseType.body.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 22),
          const Eyebrow('Which way'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _Direction(
                  title: 'I lent it out',
                  detail: 'They owe you',
                  selected: lent,
                  tone: SpendWiseColors.keep,
                  onTap: () => setState(() => lent = true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Direction(
                  title: 'I borrowed it',
                  detail: 'You owe them',
                  selected: !lent,
                  tone: SpendWiseColors.spend,
                  onTap: () => setState(() => lent = false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Eyebrow(lent ? 'Who owes you' : 'Who you owe'),
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
                    color: lent ? SpendWiseColors.keep : SpendWiseColors.spend,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PrimaryAction(
            label: lent ? 'Record what they owe' : 'Record what you owe',
            busy: saving,
            onPressed: _save,
          ),
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
        lent: lent,
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

class _Direction extends StatelessWidget {
  const _Direction({
    required this.title,
    required this.detail,
    required this.selected,
    required this.tone,
    required this.onTap,
  });

  final String title;
  final String detail;
  final bool selected;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: selected ? tone : SpendWiseColors.edge,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: SpendWiseType.rowStrong.copyWith(
              fontSize: 14,
              color: selected ? tone : SpendWiseColors.fg,
            ),
          ),
          const SizedBox(height: 2),
          Text(detail, style: SpendWiseType.body.copyWith(fontSize: 12)),
        ],
      ),
    ),
  );
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
    final tone = current.lent ? SpendWiseColors.keep : SpendWiseColors.spend;
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
            Eyebrow(current.lent ? 'Owed to you by' : 'You owe'),
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
                          color: current.isSettled
                              ? SpendWiseColors.dim
                              : tone,
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
                current.lent ? 'Record money coming back' : 'Record a repayment',
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
            Row(
              children: [
                if (!current.isSettled)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: working ? null : _close,
                      child: const Text('Call it settled'),
                    ),
                  )
                else
                  Expanded(
                    child: Text(
                      'Settled${current.closedAt == null ? '' : ' on ${DateFormat('d MMM yyyy').format(current.closedAt!)}'}.',
                      style: SpendWiseType.body.copyWith(fontSize: 13),
                    ),
                  ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: working ? null : _forget,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SpendWiseColors.spend,
                  ),
                  child: const Text('Not a loan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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

  Future<void> _forget() => _run(
    () => widget.viewModel.uiRemoveDebt(debt.id),
    closeAfter: true,
  );

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not do that: $error')));
    }
  }
}
