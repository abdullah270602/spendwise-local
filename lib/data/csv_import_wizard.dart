import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';

import '../domain/domain.dart';
import 'local_ledger.dart';
import 'statement_table_detector.dart';

enum CsvColumnRole {
  date,
  description,
  debit,
  credit,
  amount,
  direction,
  balance,
  reference,
  merchant,
  currency,
  ignore,
}

enum CsvDateFormat {
  isoYearMonthDay,
  dayMonthYearSlash,
  dayMonthYearDash,
  monthDayYearSlash,
}

enum CsvAmountConvention { negativeIsDebit, positiveIsDebit }

final class CsvMappingDefinition {
  const CsvMappingDefinition({
    required this.roles,
    this.dateFormat = CsvDateFormat.isoYearMonthDay,
    this.amountConvention = CsvAmountConvention.negativeIsDebit,
    this.defaultCurrency = 'PKR',
  });

  final Map<int, CsvColumnRole> roles;
  final CsvDateFormat dateFormat;
  final CsvAmountConvention amountConvention;
  final String defaultCurrency;

  int? column(CsvColumnRole role) => roles.entries
      .where((entry) => entry.value == role)
      .map((entry) => entry.key)
      .firstOrNull;

  bool get isValid {
    final hasCore =
        column(CsvColumnRole.date) != null &&
        (column(CsvColumnRole.description) != null ||
            column(CsvColumnRole.merchant) != null);
    final hasAmount =
        column(CsvColumnRole.amount) != null ||
        column(CsvColumnRole.debit) != null ||
        column(CsvColumnRole.credit) != null;
    return hasCore && hasAmount;
  }

  Map<String, Object?> toJson() => {
    'roles': {
      for (final entry in roles.entries) '${entry.key}': entry.value.name,
    },
    'dateFormat': dateFormat.name,
    'amountConvention': amountConvention.name,
    'defaultCurrency': defaultCurrency,
  };

  static CsvMappingDefinition fromJson(Map<String, Object?> json) =>
      CsvMappingDefinition(
        roles: (json['roles'] as Map).map(
          (key, value) => MapEntry(
            int.parse('$key'),
            CsvColumnRole.values.byName('$value'),
          ),
        ),
        dateFormat: CsvDateFormat.values.byName('${json['dateFormat']}'),
        amountConvention: CsvAmountConvention.values.byName(
          '${json['amountConvention']}',
        ),
        defaultCurrency: json['defaultCurrency'] as String? ?? 'PKR',
      );
}

final class CsvInspection {
  const CsvInspection({
    required this.fileName,
    required this.fileSha256,
    required this.delimiter,
    required this.headers,
    required this.sampleRows,
    required this.headerFingerprint,
    required this.headerRowIndex,
    required this.suggestedMapping,
    required this.mappingWasRemembered,
  });

  final String fileName;
  final String fileSha256;
  final String delimiter;
  final List<String> headers;
  final List<List<String>> sampleRows;
  final String headerFingerprint;
  final int headerRowIndex;
  final CsvMappingDefinition suggestedMapping;
  final bool mappingWasRemembered;
}

final class CsvPreviewRow {
  const CsvPreviewRow({
    required this.rowNumber,
    required this.raw,
    this.occurredAt,
    this.description,
    this.direction,
    this.amount,
    this.reference,
    this.merchant,
    this.balanceMinor,
    this.dedupeFingerprint,
    this.probableDuplicate = false,
    this.error,
  });

  final int rowNumber;
  final Map<String, String> raw;
  final DateTime? occurredAt;
  final String? description;
  final EntryDirection? direction;
  final Money? amount;
  final String? reference;
  final String? merchant;
  final int? balanceMinor;
  final String? dedupeFingerprint;
  final bool probableDuplicate;
  final String? error;
  bool get valid =>
      error == null &&
      occurredAt != null &&
      direction != null &&
      amount != null;

