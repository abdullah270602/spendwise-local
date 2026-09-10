import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/category_picker.dart';
import '../../widgets/shape_kit.dart';
import '../debts/debt_matching.dart';
import '../debts/debt_sheets.dart' as debt_sheets;
import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';

class TransactionDetailsScreen extends StatelessWidget {
  const TransactionDetailsScreen({
    super.key,
    required this.viewModel,
    required this.transaction,
  });
  final SpendWiseViewModel viewModel;
  final TransactionViewData transaction;
  @override
  Widget build(BuildContext context) {
    final color = transaction.kind == TransactionKind.expense
        ? SpendWiseColors.expense
        : transaction.kind == TransactionKind.income
        ? SpendWiseColors.income
        : SpendWiseColors.warning;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction'),
        actions: [
          IconButton(
            onPressed: () => _showCorrection(context),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit classification',
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'delete') {
                await _confirmDelete(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete transaction')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          SpendWiseTheme.gutter,
          10,
          SpendWiseTheme.gutter,
          48,
        ),
        children: [
          // No card, no icon-in-a-tinted-circle: every other screen states a
          // figure as an eyebrow, a title and a number set straight on the
          // background, and this one drew a raised panel around the same
          // three facts instead of trusting them to carry the page.
          Eyebrow(transaction.kind.name, color: color),
          const SizedBox(height: 8),
          Text(
            transaction.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          Text(
            formatMoney(
              transaction.amount,
              signed: transaction.kind != TransactionKind.transfer,
            ),
            style: Theme.of(context).textTheme.displaySmall
                ?.copyWith(color: color),
          ),
          const SizedBox(height: 8),
          Text(
            transaction.subtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          const SectionHeading('Details'),
          const SizedBox(height: 8),
          Column(
            children: [
              _Detail('Type', titleCase(transaction.kind.name)),
              _Detail('Category', transaction.category),
              _Detail(
                'Account',
                transaction.accountName.isEmpty
                    ? 'Unassigned'
                    : transaction.accountName,
              ),
              _Detail(
                'Date',
                '${transaction.occurredAt.day}/${transaction.occurredAt.month}/${transaction.occurredAt.year} · ${transaction.occurredAt.hour.toString().padLeft(2, '0')}:${transaction.occurredAt.minute.toString().padLeft(2, '0')}',
              ),
              if (transaction.note.isNotEmpty)
                _Detail('Note', transaction.note),
            ],
          ),
          const SizedBox(height: 18),
          _BalanceTrail(transaction: transaction),
          _LoanSection(viewModel: viewModel, transaction: transaction),
          const SectionHeading('Source evidence'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: SpendWiseColors.edge),
            ),
            child: Row(
              children: [
                Icon(Icons.layers_outlined, color: SpendWiseColors.accent),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.evidenceCount == 0
                            ? 'No linked evidence'
                            : '${transaction.evidenceCount} evidence ${transaction.evidenceCount == 1 ? 'item' : 'items'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(switch (transaction.evidenceCount) {
                        0 => 'Manual and older transactions may not have a linked notification or import.',
                        1 => 'One notification or import supports this transaction.',
                        _ => 'Multiple observations support this transaction.',
                      }, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (transaction.evidence.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < transaction.evidence.length; i++)
              _EvidenceCard(
                item: transaction.evidence[i],
                isLast: i == transaction.evidence.length - 1,
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this transaction?'),
        content: const Text(
          'The ledger entry will be removed. Its original notification or import evidence remains available for reconciliation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: SpendWiseColors.expense,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete transaction'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    // Grabbed before the pop below: once this screen is gone its own
    // Scaffold is gone with it, and the messenger and navigator this screen
    // sat inside are what stay -- the same reason the review inbox grabs
    // both before it pops the sheet it deletes from.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final id = transaction.id;
    try {
      await viewModel.deleteTransaction(id);
    } catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not delete: $error')),
        );
      }
      return;
    }
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Transaction deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => viewModel.restoreTransaction(id),
        ),
      ),
    );
  }

  Future<void> _showCorrection(BuildContext context) async {
    var kind = transaction.kind;
    var category = transaction.category;
    final accounts = viewModel.accounts;
    final accountIds = accounts.map((item) => item.id).toSet();
    String? accountId = accountIds.contains(transaction.accountId)
        ? transaction.accountId
        : accounts.firstOrNull?.id;
    String? toAccountId =
        accountIds.contains(transaction.toAccountId) &&
            transaction.toAccountId != accountId
        ? transaction.toAccountId
        : accounts.where((item) => item.id != accountId).firstOrNull?.id;
    var saving = false;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 16),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit classification',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Change the type, category, or account. Original source evidence stays unchanged.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 18),
                SegmentedButton<TransactionKind>(
                  segments: const [
                    ButtonSegment(
                      value: TransactionKind.expense,
                      label: Text('Expense'),
                    ),
                    ButtonSegment(
                      value: TransactionKind.income,
                      label: Text('Income'),
                    ),
                    ButtonSegment(
                      value: TransactionKind.transfer,
                      label: Text('Transfer'),
                    ),
                  ],
                  selected: {kind},
                  onSelectionChanged: saving
                      ? null
                      : (value) => setModalState(() {
                          kind = value.first;
                          if (kind == TransactionKind.transfer &&
                              (toAccountId == null ||
                                  toAccountId == accountId)) {
                            toAccountId = accounts
                                .where((item) => item.id != accountId)
                                .firstOrNull
                                ?.id;
                          }
                        }),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: saving
                      ? null
                      : () async {
                          final picked = await pickCategory(
                            context,
                            viewModel: viewModel,
                            kind: kind,
                            current: category,
                          );
                          if (picked != null) {
                            setModalState(() => category = picked);
                          }
                        },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Category'),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(category, style: SpendWiseType.row),
                        ),
                        const Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: SpendWiseColors.dim,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: accountId,
                  decoration: const InputDecoration(labelText: 'Account'),
                  items: accounts
                      .map(
                        (value) => DropdownMenuItem(
                          value: value.id,
                          child: Text(value.name),
                        ),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) => setModalState(() {
                          accountId = value;
                          if (toAccountId == accountId) {
                            toAccountId = accounts
                                .where((item) => item.id != accountId)
                                .firstOrNull
                                ?.id;
                          }
                        }),
                ),
                if (kind == TransactionKind.transfer) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('destination-$accountId-$toAccountId'),
                    initialValue: toAccountId,
                    decoration: const InputDecoration(
                      labelText: 'Destination account',
                    ),
                    items: accounts
                        .where((value) => value.id != accountId)
                        .map(
                          (value) => DropdownMenuItem(
                            value: value.id,
                            child: Text(value.name),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (value) => setModalState(() => toAccountId = value),
                  ),
                  if (accounts.length < 2) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Add another account before classifying this as a transfer.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: saving || accounts.isEmpty
                        ? null
                        : () async {
                            if (accountId == null) {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                const SnackBar(
                                  content: Text('Choose an account first.'),
                                ),
                              );
                              return;
                            }
                            if (kind == TransactionKind.transfer &&
                                (toAccountId == null ||
                                    toAccountId == accountId)) {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Choose a different destination account.',
                                  ),
                                ),
                              );
                              return;
                            }
                            setModalState(() => saving = true);
                            try {
                              await viewModel.uiCorrectTransaction(
                                transaction.id,
                                TransactionCorrectionDraft(
                                  kind: kind,
                                  category: category,
                                  accountId: accountId,
                                  toAccountId: toAccountId,
                                ),
                              );
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext, true);
                              }
                            } on UnsupportedError {
                              if (sheetContext.mounted) {
                                setModalState(() => saving = false);
                                ScaffoldMessenger.of(sheetContext).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'This ledger build cannot edit imported records yet.',
                                    ),
                                  ),
                                );
                              }
                            } catch (error) {
                              if (sheetContext.mounted) {
                                setModalState(() => saving = false);
                                ScaffoldMessenger.of(sheetContext).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Could not save changes: ${error.toString().replaceFirst('StateError: ', '').replaceFirst('ArgumentError: ', '')}',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                    child: Text(saving ? 'Saving…' : 'Save classification'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved == true && context.mounted) Navigator.pop(context);
  }
}

