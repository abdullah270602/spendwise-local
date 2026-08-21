import 'package:flutter/material.dart';

import '../../app/theme.dart';
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
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      transaction.kind == TransactionKind.transfer
                          ? Icons.swap_horiz_rounded
                          : transaction.kind == TransactionKind.income
                          ? Icons.south_west_rounded
                          : Icons.north_east_rounded,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    transaction.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const SectionHeading('Details'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                _Detail('Type', transaction.kind.name),
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
          ),
          const SizedBox(height: 18),
          const SectionHeading('Source evidence'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(
                    Icons.layers_outlined,
                    color: SpendWiseColors.accent,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${transaction.evidenceCount} evidence ${transaction.evidenceCount == 1 ? 'item' : 'items'}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          transaction.evidenceCount > 1
                              ? 'Multiple observations support this transaction.'
                              : 'This transaction currently has one supporting observation.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (transaction.evidence.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < transaction.evidence.length; i++)
              _EvidenceCard(
                item: transaction.evidence[i],
                isLast: i == transaction.evidence.length - 1,
              ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              'Detailed source evidence is unavailable for this legacy record.',
              style: Theme.of(context).textTheme.bodySmall,
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
    await viewModel.deleteTransaction(transaction.id);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _showCorrection(BuildContext context) async {
    var kind = transaction.kind;
    var category = transaction.category;
    String? accountId =
        transaction.accountId ?? viewModel.accounts.firstOrNull?.id;
    String? toAccountId = transaction.toAccountId;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
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
                onSelectionChanged: (value) =>
                    setModalState(() => kind = value.first),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items:
                    {
                          'Food & dining',
                          'Shopping',
                          'Transport',
                          'Bills & utilities',
                          'Entertainment',
                          'Subscriptions & digital services',
                          'Cash withdrawal',
                          'Fees',
                          'Income',
                          'Transfer',
                          'Other',
                          transaction.category,
                        }
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                onChanged: (value) => category = value ?? category,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: accountId,
                decoration: const InputDecoration(labelText: 'Account'),
                items: viewModel.accounts
                    .map(
                      (value) => DropdownMenuItem(
                        value: value.id,
                        child: Text(value.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => accountId = value,
              ),
              if (kind == TransactionKind.transfer) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: toAccountId,
                  decoration: const InputDecoration(
                    labelText: 'Destination account',
                  ),
                  items: viewModel.accounts
                      .where((value) => value.id != accountId)
                      .map(
                        (value) => DropdownMenuItem(
                          value: value.id,
                          child: Text(value.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => toAccountId = value,
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
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
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'This ledger build cannot edit imported records yet.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Save classification'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true && context.mounted) Navigator.pop(context);
  }
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.item, required this.isLast});
  final EvidenceViewData item;
  final bool isLast;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 28,
        child: Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: SpendWiseColors.accent,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Container(width: 1, height: 128, color: SpendWiseColors.border),
          ],
        ),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 2,
              ),
              title: Text(
                item.sourceLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${_stateLabel(item.state)} · ${(item.confidence * 100).round()}% confidence',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: [
                if (item.title.isNotEmpty || item.body.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: SpendWiseColors.background,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      [
                        item.title,
                        item.body,
                      ].where((value) => value.isNotEmpty).join('\n'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 10),
                _Meta('Source reader', item.parserId),
                if (item.ruleId.isNotEmpty) _Meta('Matching rule', item.ruleId),
                _Meta('Observed', _dateTime(item.observedAt)),
                if (item.reasons.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'WHY IT MATCHED',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(fontSize: 10, letterSpacing: 1.2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final reason in item.reasons)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '• ${reason.replaceAll('_', ' ')}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    ],
  );

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

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
