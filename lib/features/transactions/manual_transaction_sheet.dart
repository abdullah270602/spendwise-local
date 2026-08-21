import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../shell/spendwise_view_model.dart';

class ManualTransactionSheet extends StatefulWidget {
  const ManualTransactionSheet({super.key, required this.viewModel});
  final SpendWiseViewModel viewModel;
  @override
  State<ManualTransactionSheet> createState() => _ManualTransactionSheetState();
}

class _ManualTransactionSheetState extends State<ManualTransactionSheet> {
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController();
  final amount = TextEditingController();
  final note = TextEditingController();
  TransactionKind kind = TransactionKind.expense;
  String? accountId;
  String? toAccountId;
  String category = 'Other';
  bool saving = false;
  @override
  void dispose() {
    title.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    accountId ??= widget.viewModel.accounts.firstOrNull?.id;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 2,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add transaction',
                style: Theme.of(context).textTheme.titleLarge,
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
                onSelectionChanged: (v) => setState(() => kind = v.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: title,
                decoration: const InputDecoration(
                  labelText: 'Merchant or description',
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Enter a description'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: 'PKR ',
                ),
                validator: (v) {
                  final parsed = Money.tryParsePkr('PKR ${v ?? ''}');
                  return parsed == null || parsed.isZero || parsed.isNegative
                      ? 'Enter a positive amount (up to 2 decimals)'
                      : null;
                },
              ),
              if (kind == TransactionKind.transfer) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: toAccountId,
                  decoration: const InputDecoration(labelText: 'To account'),
                  items: widget.viewModel.accounts
                      .where((account) => account.id != accountId)
                      .map(
                        (account) => DropdownMenuItem(
                          value: account.id,
                          child: Text(account.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => toAccountId = value,
                  validator: (value) => value == null || value == accountId
                      ? 'Choose a different destination account'
                      : null,
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: accountId,
                decoration: const InputDecoration(labelText: 'Account'),
                items: widget.viewModel.accounts
                    .map(
                      (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                    )
                    .toList(),
                onChanged: (v) => accountId = v,
                validator: (v) => v == null ? 'Add an account first' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items:
                    const [
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
                        ]
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                onChanged: (v) => category = v ?? category,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: saving ? null : _save,
                  child: Text(saving ? 'Saving…' : 'Save transaction'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    final units = Money.parsePkr('PKR ${amount.text}').minorUnits;
    await widget.viewModel.saveManualTransaction(
      ManualTransactionDraft(
        title: title.text.trim(),
        amount: MoneyViewData(units),
        kind: kind,
        accountId: accountId!,
        toAccountId: toAccountId,
        category: category,
        occurredAt: DateTime.now(),
        note: note.text.trim(),
      ),
    );
    if (mounted) Navigator.pop(context);
  }
}