  CsvPreviewRow copyWith({
    bool? probableDuplicate,
    String? dedupeFingerprint,
  }) => CsvPreviewRow(
    rowNumber: rowNumber,
    raw: raw,
    occurredAt: occurredAt,
    description: description,
    direction: direction,
    amount: amount,
    reference: reference,
    merchant: merchant,
    balanceMinor: balanceMinor,
    dedupeFingerprint: dedupeFingerprint ?? this.dedupeFingerprint,
    probableDuplicate: probableDuplicate ?? this.probableDuplicate,
    error: error,
  );
}

final class CsvImportPreview {
  const CsvImportPreview({
    required this.inspection,
    required this.mapping,
    required this.rows,
    required this.sameFileAlreadyImported,
  });

  final CsvInspection inspection;
  final CsvMappingDefinition mapping;
  final List<CsvPreviewRow> rows;
  final bool sameFileAlreadyImported;
  int get validCount => rows.where((row) => row.valid).length;
  int get errorCount => rows.where((row) => !row.valid).length;
  int get duplicateCount => rows.where((row) => row.probableDuplicate).length;

  CsvImportPreview copyWith({List<CsvPreviewRow>? rows}) => CsvImportPreview(
    inspection: inspection,
    mapping: mapping,
    rows: rows ?? this.rows,
    sameFileAlreadyImported: sameFileAlreadyImported,
  );
}

final class CsvCommitResult {
  const CsvCommitResult({
    required this.batchId,
    required this.imported,
    required this.errors,
    required this.duplicateCandidates,
    this.skippedAsExactReimport = false,
  });
  final String? batchId;
  final int imported;
  final int errors;
  final int duplicateCandidates;
  final bool skippedAsExactReimport;
}

final class CsvImportWizard {
  const CsvImportWizard(this.ledger);
  final LocalLedger ledger;

  CsvInspection inspect({
    required String fileName,
    required String text,
    required String accountId,
  }) {
    final normalized = text.startsWith('\ufeff') ? text.substring(1) : text;
    final detected = const StatementTableDetector().detect(normalized);
    final headers = detected.headers;
    final fingerprint = sha256
        .convert(utf8.encode(headers.map(_normalizeHeader).join('|')))
        .toString();
    final remembered = ledger.rememberedCsvMapping(
      accountId: accountId,
      headerFingerprint: fingerprint,
    );
    final suggested = remembered == null
        ? _suggest(headers)
        : CsvMappingDefinition.fromJson(
            Map<String, Object?>.from(remembered['mapping']! as Map),
          );
    return CsvInspection(
      fileName: fileName,
      fileSha256: sha256.convert(utf8.encode(normalized)).toString(),
      delimiter: detected.delimiter,
      headers: headers,
      sampleRows: detected.dataRows
          .take(20)
          .map((row) => row.map((value) => '$value').toList(growable: false))
          .toList(growable: false),
      headerFingerprint: fingerprint,
      headerRowIndex: detected.headerRowIndex,
      suggestedMapping: suggested,
      mappingWasRemembered: remembered != null,
    );
  }

