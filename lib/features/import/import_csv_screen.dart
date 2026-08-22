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
  StatementFileViewData? selectedFile;
  int step = 0;
  bool busy = false;
  String sourceLabel = 'Bank statement';
  final sheetStates = <String, _SheetImportState>{};
  CsvImportPreviewViewData? preview;
  bool exitApproved = false;
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: exitApproved || (step == 0 && selectedFile == null),
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
          'Choose the worksheets to import and confirm each suggested account. Nothing is saved yet.',
          'Confirm the detected columns for every selected worksheet.',
          'Review inferred categories, cross-sheet duplicates, and row errors.',
          'SpendWise will save the selected sheets as evidence, then reconcile them together.',
        ][step],
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: SpendWiseColors.textSecondary),
      ),
    ],
  );
  Widget _selectFile(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        initialValue: sourceLabel,
        decoration: const InputDecoration(labelText: 'Source / institution'),
        onChanged: (v) => sourceLabel = v.trim(),
      ),
      const SizedBox(height: 16),
      Semantics(
        button: true,
        label: selectedFile == null
            ? 'Choose CSV or Excel files. Supports multiple CSV, XLSX, and XLS files, read locally on this device.'
            : '${selectedFile!.fileName}, ${_selectedStates.length} worksheets selected',
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
                color: selectedFile == null
                    ? SpendWiseColors.border
                    : SpendWiseColors.accent,
              ),
            ),
            child: ExcludeSemantics(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selectedFile == null
                        ? Icons.upload_file_outlined
                        : Icons.check_circle_outline_rounded,
                    size: 38,
                    color: SpendWiseColors.accent,
                  ),
                  const SizedBox(height: 11),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Text(
                      selectedFile == null
                          ? 'Choose CSV or Excel files'
                          : '${selectedFile!.fileName} · ${_selectedStates.length} of ${sheetStates.length} sheets',
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
      if (selectedFile != null) ...[
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                'Worksheets',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              '${_selectedStates.length} selected',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final state in sheetStates.values) ...[
          _sheetSelectionCard(context, state),
          const SizedBox(height: 9),
        ],
      ],
      const SizedBox(height: 10),
      const PrivacyBanner(compact: true),
    ],
  );

  Widget _sheetSelectionCard(
    BuildContext context,
    _SheetImportState state,
  ) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            value: state.selected,
            enabled: state.importable,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Text(
              state.sheet.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              state.importable
                  ? '${state.rows.length} rows · ${state.sheet.accountInferenceReason}'
                  : state.error,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onChanged: state.importable
                ? (selected) => setState(() {
                    state.selected = selected ?? false;
                    preview = null;
                  })
                : null,
          ),
          if (state.selected && state.importable)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: DropdownButtonFormField<String>(
                key: ValueKey('${state.sheet.name}:${state.accountId}'),
                initialValue: state.accountId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Destination account',
                  helperText: state.sheet.accountInferenceConfidence >= .55
                      ? 'Suggested from statement details'
                      : 'Confirm where this sheet belongs',
                ),
                items: widget.viewModel.accounts
                    .map(
                      (account) => DropdownMenuItem(
                        value: account.id,
                        child: Text(
                          '${account.name} · ${account.currency}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: busy
                    ? null
                    : (accountId) => setState(() {
                        state.accountId = accountId;
                        preview = null;
                      }),
              ),
            ),
        ],
      ),
    ),
  );
  Widget _mapColumns(BuildContext context) => Column(
    children: [
      for (final indexed in _selectedStates.indexed) ...[
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            initiallyExpanded: indexed.$1 == 0,
            title: Text(
              indexed.$2.sheet.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${indexed.$2.rows.length} rows · ${_mappingValid(indexed.$2) ? 'Ready' : 'Needs mapping'}',
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  indexed.$2.headerRowIndex > 0
                      ? 'Transaction table found on row ${indexed.$2.headerRowIndex + 1}'
                      : 'Transaction headers detected',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: indexed.$2.headers
                      .map((header) => Chip(label: Text(header)))
                      .toList(growable: false),
                ),
              ),
              const SizedBox(height: 14),
              for (final field in _importFields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey(
                      '${indexed.$2.sheet.name}:${field.name}:${indexed.$2.mapping[field]}',
                    ),
                    initialValue: indexed.$2.mapping[field],
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: _fieldName(field),
                      helperText:
                          field == ImportField.date ||
                              field == ImportField.description
                          ? 'Required'
                          : null,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Not mapped'),
                      ),
                      ...indexed.$2.headers.map(
                        (header) => DropdownMenuItem<String?>(
                          value: header,
                          child: Text(header, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      if (value == null) {
                        indexed.$2.mapping.remove(field);
                      } else {
                        indexed.$2.mapping[field] = value;
                      }
                      preview = null;
                    }),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
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
                DataColumn(label: Text('Sheet')),
                DataColumn(label: Text('Account')),
                DataColumn(label: Text('Row')),
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Description')),
                DataColumn(label: Text('Category')),
                DataColumn(label: Text('Amount')),
                DataColumn(label: Text('Status')),
              ],
              rows: [
                for (final row in result.rows.take(25))
                  DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 90,
                          child: Text(
                            row.sheetName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(Text(row.accountName)),
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
                      DataCell(Text(row.category)),
                      DataCell(Text(row.amount)),
                      DataCell(
                        Text(
                          row.error ??
                              (row.duplicate
                                  ? row.duplicateReason.isEmpty
                                        ? 'Review duplicate'
                                        : row.duplicateReason
                                  : 'Valid'),
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
        if (!result.sameFileAlreadyImported && result.reimportedSheetCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '${result.reimportedSheetCount} previously imported ${result.reimportedSheetCount == 1 ? 'sheet was' : 'sheets were'} detected and will not be duplicated.',
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
                  '${_selectedStates.length} ${_selectedStates.length == 1 ? 'worksheet' : 'worksheets'} · ${preview?.duplicateCount ?? 0} possible duplicates',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Source: $sourceLabel',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Categories are inferred locally from descriptions. Unknown merchants remain in Other and can be corrected later.',
                  textAlign: TextAlign.center,
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
        0 =>
          selectedFile != null &&
              _selectedStates.isNotEmpty &&
              _selectedStates.every((state) => state.accountId != null),
        1 => _selectedStates.every(_mappingValid),
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
      _loadFile(file);
    } catch (error) {
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read statement: $error')),
      );
    }
  }

  void _loadFile(StatementFileViewData file) {
    final next = <String, _SheetImportState>{};
    for (final sheet in file.sheets) {
      if (!sheet.importable) {
        next[sheet.name] = _SheetImportState.unsupported(
          sheet,
          sheet.detectionError,
        );
        continue;
      }
      try {
        final detected = const StatementTableDetector().detect(sheet.csvText);
        final mapping = <ImportField, String>{};
        for (final header in detected.headers) {
          final field = _importFieldForHeader(header);
          if (field != null) mapping.putIfAbsent(field, () => header);
        }
        next[sheet.name] = _SheetImportState(
          sheet: sheet,
          headers: detected.headers,
          rows: detected.dataRows
              .map((row) => row.map((value) => '$value').toList())
              .toList(growable: false),
          headerRowIndex: detected.headerRowIndex,
          mapping: mapping,
          accountId:
              sheet.suggestedAccountId ??
              (widget.viewModel.accounts.length == 1
                  ? widget.viewModel.accounts.single.id
                  : null),
        );
      } on FormatException catch (error) {
        next[sheet.name] = _SheetImportState.unsupported(sheet, error.message);
      }
    }
    setState(() {
      selectedFile = file;
      sheetStates
        ..clear()
        ..addAll(next);
      preview = null;
      busy = false;
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
    csvText: _selectedStates.first.sheet.csvText,
    accountId: _selectedStates.first.accountId!,
    sourceLabel: sourceLabel.isEmpty ? 'Statement import' : sourceLabel,
    fileName: selectedFile?.fileName ?? 'statement.csv',
    mapping: Map.unmodifiable(_selectedStates.first.mapping),
    sheets: _selectedStates
        .map(
          (state) => StatementSheetImportDraft(
            sheetName: state.sheet.name,
            csvText: state.sheet.csvText,
            accountId: state.accountId!,
            mapping: Map.unmodifiable(state.mapping),
          ),
        )
        .toList(growable: false),
  );

  List<_SheetImportState> get _selectedStates => sheetStates.values
      .where((state) => state.selected && state.importable)
      .toList(growable: false);

  bool _mappingValid(_SheetImportState state) =>
      state.mapping.containsKey(ImportField.date) &&
      (state.mapping.containsKey(ImportField.description) ||
          state.mapping.containsKey(ImportField.merchant)) &&
      (state.mapping.containsKey(ImportField.amount) ||
          state.mapping.containsKey(ImportField.debit) ||
          state.mapping.containsKey(ImportField.credit));

  static ImportField? _importFieldForHeader(String header) =>
      switch (recognizeStatementHeader(header)) {
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

const _importFields = <ImportField>[
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
];

final class _SheetImportState {
  _SheetImportState({
    required this.sheet,
    required this.headers,
    required this.rows,
    required this.headerRowIndex,
    required this.mapping,
    required this.accountId,
  }) : selected = true,
       importable = true,
       error = '';

  _SheetImportState.unsupported(this.sheet, this.error)
    : headers = const [],
      rows = const [],
      headerRowIndex = 0,
      mapping = <ImportField, String>{},
      accountId = null,
      selected = false,
      importable = false;

  final StatementSheetViewData sheet;
  final List<String> headers;
  final List<List<String>> rows;
  final int headerRowIndex;
  final Map<ImportField, String> mapping;
  String? accountId;
  bool selected;
  final bool importable;
  final String error;
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
