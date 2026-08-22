import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/csv_import_wizard.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

void main() {
  late LocalLedger ledger;
  late CsvImportWizard wizard;
  late String accountId;

  setUp(() {
    ledger = LocalLedger.openInMemoryForTests();
    wizard = CsvImportWizard(ledger);
    accountId = ledger.addAccount(
      name: 'Meezan Current',
      type: AccountType.bank,
    );
  });

  tearDown(() => ledger.close());

  test(
    'inspects, maps, previews, and commits a normal debit/credit statement',
    () {
      const text = '''Txn Date,Details,Debit,Credit,Running Balance,Ref No.
20/08/2026,FOODPANDA,4250.00,,95750.00,TXN-1001
21/08/2026,SALARY,,152600.00,248350.00,TXN-1002
''';
      final inspection = wizard.inspect(
        fileName: 'meezan.csv',
        text: text,
        accountId: accountId,
      );
      final mapping = CsvMappingDefinition(
        roles: inspection.suggestedMapping.roles,
        dateFormat: CsvDateFormat.dayMonthYearSlash,
      );
      final preview = wizard.preview(
        inspection: inspection,
        text: text,
        accountId: accountId,
        mapping: mapping,
      );
      expect(preview.validCount, 2);
      expect(preview.errorCount, 0);
      expect(preview.rows.first.direction, EntryDirection.debit);
      expect(preview.rows.last.direction, EntryDirection.credit);
      expect(preview.rows.first.balanceMinor, 9575000);

      final result = wizard.commit(preview: preview, accountId: accountId);
      expect(result.imported, 2);
      expect(ledger.snapshot().transactions, hasLength(2));
    },
  );

  test('finds a bank transaction table below statement metadata', () {
    const text = '''UBL Account Statement
Account Title;Sample Customer
Account Number;00001234
Statement Period;August 2026

Transaction Date;Value Date;Transaction Remarks;Withdrawal Amount;Deposit Amount;Available Balance;Instrument ID
20/08/2026;20/08/2026;CARD PURCHASE;1500.50;;98500.50;TX-1
21/08/2026;21/08/2026;SALARY;;50000;148500.50;TX-2
''';
    final inspection = wizard.inspect(
      fileName: 'bank-export.csv',
      text: text,
      accountId: accountId,
    );
    final mapping = CsvMappingDefinition(
      roles: inspection.suggestedMapping.roles,
      dateFormat: CsvDateFormat.dayMonthYearSlash,
    );
    final preview = wizard.preview(
      inspection: inspection,
      text: text,
      accountId: accountId,
      mapping: mapping,
    );

    expect(inspection.delimiter, ';');
    expect(inspection.headerRowIndex, 4);
    expect(inspection.suggestedMapping.column(CsvColumnRole.date), 0);
    expect(inspection.suggestedMapping.column(CsvColumnRole.description), 2);
    expect(inspection.suggestedMapping.column(CsvColumnRole.debit), 3);
    expect(inspection.suggestedMapping.column(CsvColumnRole.credit), 4);
    expect(inspection.suggestedMapping.column(CsvColumnRole.balance), 5);
    expect(inspection.suggestedMapping.column(CsvColumnRole.reference), 6);
    expect(preview.validCount, 2);
    expect(preview.rows.first.rowNumber, 6);
    expect(preview.rows.first.amount?.minorUnits, 150050);
  });

  test('supports a single signed amount column and explicit direction', () {
    const text = '''Date,Description,Amount,Direction,Reference
2026-08-20,Coffee,-450.50,debit,C-1
2026-08-21,Refund,+450.50,credit,C-2
''';
    final inspection = wizard.inspect(
      fileName: 'signed.csv',
      text: text,
      accountId: accountId,
    );
    final preview = wizard.preview(
      inspection: inspection,
      text: text,
      accountId: accountId,
      mapping: inspection.suggestedMapping,
    );
    expect(preview.validCount, 2);
    expect(preview.rows.first.amount!.minorUnits, 45050);
    expect(preview.rows.first.direction, EntryDirection.debit);
  });

  test('maps the exact Meezan workbook headers including document number', () {
    const text = '''Booking Date,Value Date,Doc No,Description,Debit,Credit,Available Balance
2026-08-20,2026-08-20,DOC-42,ONLINE PURCHASE FOOD PANDA,4250,,95750
''';
    final inspection = wizard.inspect(
      fileName: 'meezan.xlsx · Sheet1',
      text: text,
      accountId: accountId,
    );
    final preview = wizard.preview(
      inspection: inspection,
      text: text,
      accountId: accountId,
      mapping: inspection.suggestedMapping,
    );

    expect(inspection.suggestedMapping.column(CsvColumnRole.date), 0);
    expect(inspection.suggestedMapping.column(CsvColumnRole.reference), 2);
    expect(preview.validCount, 1);
    expect(preview.rows.single.reference, 'DOC-42');
  });

  test('retains malformed rows as preview errors while valid rows remain importable', () {
    const text = '''Date,Description,Debit,Credit
31/02/2026,Impossible,100,
20/08/2026,Both,100,100
21/08/2026,Valid,250,
''';
    final inspection = wizard.inspect(
      fileName: 'mixed.csv',
      text: text,
      accountId: accountId,
    );
    final mapping = CsvMappingDefinition(
      roles: inspection.suggestedMapping.roles,
      dateFormat: CsvDateFormat.dayMonthYearSlash,
    );
    final preview = wizard.preview(
      inspection: inspection,
      text: text,
      accountId: accountId,
      mapping: mapping,
    );
    expect(preview.validCount, 1);
    expect(preview.errorCount, 2);
    final result = wizard.commit(preview: preview, accountId: accountId);
    expect(result.imported, 1);
    expect(result.errors, 2);
  });

  test('exact same file and account is idempotent', () {
    const text = '''Date,Description,Debit,Reference
2026-08-20,Groceries,1000,R-1
''';
    final inspection = wizard.inspect(
      fileName: 'same.csv',
      text: text,
      accountId: accountId,
    );
    final preview = wizard.preview(
      inspection: inspection,
      text: text,
      accountId: accountId,
      mapping: inspection.suggestedMapping,
    );
    wizard.commit(preview: preview, accountId: accountId);

    final again = wizard.preview(
      inspection: inspection,
      text: text,
      accountId: accountId,
      mapping: inspection.suggestedMapping,
    );
    expect(again.sameFileAlreadyImported, isTrue);
    final result = wizard.commit(preview: again, accountId: accountId);
    expect(result.skippedAsExactReimport, isTrue);
    expect(ledger.snapshot().transactions, hasLength(1));
  });

  test(
    'overlapping export flags and reconciles an existing referenced row',
    () {
      const first = '''Date,Description,Debit,Reference
2026-08-20,FOODPANDA,4250,FP-42
''';
      const overlap = '''Date,Description,Debit,Reference
2026-08-20,FOODPANDA,4250,FP-42
2026-08-21,FUEL,6000,F-9
''';
      final firstInspection = wizard.inspect(
        fileName: 'week1.csv',
        text: first,
        accountId: accountId,
      );
      final firstPreview = wizard.preview(
        inspection: firstInspection,
        text: first,
        accountId: accountId,
        mapping: firstInspection.suggestedMapping,
      );
      wizard.commit(preview: firstPreview, accountId: accountId);

      final secondInspection = wizard.inspect(
        fileName: 'week2.csv',
        text: overlap,
        accountId: accountId,
      );
      final secondPreview = wizard.preview(
        inspection: secondInspection,
        text: overlap,
        accountId: accountId,
        mapping: secondInspection.suggestedMapping,
      );
      expect(secondPreview.duplicateCount, 1);
      wizard.commit(preview: secondPreview, accountId: accountId);
      expect(ledger.snapshot().transactions, hasLength(2));
    },
  );
}