  CsvImportPreview preview({
    required CsvInspection inspection,
    required String text,
    required String accountId,
    required CsvMappingDefinition mapping,
  }) {
    if (!mapping.isValid) {
      throw const FormatException(
        'Map date, description/merchant, and amount columns.',
      );
    }
    final normalized = text.startsWith('\ufeff') ? text.substring(1) : text;
    final decoded = Csv(
      fieldDelimiter: inspection.delimiter,
      autoDetect: false,
    ).decode(normalized);
    final rows = <CsvPreviewRow>[];
    final fingerprintOccurrences = <String, int>{};
    for (
      var index = inspection.headerRowIndex + 1;
      index < decoded.length;
      index++
    ) {
      final rawRow = decoded[index];
      final raw = {
        for (var column = 0; column < inspection.headers.length; column++)
          inspection.headers[column]: column < rawRow.length
              ? '${rawRow[column]}'
              : '',
      };
      try {
        final parsed = _normalizeRow(
          rowNumber: index + 1,
          values: rawRow,
          headers: inspection.headers,
          mapping: mapping,
        );
        final duplicateBase = _duplicateFingerprintBase(
          accountId: accountId,
          row: parsed,
        );
        final occurrence = duplicateBase == null
            ? null
            : (fingerprintOccurrences[duplicateBase] ?? 0) + 1;
        if (duplicateBase != null) {
          fingerprintOccurrences[duplicateBase] = occurrence!;
        }
        final dedupeFingerprint = duplicateBase == null
            ? null
            : sha256
                  .convert(utf8.encode('$duplicateBase|$occurrence'))
                  .toString();
        rows.add(
          CsvPreviewRow(
            rowNumber: parsed.rowNumber,
            raw: raw,
            occurredAt: parsed.occurredAt,
            description: parsed.description,
            direction: parsed.direction,
            amount: parsed.amount,
            reference: parsed.reference,
            merchant: parsed.merchant,
            balanceMinor: parsed.balanceMinor,
            dedupeFingerprint: dedupeFingerprint,
            probableDuplicate: ledger.probableEvidenceDuplicate(
              accountId: accountId,
              direction: parsed.direction!,
              amount: parsed.amount!,
              occurredAt: parsed.occurredAt!,
              description: parsed.description!,
              reference: parsed.reference,
              balanceMinor: parsed.balanceMinor,
              dedupeFingerprint: dedupeFingerprint,
            ),
          ),
        );
      } on FormatException catch (error) {
        rows.add(
          CsvPreviewRow(rowNumber: index + 1, raw: raw, error: error.message),
        );
      }
    }
    return CsvImportPreview(
      inspection: inspection,
      mapping: mapping,
      rows: rows,
      sameFileAlreadyImported: ledger.wasFileImported(
        fileSha256: inspection.fileSha256,
        accountId: accountId,
      ),
    );
  }

  CsvCommitResult commit({
    required CsvImportPreview preview,
    required String accountId,
    String? sourceId,
    String mappingName = 'Statement format',
    bool reconcile = true,
  }) {
    if (preview.sameFileAlreadyImported) {
      return CsvCommitResult(
        batchId: null,
        imported: 0,
        errors: 0,
        duplicateCandidates: preview.duplicateCount,
        skippedAsExactReimport: true,
      );
    }
    final mappingId = ledger.rememberCsvMapping(
      name: mappingName,
      accountId: accountId,
      headerFingerprint: preview.inspection.headerFingerprint,
      delimiter: preview.inspection.delimiter,
      mapping: preview.mapping.toJson(),
      dateFormat: preview.mapping.dateFormat.name,
      amountSignConvention: preview.mapping.amountConvention.name,
    );
    final batchId = ledger.createImportBatch(
      fileName: preview.inspection.fileName,
      fileSha256: preview.inspection.fileSha256,
      accountId: accountId,
      sourceId: sourceId,
      mappingId: mappingId,
      mapping: preview.mapping.toJson(),
      rowCount: preview.rows.length,
    );
    var imported = 0;
    for (final row in preview.rows) {
      if (!row.valid) {
        ledger.recordImportRow(
          batchId: batchId,
          rowNumber: row.rowNumber,
          raw: row.raw,
          status: 'error',
          errorMessage: row.error,
        );
        continue;
      }
      final observationId = ledger.ingestCsvCandidate(
        batchId: preview.inspection.fileSha256,
        rowNumber: row.rowNumber,
        accountId: accountId,
        direction: row.direction!,
        amount: row.amount!,
        occurredAt: row.occurredAt!,
        description: row.description!,
        reference: row.reference,
        balanceMinor: row.balanceMinor,
        dedupeFingerprint: row.dedupeFingerprint,
        sourceId: sourceId,
      );
      if (observationId != null) imported++;
      ledger.recordImportRow(
        batchId: batchId,
        rowNumber: row.rowNumber,
        raw: row.raw,
        status: row.probableDuplicate ? 'duplicateCandidate' : 'imported',
        normalized: {
          'occurredAt': row.occurredAt!.toIso8601String(),
          'direction': row.direction!.name,
          'amountMinor': row.amount!.minorUnits,
          'currency': row.amount!.currency,
          'description': row.description,
          'merchant': row.merchant,
          'reference': row.reference,
          'balanceMinor': row.balanceMinor,
        },
        rawObservationId: observationId,
      );
    }
    if (reconcile) ledger.finishBatch();
    ledger.finishImportBatch(
      batchId: batchId,
      importedCount: imported,
      errorCount: preview.errorCount,
      duplicateCount: preview.duplicateCount,
    );
    return CsvCommitResult(
      batchId: batchId,
      imported: imported,
      errors: preview.errorCount,
      duplicateCandidates: preview.duplicateCount,
    );
  }

