import 'package:csv/csv.dart';

enum StatementColumnKind {
  date,
  description,
  merchant,
  debit,
  credit,
  amount,
  direction,
  balance,
  reference,
  currency,
  unknown,
}

final class DetectedStatementTable {
  const DetectedStatementTable({
    required this.delimiter,
    required this.headerRowIndex,
    required this.headers,
    required this.dataRows,
  });

  final String delimiter;
  final int headerRowIndex;
  final List<String> headers;
  final List<List<dynamic>> dataRows;
}

/// Locates the transaction table inside CSV text or an Excel sheet converted
/// to CSV. Bank exports often place titles and account metadata above it.
final class StatementTableDetector {
  const StatementTableDetector();

  DetectedStatementTable detect(String text) {
    final normalized = text.startsWith('\ufeff') ? text.substring(1) : text;
    if (normalized.trim().isEmpty) {
      throw const FormatException('The statement is empty.');
    }

    _Candidate? best;
    for (final delimiter in const [',', ';', '\t', '|']) {
      try {
        final rows = Csv(
          fieldDelimiter: delimiter,
          autoDetect: false,
        ).decode(normalized);
        for (var index = 0; index < rows.length && index < 60; index++) {
          final score = _scoreHeader(rows[index]);
          final candidate = _Candidate(
            delimiter: delimiter,
            rows: rows,
            headerRowIndex: index,
            score: score,
          );
          if (best == null || candidate.isBetterThan(best)) best = candidate;
        }
      } on FormatException {
        // Try the next delimiter. A quoted field may be valid for only one.
      }
    }
    if (best == null || best.rows.isEmpty) {
      throw const FormatException('The statement could not be read.');
    }

    var headerIndex = best.headerRowIndex;
    if (best.score < 8) {
      headerIndex = best.rows.indexWhere(
        (row) => row.where((value) => '$value'.trim().isNotEmpty).length >= 2,
      );
      if (headerIndex < 0) {
        throw const FormatException('No transaction table was found.');
      }
    }
    final headers = _uniqueHeaders(best.rows[headerIndex]);
    if (headers.every((header) => header.isEmpty)) {
      throw const FormatException('No transaction header row was found.');
    }
    return DetectedStatementTable(
      delimiter: best.delimiter,
      headerRowIndex: headerIndex,
      headers: headers,
      dataRows: best.rows.skip(headerIndex + 1).toList(growable: false),
    );
  }

  int _scoreHeader(List<dynamic> row) {
    final kinds = row
        .map((value) => recognizeStatementHeader('$value'))
        .where((kind) => kind != StatementColumnKind.unknown)
        .toSet();
    var score = kinds.length;
    if (kinds.contains(StatementColumnKind.date)) score += 5;
    if (kinds.contains(StatementColumnKind.description) ||
        kinds.contains(StatementColumnKind.merchant)) {
      score += 4;
    }
    if (kinds.contains(StatementColumnKind.amount) ||
        kinds.contains(StatementColumnKind.debit) ||
        kinds.contains(StatementColumnKind.credit)) {
      score += 5;
    }
    if (kinds.contains(StatementColumnKind.balance)) score += 2;
    if (kinds.contains(StatementColumnKind.reference)) score += 1;
    return score;
  }

  List<String> _uniqueHeaders(List<dynamic> row) {
    final counts = <String, int>{};
    return [
      for (var index = 0; index < row.length; index++)
        () {
          final value = '${row[index]}'.trim();
          final base = value.isEmpty ? 'Column ${index + 1}' : value;
          final count = (counts[base.toLowerCase()] ?? 0) + 1;
          counts[base.toLowerCase()] = count;
          return count == 1 ? base : '$base ($count)';
        }(),
    ];
  }
}

StatementColumnKind recognizeStatementHeader(String value) {
  final header = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return switch (header) {
    'date' ||
    'txndate' ||
    'transactiondate' ||
    'transactiondatetime' ||
    'postingdate' ||
    'valuedate' => StatementColumnKind.date,
    'description' ||
    'details' ||
    'transactiondetails' ||
    'narration' ||
    'narrative' ||
    'memo' ||
    'remarks' ||
    'transactionremarks' ||
    'particulars' => StatementColumnKind.description,
    'merchant' || 'counterparty' || 'payee' => StatementColumnKind.merchant,
    'debit' ||
    'debitamount' ||
    'withdrawal' ||
    'withdrawals' ||
    'withdrawalamount' ||
    'dramount' ||
    'moneyout' ||
    'paidout' => StatementColumnKind.debit,
    'credit' ||
    'creditamount' ||
    'deposit' ||
    'deposits' ||
    'depositamount' ||
    'cramount' ||
    'moneyin' ||
    'paidin' => StatementColumnKind.credit,
    'amount' ||
    'transactionamount' ||
    'txnamount' => StatementColumnKind.amount,
    'direction' || 'drcr' || 'type' => StatementColumnKind.direction,
    'balance' ||
    'runningbalance' ||
    'closingbalance' ||
    'availablebalance' ||
    'ledgerbalance' ||
    'accountbalance' => StatementColumnKind.balance,
    'reference' ||
    'referenceno' ||
    'refno' ||
    'transactionid' ||
    'txnref' ||
    'rrn' ||
    'instrumentid' ||
    'chequeno' ||
    'tracenumber' => StatementColumnKind.reference,
    'currency' || 'ccy' => StatementColumnKind.currency,
    _ => StatementColumnKind.unknown,
  };
}

final class _Candidate {
  const _Candidate({
    required this.delimiter,
    required this.rows,
    required this.headerRowIndex,
    required this.score,
  });

  final String delimiter;
  final List<List<dynamic>> rows;
  final int headerRowIndex;
  final int score;

  bool isBetterThan(_Candidate other) {
    if (score != other.score) return score > other.score;
    final width = rows[headerRowIndex].length;
    final otherWidth = other.rows[other.headerRowIndex].length;
    if (width != otherWidth) return width > otherWidth;
    return headerRowIndex < other.headerRowIndex;
  }
}
