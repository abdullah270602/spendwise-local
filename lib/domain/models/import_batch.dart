enum ImportBatchStatus { staged, imported, partiallyImported, rejected }

final class ImportColumnMapping {
  const ImportColumnMapping({
    required this.dateColumn,
    required this.descriptionColumn,
    this.amountColumn,
    this.debitColumn,
    this.creditColumn,
    this.referenceColumn,
    this.dateFormat,
  });

  final String dateColumn;
  final String descriptionColumn;
  final String? amountColumn;
  final String? debitColumn;
  final String? creditColumn;
  final String? referenceColumn;
  final String? dateFormat;
}

final class ImportBatch {
  const ImportBatch({
    required this.id,
    required this.accountId,
    required this.fileName,
    required this.fileDigest,
    required this.createdAt,
    required this.mapping,
    this.status = ImportBatchStatus.staged,
  });

  final String id;
  final String accountId;
  final String fileName;
  final String fileDigest;
  final DateTime createdAt;
  final ImportColumnMapping mapping;
  final ImportBatchStatus status;
}

final class ImportRow {
  const ImportRow({
    required this.batchId,
    required this.rowNumber,
    required this.values,
    this.error,
    this.observationId,
  });

  final String batchId;
  final int rowNumber;
  final Map<String, String> values;
  final String? error;
  final String? observationId;
}
