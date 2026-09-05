import 'package:flutter/material.dart';

import '../../app/theme.dart';
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
        padding: const EdgeInsets.fromLTRB(SpendWiseTheme.gutter, 8, SpendWiseTheme.gutter, 48),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SpendWiseColors.warning.withValues(alpha: .1),
              border: Border.all(
                color: SpendWiseColors.warning.withValues(alpha: .3),
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: SpendWiseColors.warning,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'Exports are readable files and are not protected by SpendWise encryption. Store and share them carefully.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Format', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ExportFormat>(
            segments: const [
              ButtonSegment(
                value: ExportFormat.csv,
                label: Text('CSV'),
                icon: Icon(Icons.table_view_outlined),
              ),
              ButtonSegment(
                value: ExportFormat.json,
                label: Text('JSON'),
                icon: Icon(Icons.data_object_rounded),
              ),
            ],
            selected: {format},
            onSelectionChanged: (v) => setState(() => format = v.first),
          ),
          const SizedBox(height: 18),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date range'),
            subtitle: Text(
              range == null
                  ? 'All dates'
                  : '${_date(range!.start)} – ${_date(range!.end)}',
            ),
            trailing: const Icon(Icons.date_range_outlined),
            onTap: () async {
              final result = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (result != null) setState(() => range = result);
            },
          ),
          if (range != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => range = null),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Clear date range'),
              ),
            ),
          const Divider(),
          const SizedBox(height: 10),
          Text('Accounts', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
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
          const SizedBox(height: 18),
          Text(
            'Transaction types',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 18),
          Text('Categories', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
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
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Include raw evidence'),
            subtitle: const Text(
              'Adds notification/import text and parser reasoning',
            ),
            value: evidence,
            onChanged: (v) => setState(() => evidence = v),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: busy ? null : _export,
            icon: const Icon(Icons.download_rounded),
            label: Text(busy ? 'Preparing…' : 'Create export'),
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
