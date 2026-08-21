import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/statement_table_detector.dart';
import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';

class ImportCsvScreen extends StatefulWidget {
  const ImportCsvScreen({super.key, required this.viewModel});
  final SpendWiseViewModel viewModel;
  @override
  State<ImportCsvScreen> createState() => _ImportCsvScreenState();
}

class _ImportCsvScreenState extends State<ImportCsvScreen> {
  String? csv;
  StatementFileViewData? selectedFile;
  String? selectedSheetName;
  int step = 0;
  bool busy = false;
  String? accountId;
  String sourceLabel = 'Bank statement';
  List<String> headers = const [];
  List<List<String>> rows = const [];
  int headerRowIndex = 0;
  final mapping = <ImportField, String>{};
  CsvImportPreviewViewData? preview;
  bool exitApproved = false;
  @override
  Widget build(BuildContext context) {
    accountId ??= widget.viewModel.accounts.firstOrNull?.id;
    return PopScope(
      canPop: exitApproved || (step == 0 && csv == null),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (step > 0) {
          setState(() => step--);
          return;
        }
        final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard this import?'),
            content: const Text(
              'The selected file and column mapping will be cleared.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (discard == true && mounted) {
          setState(() => exitApproved = true);
          Navigator.pop(this.context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Import statement')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
              child: Row(
                children: [
                  for (var i = 0; i < 4; i++)
                    Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: i == 3 ? 0 : 6),
                        height: 4,
                        decoration: BoxDecoration(
                          color: i <= step
                              ? SpendWiseColors.accent
                              : SpendWiseColors.border,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: ListView(
                  key: ValueKey(step),
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  children: [
                    _header,
                    const SizedBox(height: 22),
                    if (step == 0) _selectFile(context),
                    if (step == 1) _mapColumns(context),
                    if (step == 2) _preview(context),
                    if (step == 3) _commit(context),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    if (step > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: busy ? null : () => setState(() => step--),
                          child: const Text('Back'),
                        ),
                      ),
                    if (step > 0) const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _canContinue ? _next : null,
                        child: Text(
                          busy
                              ? 'Working…'
                              : step == 3
                              ? 'Import transactions'
                              : 'Continue',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget get _header => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        [
          'Select statement',
          'Map columns',
          'Review rows',
          'Confirm import',
        ][step],
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 7),
      Text(
        [
          'Choose where these transactions belong. Nothing is saved yet.',
          'Confirm how the statement columns map to ledger fields.',
          'Inspect valid rows, duplicates, and errors before committing.',
          'SpendWise will save raw rows as evidence, then reconcile them.',
        ][step],
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: SpendWiseColors.textSecondary),
      ),
    ],
  );
  Widget _selectFile(BuildContext context) => Column(
    children: [
      DropdownButtonFormField<String>(
        initialValue: accountId,
        decoration: const InputDecoration(labelText: 'Destination account'),
        items: widget.viewModel.accounts
            .map(
              (a) => DropdownMenuItem(
                value: a.id,
                child: Text('${a.name} · ${a.currency}'),
              ),
            )
            .toList(),
        onChanged: (v) => setState(() => accountId = v),
      ),
      const SizedBox(height: 12),
      TextFormField(
        initialValue: sourceLabel,
        decoration: const InputDecoration(labelText: 'Source / institution'),
        onChanged: (v) => sourceLabel = v.trim(),
      ),
      const SizedBox(height: 16),
      Semantics(
        button: true,
        label: csv == null
            ? 'Choose CSV or Excel file. Supports CSV, XLSX, and XLS. Read locally on this device.'
            : '${selectedFile!.fileName}, ${rows.length} data rows',
        child: InkWell(
          onTap: busy ? null : _pick,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: double.infinity,
            height: 136,
            decoration: BoxDecoration(
              color: SpendWiseColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: csv == null
                    ? SpendWiseColors.border
                    : SpendWiseColors.accent,
              ),
            ),
            child: ExcludeSemantics(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    csv == null
                        ? Icons.upload_file_outlined
                        : Icons.check_circle_outline_rounded,
                    size: 38,
                    color: SpendWiseColors.accent,
                  ),
                  const SizedBox(height: 11),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Text(
                      csv == null
                          ? 'Choose CSV or Excel file'
                          : '${selectedFile!.fileName} · ${rows.length} rows',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      if ((selectedFile?.sheets.length ?? 0) > 1) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ObjectKey(selectedFile),
          initialValue: selectedSheetName,
          decoration: const InputDecoration(labelText: 'Worksheet'),
          items: selectedFile!.sheets
              .map(
                (sheet) => DropdownMenuItem(
                  value: sheet.name,
                  child: Text(sheet.name),
                ),
              )
              .toList(),
          onChanged: busy
              ? null
              : (name) {
                  if (name == null) return;
                  final sheet = selectedFile!.sheets.firstWhere(
                    (sheet) => sheet.name == name,
                  );
                  _loadSheet(selectedFile!, sheet);
                },
        ),
      ],
      const SizedBox(height: 16),
      const PrivacyBanner(compact: true),
    ],
  );
  Widget _mapColumns(BuildContext context) => Column(
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Detected headers',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (headerRowIndex > 0) ...[
                const SizedBox(height: 3),
                Text(
                  'Transaction table found on row ${headerRowIndex + 1}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: headers.map((h) => Chip(label: Text(h))).toList(),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      for (final field in const [
        ImportField.date,
        ImportField.description,
        ImportField.amount,
        ImportField.debit,
        ImportField.credit,
        ImportField.direction,
        ImportField.balance,
        ImportField.merchant,
        ImportField.currency,
        ImportField.reference,
        ImportField.ignore,
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DropdownButtonFormField<String?>(
            initialValue: mapping[field],
            decoration: InputDecoration(
              labelText: _fieldName(field),
              helperText:
                  field == ImportField.date || field == ImportField.description
                  ? 'Required'
                  : null,
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Not mapped'),
              ),
              ...headers.map(
                (h) => DropdownMenuItem<String?>(value: h, child: Text(h)),
              ),
            ],
            onChanged: (v) => setState(() {
              if (v == null) {
                mapping.remove(field);
              } else {
                mapping[field] = v;
              }
            }),
          ),
        ),
    ],
  );
  Widget _preview(BuildContext context) {
    final result = preview!;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Count('Valid', result.validCount, SpendWiseColors.income),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Count(
                'Errors',
                result.errorCount,
                SpendWiseColors.expense,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Count(
                'Possible duplicates',
                result.duplicateCount,
                SpendWiseColors.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Row')),
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Description')),
                DataColumn(label: Text('Amount')),
                DataColumn(label: Text('Status')),
              ],
              rows: [
                for (final row in result.rows.take(25))
                  DataRow(
                    cells: [
                      DataCell(Text('${row.rowNumber}')),
                      DataCell(Text(row.date)),
                      DataCell(
                        SizedBox(
                          width: 150,
                          child: Text(
                            row.description,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(Text(row.amount)),
                      DataCell(
                        Text(
                          row.error ??
                              (row.duplicate ? 'Review duplicate' : 'Valid'),
                          style: TextStyle(
                            color: row.error != null
                                ? SpendWiseColors.expense
                                : row.duplicate
                                ? SpendWiseColors.warning
                                : SpendWiseColors.income,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (result.rows.length > 25)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Showing 25 of ${result.rows.length} rows'),
          ),
        if (result.sameFileAlreadyImported)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'This exact file was already imported. It will not be duplicated.',
            ),
          ),
      ],
    );
  }

  Widget _commit(BuildContext context) {
    final valid = preview?.validCount ?? 0;
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                const Icon(
                  Icons.fact_check_outlined,
                  color: SpendWiseColors.accent,
                  size: 38,
                ),
                const SizedBox(height: 12),
                Text(
                  '$valid rows ready',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 5),
                Text(
                  'Account: ${widget.viewModel.accounts.where((a) => a.id == accountId).map((a) => a.name).firstOrNull ?? 'Unknown'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Source: $sourceLabel',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const PrivacyBanner(),
      ],
    );
  }

  bool get _canContinue =>
      !busy &&
      switch (step) {
        0 => csv != null && accountId != null,
        1 =>
          mapping.containsKey(ImportField.date) &&
              (mapping.containsKey(ImportField.description) ||
                  mapping.containsKey(ImportField.merchant)) &&
              (mapping.containsKey(ImportField.amount) ||
                  mapping.containsKey(ImportField.debit) ||
                  mapping.containsKey(ImportField.credit)),
        _ => true,
      };
  Future<void> _pick() async {
    setState(() => busy = true);
    try {
      final file = await widget.viewModel.uiPickStatementFile();
      if (!mounted) return;
      if (file == null) {
        setState(() => busy = false);
        return;
      }
      _loadSheet(file, file.sheets.first);
    } catch (error) {
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read statement: $error')),
      );
    }
  }

  void _loadSheet(StatementFileViewData file, StatementSheetViewData sheet) {
    final value = sheet.csvText;
    final detected = const StatementTableDetector().detect(value);
    final parsedRows = detected.dataRows
        .map((row) => row.map((value) => '$value').toList())
        .toList();
    setState(() {
      selectedFile = file;
      selectedSheetName = sheet.name;
      csv = value;
      headers = detected.headers;
      rows = parsedRows;
      headerRowIndex = detected.headerRowIndex;
      mapping.clear();
      preview = null;
      busy = false;
      for (final h in headers) {
        final field = switch (recognizeStatementHeader(h)) {
          StatementColumnKind.date => ImportField.date,
          StatementColumnKind.description => ImportField.description,
          StatementColumnKind.merchant => ImportField.merchant,
          StatementColumnKind.debit => ImportField.debit,
          StatementColumnKind.credit => ImportField.credit,
          StatementColumnKind.amount => ImportField.amount,
          StatementColumnKind.direction => ImportField.direction,
          StatementColumnKind.balance => ImportField.balance,
          StatementColumnKind.reference => ImportField.reference,
          StatementColumnKind.currency => ImportField.currency,
          StatementColumnKind.unknown => null,
        };
        if (field != null) {
          mapping.putIfAbsent(field, () => h);
        }
      }
    });
  }

  Future<void> _next() async {
    if (step == 1) {
      setState(() => busy = true);
      try {
        final result = await widget.viewModel.uiPreviewCsvImport(_draft);
        if (!mounted) return;
        setState(() {
          preview = result;
          busy = false;
          step = 2;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() => busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not preview file: $error')),
        );
      }
      return;
    }
    if (step < 3) {
      setState(() => step++);
      return;
    }
    setState(() => busy = true);
    try {
      await widget.viewModel.uiCommitCsvImport(_draft);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Statement imported and reconciled')),
        );
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) setState(() => busy = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import failed: $error')));
      }
    }
  }

  CsvImportDraft get _draft => CsvImportDraft(
    csvText: csv!,
    accountId: accountId!,
    sourceLabel: sourceLabel.isEmpty ? 'Statement import' : sourceLabel,
    fileName:
        '${selectedFile?.fileName ?? 'statement.csv'}${selectedSheetName == null ? '' : ' · $selectedSheetName'}',
    mapping: Map.unmodifiable(mapping),
  );

  static String _fieldName(ImportField field) => switch (field) {
    ImportField.date => 'Date',
    ImportField.description => 'Description / merchant',
    ImportField.amount => 'Signed amount',
    ImportField.debit => 'Debit amount',
    ImportField.credit => 'Credit amount',
    ImportField.direction => 'Transaction direction',
    ImportField.balance => 'Running balance',
    ImportField.merchant => 'Merchant / counterparty',
    ImportField.currency => 'Currency',
    ImportField.reference => 'Reference',
    ImportField.ignore => 'Ignore field',
  };
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(11),
      child: Column(
        children: [
          Text(
            '$value',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: color),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
