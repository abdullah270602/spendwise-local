import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';

import '../core/money.dart';
import '../domain/models/event_candidate.dart';
import 'local_ledger.dart';

final class CsvImportResult {
  const CsvImportResult({required this.imported, required this.errors});
  final int imported;
  final List<String> errors;
}

/// Conservative statement importer for common date/description/debit/credit
/// and signed-amount CSV exports. Ambiguous rows are retained as errors instead
/// of silently guessing direction or dates.
final class CsvImporter {
  const CsvImporter(this.ledger);
  final LocalLedger ledger;

  CsvImportResult import(String text, {required String accountId}) {
    final normalized = text.startsWith('\ufeff') ? text.substring(1) : text;
    final rows = Csv().decode(normalized);
    if (rows.length < 2) {
      return const CsvImportResult(
        imported: 0,
        errors: ['The CSV has no data rows.'],
      );
    }
    final headers = rows.first.map((value) => _header('$value')).toList();
    final dateIndex = _find(headers, const [
      'date',
      'transactiondate',
      'valuedate',
    ]);
    final descriptionIndex = _find(headers, const [
      'description',
      'details',
      'narration',
      'merchant',
      'memo',
    ]);
    final amountIndex = _find(headers, const ['amount', 'transactionamount']);
    final debitIndex = _find(headers, const [
      'debit',
      'withdrawal',
      'moneyout',
    ]);
    final creditIndex = _find(headers, const ['credit', 'deposit', 'moneyin']);
    final referenceIndex = _find(headers, const [
      'reference',
      'ref',
      'transactionid',
      'txnref',
    ]);
    if (dateIndex < 0 ||
        descriptionIndex < 0 ||
        (amountIndex < 0 && debitIndex < 0 && creditIndex < 0)) {
      return const CsvImportResult(
        imported: 0,
        errors: [
          'Required columns: date, description, and amount (or debit/credit).',
        ],
      );
    }
    final batchId = sha256.convert(utf8.encode(normalized)).toString();
    final errors = <String>[];
    var imported = 0;
    for (var index = 1; index < rows.length; index++) {
      final row = rows[index];
      String cell(int column) =>
          column >= 0 && column < row.length ? '${row[column]}'.trim() : '';
      try {
        final date = _date(cell(dateIndex));
        if (date == null) throw const FormatException('unsupported date');
        EntryDirection direction;
        Money? money;
        final debit = debitIndex < 0 ? '' : cell(debitIndex);
        final credit = creditIndex < 0 ? '' : cell(creditIndex);
        if (debit.isNotEmpty && credit.isNotEmpty) {
          throw const FormatException('both debit and credit are populated');
        } else if (debit.isNotEmpty) {
          direction = EntryDirection.debit;
          money = Money.tryParsePkr('PKR $debit');
        } else if (credit.isNotEmpty) {
          direction = EntryDirection.credit;
          money = Money.tryParsePkr('PKR $credit');
        } else {
          final raw = cell(amountIndex).replaceAll(',', '');
          if (!raw.startsWith('-') && !raw.startsWith('+')) {
            throw const FormatException('signed amount required');
          }
          direction = raw.startsWith('-')
              ? EntryDirection.debit
              : EntryDirection.credit;
          money = Money.tryParsePkr('PKR $raw');
        }
        if (money == null || money.isZero) {
          throw const FormatException('invalid amount');
        }
        ledger.ingestCsvCandidate(
          batchId: batchId,
          rowNumber: index + 1,
          accountId: accountId,
          direction: direction,
          amount: money.absolute,
          occurredAt: date,
          description: cell(descriptionIndex),
          reference: referenceIndex < 0 ? null : cell(referenceIndex),
        );
        imported++;
      } on FormatException catch (error) {
        errors.add('Row ${index + 1}: ${error.message}');
      }
    }
    ledger.finishBatch();
    return CsvImportResult(imported: imported, errors: errors);
  }

  int _find(List<String> headers, List<String> names) {
    for (final name in names) {
      final index = headers.indexOf(name);
      if (index >= 0) {
        return index;
      }
    }
    return -1;
  }

  String _header(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  DateTime? _date(String value) {
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (iso != null) {
      return _validDate(iso.group(1)!, iso.group(2)!, iso.group(3)!);
    }
    final local = RegExp(r'^(\d{2})[/-](\d{2})[/-](\d{4})$').firstMatch(value);
    if (local != null) {
      return _validDate(local.group(3)!, local.group(2)!, local.group(1)!);
    }
    return null;
  }

  DateTime? _validDate(String year, String month, String day) {
    final y = int.parse(year), m = int.parse(month), d = int.parse(day);
    final value = DateTime.utc(y, m, d);
    return value.year == y && value.month == m && value.day == d ? value : null;
  }
}