  String? _duplicateFingerprintBase({
    required String accountId,
    required CsvPreviewRow row,
  }) {
    if (!row.valid) return null;
    final description = CategoryClassifier.normalize(
      row.description ?? row.merchant ?? '',
    );
    if (description.isEmpty) return null;
    final reference = CategoryClassifier.normalize(row.reference ?? '');
    if (reference.isEmpty && row.balanceMinor == null) return null;
    final date = row.occurredAt!.toUtc().toIso8601String().split('T').first;
    return [
      accountId,
      date,
      row.direction!.name,
      row.amount!.currency,
      row.amount!.minorUnits,
      description,
      if (reference.isNotEmpty) 'reference:$reference',
      if (row.balanceMinor != null) 'balance:${row.balanceMinor}',
    ].join('|');
  }

  CsvPreviewRow _normalizeRow({
    required int rowNumber,
    required List<Object?> values,
    required List<String> headers,
    required CsvMappingDefinition mapping,
  }) {
    String cell(CsvColumnRole role) {
      final column = mapping.column(role);
      return column == null || column >= values.length
          ? ''
          : '${values[column]}'.trim();
    }

    final date = _parseDate(cell(CsvColumnRole.date), mapping.dateFormat);
    if (date == null) {
      throw const FormatException('Invalid or unsupported date.');
    }
    final merchant = cell(CsvColumnRole.merchant);
    final narrative = cell(CsvColumnRole.description);
    final description = [
      merchant,
      narrative,
    ].where((value) => value.isNotEmpty).toSet().join(' — ');
    if (description.isEmpty) {
      throw const FormatException('Description is empty.');
    }
    final debit = cell(CsvColumnRole.debit);
    final credit = cell(CsvColumnRole.credit);
    EntryDirection direction;
    Money? amount;
    if (debit.isNotEmpty && credit.isNotEmpty) {
      throw const FormatException('Both debit and credit are populated.');
    } else if (debit.isNotEmpty) {
      direction = EntryDirection.debit;
      amount = _parseMoney(debit, mapping.defaultCurrency)?.absolute;
    } else if (credit.isNotEmpty) {
      direction = EntryDirection.credit;
      amount = _parseMoney(credit, mapping.defaultCurrency)?.absolute;
    } else {
      final signed = _parseMoney(
        cell(CsvColumnRole.amount),
        mapping.defaultCurrency,
      );
      if (signed == null || signed.isZero) {
        throw const FormatException('Amount is missing or invalid.');
      }
      final negativeMeansDebit =
          mapping.amountConvention == CsvAmountConvention.negativeIsDebit;
      direction = signed.isNegative == negativeMeansDebit
          ? EntryDirection.debit
          : EntryDirection.credit;
      final explicit = cell(CsvColumnRole.direction).toLowerCase();
      if (explicit.isNotEmpty) {
        if (RegExp(r'^(debit|dr|out|withdrawal)$').hasMatch(explicit)) {
          direction = EntryDirection.debit;
        } else if (RegExp(r'^(credit|cr|in|deposit)$').hasMatch(explicit)) {
          direction = EntryDirection.credit;
        } else {
          throw const FormatException('Unrecognized transaction direction.');
        }
      }
      amount = signed.absolute;
    }
    if (amount == null || amount.isZero) {
      throw const FormatException('Amount is missing, zero, or invalid.');
    }
    final balance = _parseMoney(
      cell(CsvColumnRole.balance),
      mapping.defaultCurrency,
    );
    return CsvPreviewRow(
      rowNumber: rowNumber,
      raw: {
        for (var index = 0; index < headers.length; index++)
          headers[index]: index < values.length ? '${values[index]}' : '',
      },
      occurredAt: date,
      description: description,
      direction: direction,
      amount: amount,
      reference: cell(CsvColumnRole.reference).nullIfEmpty,
      merchant: merchant.nullIfEmpty,
      balanceMinor: balance?.minorUnits,
    );
  }

