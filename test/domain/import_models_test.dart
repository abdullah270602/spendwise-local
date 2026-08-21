import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/domain.dart';

void main() {
  test('import batch retains explicit reproducible mapping', () {
    const mapping = ImportColumnMapping(
      dateColumn: 'Value Date',
      descriptionColumn: 'Narration',
      debitColumn: 'Debit',
      creditColumn: 'Credit',
      referenceColumn: 'Reference',
      dateFormat: 'dd/MM/yyyy',
    );
    final batch = ImportBatch(
      id: 'batch:sanitized',
      accountId: 'account:sample',
      fileName: 'statement.csv',
      fileDigest: 'sanitized-digest',
      createdAt: DateTime.utc(2026, 8, 21),
      mapping: mapping,
    );
    expect(batch.mapping.referenceColumn, 'Reference');
    expect(batch.status, ImportBatchStatus.staged);
  });
}