/// One piece of evidence, collapsed to its source and confidence until
/// tapped open.
///
/// Built from a plain bordered block and a hand-rolled disclosure rather
/// than [ExpansionTile]: the stock tile ships its own chevron rotation and
/// expand animation, on a duration this app never chose and with no way to
/// honour reduced motion short of reaching past the widget to silence it --
/// which is exactly the gap that let this screen's disclosures keep moving
/// after every other animation in the app had been told to stop.
class _EvidenceCard extends StatefulWidget {
  const _EvidenceCard({required this.item, required this.isLast});
  final EvidenceViewData item;
  final bool isLast;

  @override
  State<_EvidenceCard> createState() => _EvidenceCardState();
}

class _EvidenceCardState extends State<_EvidenceCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    // 220ms is the short end of the app's own range: a chevron and a detail
    // panel are the smallest motion this screen makes, so they take the
    // smallest number already in use rather than inventing a new one.
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 28,
          child: Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: SpendWiseColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
              if (!widget.isLast)
                Container(width: 1, height: 128, color: SpendWiseColors.border),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: SpendWiseColors.edge),
              ),
              child: Column(
                children: [
                  Semantics(
                    button: true,
                    expanded: _open,
                    child: InkWell(
                      onTap: () => setState(() => _open = !_open),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.sourceLabel,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_stateLabel(item.state)} · ${(item.confidence * 100).round()}% confidence',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            AnimatedRotation(
                              turns: _open ? .5 : 0,
                              duration: duration,
                              curve: Curves.easeOutQuint,
                              child: const Icon(
                                Icons.expand_more_rounded,
                                size: 18,
                                color: SpendWiseColors.dim,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: duration,
                    curve: Curves.easeOutQuint,
                    alignment: Alignment.topCenter,
                    child: !_open
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (item.title.isNotEmpty ||
                                    item.body.isNotEmpty)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: SpendWiseColors.background,
                                      border: Border.all(
                                        color: SpendWiseColors.line,
                                      ),
                                    ),
                                    child: Text(
                                      [item.title, item.body]
                                          .where((value) => value.isNotEmpty)
                                          .join('\n'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
                                const SizedBox(height: 10),
                                _Meta('Source reader', item.parserId),
                                if (item.ruleId.isNotEmpty)
                                  _Meta('Matching rule', item.ruleId),
                                _Meta('Observed', _dateTime(item.observedAt)),
                                if (item.reasons.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'WHY IT MATCHED',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontSize: 10,
                                            letterSpacing: 1.2,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  for (final reason in item.reasons)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '• ${reason.replaceAll('_', ' ')}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _stateLabel(EvidenceState state) => switch (state) {
    EvidenceState.accepted => 'Supporting evidence',
    EvidenceState.duplicate => 'Duplicate observation',
    EvidenceState.matched => 'Matched transfer leg',
    EvidenceState.unparsed => 'Could not be read',
    EvidenceState.ignored => 'Not used',
  };

  static String _dateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.day}/${local.month}/${local.year} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: 74,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// One label-value pair. Draws its own hairline underneath rather than
/// sitting inside a bordered box -- the same rule as [RegisterRow]: a group
/// of facts is a run of rows separated by hairlines, never a panel.
class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 13),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: SpendWiseColors.line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

/// Lending is invisible to a bank alert, so this is where a person tells the
/// ledger what really happened. Offered on every ordinary movement, and
/// replaced by the loan itself once one exists.
class _LoanSection extends StatelessWidget {
  const _LoanSection({required this.viewModel, required this.transaction});

  final SpendWiseViewModel viewModel;
  final TransactionViewData transaction;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    // The screen is handed a snapshot taken when it was pushed. Attaching an
    // entry to a loan changes exactly this section, so it has to read the
    // entry back rather than keep drawing the copy it arrived with.
    animation: viewModel,
    builder: (context, _) => _body(context),
  );

  Widget _body(BuildContext context) {
    final live =
        viewModel.transactions
            .where((item) => item.id == transaction.id)
            .firstOrNull ??
        transaction;
    if (live.kind == TransactionKind.transfer) {
      return const SizedBox.shrink();
    }
    final debt = live.debtId == null
        ? null
        : viewModel.uiDebts.where((item) => item.id == live.debtId).firstOrNull;

    if (debt == null) return _unattached(context, live);

    final tone = debt_sheets.toneForDebtKind(debt.kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(debt.kind.categoryName),
        const SizedBox(height: 8),
        InkWell(
          onTap: () =>
              debt_sheets.openDebt(context, viewModel: viewModel, debt: debt),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
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
                      Text(debt.counterparty, style: SpendWiseType.row),
                      const SizedBox(height: 2),
                      Text(
                        debt.isSettled
                            ? 'Settled'
                            : '${formatAmount(debt.outstanding, cents: false)} still out',
                        style: SpendWiseType.metaTight,
                      ),
                    ],
                  ),
                ),
                const Text('→', style: TextStyle(color: SpendWiseColors.dim)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  /// What an entry that belongs to no loan offers: the three stories it could
  /// be the start of, and — the half that was missing — the loans it could be
  /// the end of.
  Widget _unattached(BuildContext context, TransactionViewData live) {
    final matches = debtMatchesFor(transaction: live, debts: viewModel.uiDebts);
    final open = debtsOpenTo(transaction: live, debts: viewModel.uiDebts);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (matches.isNotEmpty) ...[
          _Suggestion(
            viewModel: viewModel,
            transaction: live,
            match: matches.first,
            others: matches.length - 1,
          ),
          const SizedBox(height: 22),
        ],
        const SectionHeading('Whose money was this?'),
        const SizedBox(height: 8),
        Text(
          'A bank alert cannot tell lending, borrowing and holding apart '
          '— only you know which one this was.',
          style: SpendWiseType.body.copyWith(fontSize: 13),
        ),
        const SizedBox(height: 12),
        // All three stories, not the two most likely -- an entry point
        // that only offered lending and borrowing was the reason holding
        // was only ever reached by picking one of those first and
        // correcting it inside the sheet.
        for (final kind in DebtKind.values) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => debt_sheets.markAsLoan(
                context,
                viewModel: viewModel,
                transaction: live,
                initialKind: kind,
              ),
              child: Text(kind.title),
            ),
          ),
          const SizedBox(height: 8),
        ],
        // Opening a new loan and closing an old one are opposite answers to
        // the same question, and only one of them used to be on this screen.
        // Without this, somebody whose loan came back had no move except to
        // record a second loan for the same money.
        if (open.isNotEmpty && matches.isEmpty)
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => debt_sheets.settleFromEntry(
                context,
                viewModel: viewModel,
                transaction: live,
              ),
              child: Text(
                live.kind == TransactionKind.income
                    ? 'This is money coming back on a loan'
                    : 'This is money going back on a loan',
              ),
            ),
          ),
        const SizedBox(height: 10),
      ],
    );
  }
}