  CsvMappingDefinition _suggest(List<String> headers) {
    final roles = <int, CsvColumnRole>{};
    for (var index = 0; index < headers.length; index++) {
      final role = switch (recognizeStatementHeader(headers[index])) {
        StatementColumnKind.date => CsvColumnRole.date,
        StatementColumnKind.description => CsvColumnRole.description,
        StatementColumnKind.merchant => CsvColumnRole.merchant,
        StatementColumnKind.debit => CsvColumnRole.debit,
        StatementColumnKind.credit => CsvColumnRole.credit,
        StatementColumnKind.amount => CsvColumnRole.amount,
        StatementColumnKind.direction => CsvColumnRole.direction,
        StatementColumnKind.balance => CsvColumnRole.balance,
        StatementColumnKind.reference => CsvColumnRole.reference,
        StatementColumnKind.currency => CsvColumnRole.currency,
        StatementColumnKind.unknown => CsvColumnRole.ignore,
      };
      roles[index] = role;
    }
    return CsvMappingDefinition(roles: roles);
  }

  Money? _parseMoney(String value, String currency) {
    var normalized = value.trim().replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) return null;
    final parentheses = normalized.startsWith('(') && normalized.endsWith(')');
    if (parentheses) {
      normalized = '-${normalized.substring(1, normalized.length - 1)}';
    }
    normalized = normalized
        .replaceAll(RegExp(r'^(PKR|Rs\.?|₨)', caseSensitive: false), '')
        .replaceAll(',', '');
    final match = RegExp(r'^([+-]?)(\d+)(?:\.(\d{1,2}))?$')
        .firstMatch(normalized);
    if (match == null) return null;
    final whole = int.tryParse(match.group(2)!);
    if (whole == null) return null;
    final fraction = int.parse(
      (match.group(3) ?? '').padRight(2, '0').ifEmpty('0'),
    );
    final sign = match.group(1) == '-' ? -1 : 1;
    return Money(
      minorUnits: sign * (whole * 100 + fraction),
      currency: currency.toUpperCase(),
    );
  }

  DateTime? _parseDate(String value, CsvDateFormat format) {
    final pattern = switch (format) {
      CsvDateFormat.isoYearMonthDay => RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$'),
      CsvDateFormat.dayMonthYearSlash || CsvDateFormat.monthDayYearSlash =>
        RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$'),
      CsvDateFormat.dayMonthYearDash => RegExp(
        r'^(\d{1,2})-(\d{1,2})-(\d{4})$',
      ),
    };
    final match = pattern.firstMatch(value.trim());
    if (match == null) return null;
    late int year, month, day;
    if (format == CsvDateFormat.isoYearMonthDay) {
      year = int.parse(match.group(1)!);
      month = int.parse(match.group(2)!);
      day = int.parse(match.group(3)!);
    } else {
      year = int.parse(match.group(3)!);
      final first = int.parse(match.group(1)!);
      final second = int.parse(match.group(2)!);
      month = format == CsvDateFormat.monthDayYearSlash ? first : second;
      day = format == CsvDateFormat.monthDayYearSlash ? second : first;
    }
    final parsed = DateTime.utc(year, month, day);
    return parsed.year == year && parsed.month == month && parsed.day == day
        ? parsed
        : null;
  }

  String _normalizeHeader(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

extension on String {
  String? get nullIfEmpty => trim().isEmpty ? null : trim();
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
