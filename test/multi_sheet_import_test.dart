import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/spendwise_controller.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart' as domain;
import 'package:spendwise/features/shell/spendwise_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'previews and reconciles all sheets with cross-sheet duplicates',
    () async {
      final ledger = LocalLedger.openInMemoryForTests();
      addTearDown(ledger.close);
      final bank = ledger.addAccount(
        name: 'Meezan Current',
        type: domain.AccountType.bank,
        institutionName: 'Meezan Bank',
        accountSuffix: '4821',
      );
      final wallet = ledger.addAccount(
        name: 'NayaPay',
        type: domain.AccountType.wallet,
        institutionName: 'NayaPay',
        accountSuffix: '9012',
      );
      final controller = SpendWiseController.forTests(ledger);
      addTearDown(controller.dispose);
      const mapping = {
        ImportField.date: 'Date',
        ImportField.description: 'Description',
        ImportField.debit: 'Debit',
        ImportField.credit: 'Credit',
        ImportField.balance: 'Balance',
        ImportField.reference: 'Reference',
      };
      const bankPrimary = '''Date,Description,Debit,Credit,Balance,Reference
2026-08-20,FOODPANDA,4250,,95750,TX-100
2026-08-21,NETFLIX.COM,1500,,94250,TX-101
''';
      const bankOverlap = '''Date,Description,Debit,Credit,Balance,Reference
2026-08-20,FOODPANDA,4250,,95750,TX-100
2026-08-22,CITY PHARMACY,750,,93500,TX-102
''';
      const walletSheet = '''Date,Description,Debit,Credit,Balance,Reference
2026-08-20,Received from Meezan,,4250,14250,TX-100
''';
      final draft = CsvImportDraft(
        csvText: bankPrimary,
        accountId: bank,
        mapping: mapping,
        fileName: 'august.xlsx',
        sheets: [
          StatementSheetImportDraft(
            sheetName: 'Meezan August',
            csvText: bankPrimary,
            accountId: bank,
            mapping: mapping,
          ),
          StatementSheetImportDraft(
            sheetName: 'Meezan overlap',
            csvText: bankOverlap,
            accountId: bank,
            mapping: mapping,
          ),
          StatementSheetImportDraft(
            sheetName: 'NayaPay',
            csvText: walletSheet,
            accountId: wallet,
            mapping: mapping,
          ),
        ],
      );

      final preview = await controller.previewCsvImport(draft);

      expect(preview.sheetCount, 3);
      expect(preview.validCount, 5);
      expect(preview.duplicateCount, 1);
      expect(
        preview.rows.where((row) => row.duplicate).single.duplicateReason,
        contains('another selected sheet'),
      );
      expect(
        preview.rows
            .where((row) => row.description.contains('NETFLIX'))
            .single
            .category,
        'Entertainment',
      );
      expect(
        preview.rows
            .where((row) => row.description.contains('PHARMACY'))
            .single
            .category,
        'Health & medical',
      );

      await controller.commitCsvImport(draft);

      final snapshot = ledger.snapshot();
      expect(snapshot.transactions, hasLength(3));
      expect(
        snapshot.transactions.where(
          (transaction) => transaction.kind == domain.TransactionKind.transfer,
        ),
        hasLength(1),
      );
      expect(
        ledger.transactionCategories().values,
        containsAll(['Entertainment', 'Health & medical', 'Transfer']),
      );

      final secondPreview = await controller.previewCsvImport(draft);
      expect(secondPreview.reimportedSheetCount, 3);
      expect(secondPreview.sameFileAlreadyImported, isTrue);
      await controller.commitCsvImport(draft);
      expect(ledger.snapshot().transactions, hasLength(3));
    },
  );
}
