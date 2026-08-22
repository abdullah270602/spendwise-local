import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/csv_import_wizard.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/data/statement_file_decoder.dart';
import 'package:spendwise/domain/domain.dart';

void main() {
  test('decodes every non-empty Excel worksheet into importable CSV', () async {
    final workbook = Excel.createExcel();
    workbook.rename(workbook.getDefaultSheet() ?? 'Sheet1', 'Current');
    workbook['Current']
      ..appendRow([
        TextCellValue('Date'),
        TextCellValue('Description'),
        TextCellValue('Debit'),
        TextCellValue('Reference'),
      ])
      ..appendRow([
        TextCellValue('2026-08-20'),
        TextCellValue('Groceries, weekly'),
        DoubleCellValue(1500.50),
        TextCellValue('TX-1'),
      ]);
    workbook['Savings']
      ..appendRow([
        TextCellValue('Date'),
        TextCellValue('Description'),
        TextCellValue('Credit'),
      ])
      ..appendRow([
        DateCellValue(year: 2026, month: 8, day: 21),
        TextCellValue('Profit'),
        IntCellValue(250),
      ]);
    workbook['Empty'];

    final decoded = await const StatementFileDecoder().decode(
      fileName: 'bank-statement.xlsx',
      bytes: workbook.save()!,
    );

    expect(decoded.fileName, 'bank-statement.xlsx');
    expect(decoded.sheets.map((sheet) => sheet.name), ['Current', 'Savings']);
    expect(decoded.sheets.first.csvText, contains('"Groceries, weekly"'));
    expect(decoded.sheets.last.csvText, contains('2026-08-21'));
  });

  test(
    'an Excel worksheet completes the existing preview and commit flow',
    () async {
      final workbook = Excel.createExcel();
      final sheet = workbook[workbook.getDefaultSheet() ?? 'Sheet1'];
      sheet
        ..appendRow([TextCellValue('UBL Account Statement')])
        ..appendRow([
          TextCellValue('Account title'),
          TextCellValue('Sample customer'),
        ])
        ..appendRow([
          TextCellValue('Statement period'),
          TextCellValue('August 2026'),
        ])
        ..appendRow([])
        ..appendRow([
          TextCellValue('Transaction Date'),
          TextCellValue('Transaction Remarks'),
          TextCellValue('Withdrawal Amount'),
          TextCellValue('Instrument ID'),
        ])
        ..appendRow([
          TextCellValue('2026-08-20'),
          TextCellValue('Foodpanda'),
          IntCellValue(4250),
          TextCellValue('FP-42'),
        ]);
      final decoded = await const StatementFileDecoder().decode(
        fileName: 'statement.xlsx',
        bytes: workbook.save()!,
      );
      final ledger = LocalLedger.openInMemoryForTests();
      addTearDown(ledger.close);
      final accountId = ledger.addAccount(
        name: 'Current',
        type: AccountType.bank,
      );
      final wizard = CsvImportWizard(ledger);
      final text = decoded.sheets.single.csvText;
      final inspection = wizard.inspect(
        fileName: decoded.fileName,
        text: text,
        accountId: accountId,
      );
      final preview = wizard.preview(
        inspection: inspection,
        text: text,
        accountId: accountId,
        mapping: inspection.suggestedMapping,
      );

      expect(inspection.headerRowIndex, 3);
      expect(inspection.headers, contains('Transaction Remarks'));
      expect(preview.validCount, 1);
      expect(preview.rows.single.rowNumber, 5);
      expect(preview.rows.single.amount?.minorUnits, 425000);
      final result = wizard.commit(preview: preview, accountId: accountId);
      expect(result.imported, 1);
      expect(ledger.snapshot().transactions, hasLength(1));
    },
  );

  test('rejects unsupported and oversized statement files clearly', () async {
    const decoder = StatementFileDecoder();
    await expectLater(
      decoder.decode(fileName: 'statement.pdf', bytes: [1, 2, 3]),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      decoder.decode(
        fileName: 'statement.xlsx',
        bytes: List.filled(StatementFileDecoder.maxFileBytes + 1, 0),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'combines multiple workbooks and disambiguates repeated sheet names',
    () async {
      List<int> workbookBytes(String description) {
        final workbook = Excel.createExcel();
        workbook[workbook.getDefaultSheet() ?? 'Sheet1']
          ..appendRow([
            TextCellValue('Date'),
            TextCellValue('Description'),
            TextCellValue('Debit'),
          ])
          ..appendRow([
            TextCellValue('2026-08-20'),
            TextCellValue(description),
            IntCellValue(100),
          ]);
        return workbook.save()!;
      }

      final decoded = await const StatementFileDecoder().decodeMany([
        StatementFileInput(
          fileName: 'year-one.xlsx',
          bytes: workbookBytes('First year'),
        ),
        StatementFileInput(
          fileName: 'year-two.xlsx',
          bytes: workbookBytes('Second year'),
        ),
      ]);

      expect(decoded.fileName, '2 statement files');
      expect(decoded.sheets, hasLength(2));
      expect(decoded.sheets.map((sheet) => sheet.name), [
        'year-one.xlsx · Sheet1',
        'year-two.xlsx · Sheet1',
      ]);
    },
  );
}
