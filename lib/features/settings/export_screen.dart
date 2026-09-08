import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key, required this.viewModel});
  final SpendWiseViewModel viewModel;
  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  ExportFormat format = ExportFormat.csv;
  DateTimeRange? range;
  final accountIds = <String>{};
  final kinds = <TransactionKind>{};
  final categories = <String>{};
  bool evidence = false, busy = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Export ledger')),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          SpendWiseTheme.gutter,
          8,
          SpendWiseTheme.gutter,
          48,
        ),
        children: [
          // A caution, not a card: a left rule in the warning tone and the
          // app's own edge on the other three sides, same as the held-back
          // block on Accounts -- there is no second surface colour to fill.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: SpendWiseColors.warning, width: 2),
                top: BorderSide(color: SpendWiseColors.edge),
                right: BorderSide(color: SpendWiseColors.edge),
                bottom: BorderSide(color: SpendWiseColors.edge),
              ),
            ),
            child: Text(
              'Exports are readable files and are not protected by SpendWise encryption. Store and share them carefully.',
              style: SpendWiseType.body.copyWith(fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 22),
          const Eyebrow('Format'),
          const SizedBox(height: 11),
          ViewToggle(
            options: const ['CSV', 'JSON'],
            selected: format == ExportFormat.csv ? 0 : 1,
            onSelected: (index) => setState(
              () => format = index == 0 ? ExportFormat.csv : ExportFormat.json,
            ),
          ),
          const SizedBox(height: 18),
          InkWell(
            onTap: () async {
              final result = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (result != null) setState(() => range = result);
            },
            child: Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: SpendWiseColors.line)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Date range', style: SpendWiseType.row),
                        const SizedBox(height: 2),
                        Text(
                          range == null
                              ? 'All dates'
                              : '${_date(range!.start)} – ${_date(range!.end)}',
                          style: SpendWiseType.body.copyWith(fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '›',
                    style: TextStyle(
                      fontSize: 20,
                      height: 1,
                      color: SpendWiseColors.dim,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (range != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => range = null),
                child: const Text('Clear date range'),
              ),
            ),
          const SizedBox(height: 22),
          const Eyebrow('Accounts'),
          const SizedBox(height: 11),
          Wrap(
            spacing: 7,
            children: [
              for (final a in widget.viewModel.accounts)
                FilterChip(
                  label: Text(a.name),
                  selected: accountIds.contains(a.id),
                  onSelected: (v) => setState(
                    () => v ? accountIds.add(a.id) : accountIds.remove(a.id),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
          const Eyebrow('Transaction types'),
          const SizedBox(height: 11),
          Wrap(
            spacing: 7,
            children: [
              for (final value in TransactionKind.values)
                FilterChip(
                  label: Text(titleCase(value.name)),
                  selected: kinds.contains(value),
                  onSelected: (v) => setState(
                    () => v ? kinds.add(value) : kinds.remove(value),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
          const Eyebrow('Categories'),
          const SizedBox(height: 11),
          Wrap(
            spacing: 7,
            children: [
              for (final value
                  in widget.viewModel.transactions
                      .map((t) => t.category)
                      .toSet())
                FilterChip(
                  label: Text(value),
                  selected: categories.contains(value),
                  onSelected: (v) => setState(
                    () => v ? categories.add(value) : categories.remove(value),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          InkWell(
            onTap: () => setState(() => evidence = !evidence),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: SpendWiseColors.line)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Include raw evidence', style: SpendWiseType.row),
                        const SizedBox(height: 2),
                        Text(
                          'Adds notification/import text and parser reasoning',
                          style: SpendWiseType.body.copyWith(fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Switch(
                    value: evidence,
                    onChanged: (v) => setState(() => evidence = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          PrimaryAction(
            label: busy ? 'Preparing…' : 'Create export',
            busy: busy,
            onPressed: busy ? null : _export,
          ),
        ],
      ),
    ),
  );
  Future<void> _export() async {
    setState(() => busy = true);
    try {
      await widget.viewModel.uiExportLedger(
        ExportRequest(
          format: format,
          from: range?.start,
          to: range?.end,
          accountIds: accountIds,
          kinds: kinds,
          categories: categories,
          includeEvidence: evidence,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Export saved')));
      }
    } on ExportCancelledException {
      // The Android document picker was closed without creating a file.
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create export: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  static String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
