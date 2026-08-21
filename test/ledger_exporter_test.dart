import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/ledger_exporter.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

void main() {
  test('plaintext exports honor the evidence switch', () {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    final account = ledger.addAccount(name: 'Daily', type: AccountType.bank);
    ledger.addManualTransaction(
      kind: TransactionKind.expense,
      amountMinor: 12500,
      occurredAt: DateTime.utc(2026, 8, 22, 15),
      accountId: account,
      description: 'Cinema',
    );
    final exporter = LedgerExporter(ledger);

    final safeCsv = utf8.decode(exporter.csv(const LedgerExportFilter()));
    final evidenceCsv = utf8.decode(
      exporter.csv(const LedgerExportFilter(includeEvidence: true)),
    );
    expect(safeCsv, isNot(contains('Evidence (JSON)')));
    expect(evidenceCsv, contains('Evidence (JSON)'));

    final safeJson = jsonDecode(
      utf8.decode(exporter.jsonBackup(const LedgerExportFilter())),
    ) as Map<String, Object?>;
    final evidenceJson = jsonDecode(
      utf8.decode(
        exporter.jsonBackup(const LedgerExportFilter(includeEvidence: true)),
      ),
    ) as Map<String, Object?>;
    final safeTransaction = (safeJson['transactions'] as List).single as Map;
    final evidenceTransaction =
        (evidenceJson['transactions'] as List).single as Map;
    expect(safeTransaction, isNot(contains('evidence')));
    expect(safeTransaction, contains('evidenceCount'));
    expect(evidenceTransaction, contains('evidence'));
  });

  test('an exclusive next-day boundary includes the selected end day', () {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    final account = ledger.addAccount(name: 'Daily', type: AccountType.bank);
    ledger.addManualTransaction(
      kind: TransactionKind.expense,
      amountMinor: 500,
      occurredAt: DateTime.utc(2026, 8, 22, 23, 59),
      accountId: account,
      description: 'Late purchase',
    );
    final json = jsonDecode(
      utf8.decode(
        LedgerExporter(ledger)
            .jsonBackup(LedgerExportFilter(to: DateTime.utc(2026, 8, 23))),
      ),
    ) as Map<String, Object?>;
    expect(json['transactions'], hasLength(1));
  });
}