/// The one loan this entry most looks like, offered as a question.
///
/// Never acted on by itself. Settling a loan the owner did not settle is the
/// expensive mistake here: a loan they believe is closed is money they will
/// never ask for again, and nothing in a bank alert can carry that decision.
class _Suggestion extends StatelessWidget {
  const _Suggestion({
    required this.viewModel,
    required this.transaction,
    required this.match,
    required this.others,
  });

  final SpendWiseViewModel viewModel;
  final TransactionViewData transaction;
  final DebtMatch match;

  /// How many other open loans this entry also looks like.
  final int others;

  @override
  Widget build(BuildContext context) {
    final debt = match.debt;
    final tone = debt_sheets.toneForDebtKind(debt.kind);
    final headline = switch (debt.kind) {
      DebtKind.lent => 'Is this ${debt.counterparty} paying you back?',
      DebtKind.borrowed => 'Is this you paying ${debt.counterparty} back?',
      DebtKind.holding => 'Is this ${debt.counterparty} money going on?',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: tone, width: 2),
          top: const BorderSide(color: SpendWiseColors.line),
          right: const BorderSide(color: SpendWiseColors.line),
          bottom: const BorderSide(color: SpendWiseColors.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(headline, style: SpendWiseType.row),
          const SizedBox(height: 4),
          // The reason is on screen because a suggestion nobody can check is
          // just an assertion, and this one moves money out of the month.
          Text(
            '${formatAmount(debt.outstanding, cents: false)} is still out on '
            'this loan, and ${match.reason}.',
            style: SpendWiseType.body.copyWith(fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => debt_sheets.settleFromEntry(
                context,
                viewModel: viewModel,
                transaction: transaction,
                debt: debt,
              ),
              child: const Text('Record it against this loan'),
            ),
          ),
          if (others > 0)
            TextButton(
              onPressed: () => debt_sheets.settleFromEntry(
                context,
                viewModel: viewModel,
                transaction: transaction,
              ),
              child: Text(
                others == 1
                    ? 'One other loan also fits'
                    : '$others other loans also fit',
              ),
            ),
        ],
      ),
    );
  }
}

