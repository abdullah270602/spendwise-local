import 'dart:convert';

import 'package:excel_plus/excel_plus.dart';

final class DecodedStatementSheet {
  const DecodedStatementSheet({required this.name, required this.csvText});

  final String name;
  final String csvText;
}

final class DecodedStatementFile {
  const DecodedStatementFile({required this.fileName, required this.sheets});

  final String fileName;
  final List<DecodedStatementSheet> sheets;
}

/// Decodes statement files without network access or temporary plaintext files.
final class StatementFileDecoder {
  const StatementFileDecoder();

  static const maxFileBytes = 25 * 1024 * 1024;

  Future<DecodedStatementFile> decode({
    required String fileName,
    required List<int> bytes,
  }) async {
    if (bytes.length > maxFileBytes) {
      throw const FormatException(
        'This statement is larger than 25 MB. Export a smaller date range and try again.',
      );
    }
    final extension = fileName.split('.').last.toLowerCase();
    if (extension == 'csv') {
      return DecodedStatementFile(
        fileName: fileName,
        sheets: [
          DecodedStatementSheet(name: 'Statement', csvText: _decodeText(bytes)),
        ],
      );
    }
    if (extension != 'xlsx' && extension != 'xls') {
      throw const FormatException('Choose a CSV, XLSX, or XLS statement.');
    }

    final workbook = await Excel.decodeBytesAsync(bytes);
    final sheets = <DecodedStatementSheet>[];
    for (final name in workbook.sheetOrder) {
      final sheet = workbook.sheets[name];
      if (sheet == null || sheet.maxRows == 0 || sheet.maxColumns == 0) {
        continue;
      }
      final text = sheet.toCsv();
      if (text.trim().isEmpty) continue;
      sheets.add(DecodedStatementSheet(name: name, csvText: text));
    }
    if (sheets.isEmpty) {
      throw const FormatException(
        'This workbook has no non-empty worksheets to import.',
      );
    }
    return DecodedStatementFile(fileName: fileName, sheets: sheets);
  }

  String _decodeText(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }
}