/// What this entry did to the balance of every account it touched.
///
/// Every other figure in this app is derived from something derived, and past
/// a certain number of derivations a person is entitled to stop believing
/// them. This is the one an owner can hold against a bank statement and check
/// line by line without trusting a single sum SpendWise made.
///
/// Drawn from the entry's own record rather than recomputed here: the figure
/// before is the figure after less what this entry did, so the three numbers
/// on the row cannot disagree with each other.
class _BalanceTrail extends StatelessWidget {
  const _BalanceTrail({required this.transaction});

  final TransactionViewData transaction;

  @override
  Widget build(BuildContext context) {
    final balances = transaction.balances;
    // An alert that matched no account has no balance to have moved, and
    // inventing one would be the app asserting something it cannot know.
    if (balances.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading('Balance around this'),
        const SizedBox(height: 8),
        for (final change in balances) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: SpendWiseColors.edge),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(change.accountName, style: SpendWiseType.row),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _Step(
                        label: 'Before',
                        minor: change.beforeMinor,
                        tone: SpendWiseColors.dim,
                      ),
                    ),
                    Text(
                      change.deltaMinor < 0 ? '−' : '+',
                      style: SpendWiseType.row.copyWith(
                        color: change.deltaMinor < 0
                            ? SpendWiseColors.spend
                            : SpendWiseColors.keep,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _Step(
                        label: 'Moved',
                        minor: change.deltaMinor.abs(),
                        tone: change.deltaMinor < 0
                            ? SpendWiseColors.spend
                            : SpendWiseColors.keep,
                      ),
                    ),
                    const Text(
                      '=',
                      style: TextStyle(color: SpendWiseColors.dim),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _Step(
                        label: 'After',
                        minor: change.afterMinor,
                        tone: SpendWiseColors.fg,
                        alignRight: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 10),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.label,
    required this.minor,
    required this.tone,
    this.alignRight = false,
  });

  final String label;
  final int minor;
  final Color tone;
  final bool alignRight;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: alignRight
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      Eyebrow(label),
      const SizedBox(height: 3),
      // A figure has no spaces to wrap at, so its only way of fitting a
      // third of a narrow screen is to shrink.
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          formatMinor(minor),
          style: SpendWiseType.rowStrong.copyWith(color: tone),
        ),
      ),
    ],
  );
}
