import 'package:csv/csv.dart';

import 'statement_table_detector.dart';

final class StatementAccountProfile {
  const StatementAccountProfile({
    required this.id,
    required this.name,
    this.institution = '',
    this.suffix = '',
  });

  final String id;
  final String name;
  final String institution;
  final String suffix;
}

final class StatementAccountInference {
  const StatementAccountInference({
    required this.suggestedAccountId,
    required this.confidence,
    required this.reason,
    this.detectedInstitution = '',
    this.detectedSuffix = '',
  });

  final String? suggestedAccountId;
  final double confidence;
  final String reason;
  final String detectedInstitution;
  final String detectedSuffix;
}

/// Infers statement ownership only from worksheet names and the metadata block
/// above the transaction table. Transaction descriptions are deliberately not
/// considered because they commonly name counterparties and transfer targets.
final class StatementAccountInferer {
  const StatementAccountInferer();

  StatementAccountInference infer({
    required String sheetName,
    required String csvText,
    required List<StatementAccountProfile> accounts,
  }) {
    if (accounts.isEmpty) {
      return const StatementAccountInference(
        suggestedAccountId: null,
        confidence: 0,
        reason: 'Add an account before importing this statement.',
      );
    }

    final detected = const StatementTableDetector().detect(csvText);
    final decoded = Csv(
      fieldDelimiter: detected.delimiter,
      autoDetect: false,
    ).decode(csvText.startsWith('\ufeff') ? csvText.substring(1) : csvText);
    final metadataRows = decoded.take(detected.headerRowIndex);
    final metadata = metadataRows
        .expand((row) => row)
        .map((value) => '$value')
        .where((value) => value.trim().isNotEmpty)
        .join(' ');
    final evidence = _normalize('$sheetName $metadata');
    final suffix = _detectSuffix(metadata);
    final institution = _detectInstitution(evidence);

    final scored = accounts.map((account) {
      var score = 0;
      final reasons = <String>[];
      final accountSuffix = account.suffix.replaceAll(RegExp(r'\D'), '');
      if (suffix.isNotEmpty &&
          accountSuffix.isNotEmpty &&
          suffix ==
              accountSuffix.substring(
                accountSuffix.length > 4 ? accountSuffix.length - 4 : 0,
              )) {
        score += 120;
        reasons.add('account ending $suffix');
      }
      final accountName = _normalize(account.name);
      if (accountName.length >= 3 && _containsPhrase(evidence, accountName)) {
        score += 55;
        reasons.add('account name');
      }
      final accountInstitution = _normalize(account.institution);
      if (accountInstitution.length >= 3 &&
          _containsPhrase(evidence, accountInstitution)) {
        score += 60;
        reasons.add('institution');
      }
      if (institution.isNotEmpty &&
          _institutionMatches(
            institution,
            '${account.name} ${account.institution}',
          )) {
        score += 65;
        reasons.add(institution);
      }
      return (account: account, score: score, reasons: reasons);
    }).toList()..sort((a, b) => b.score.compareTo(a.score));

    final best = scored.first;
    final runnerUp = scored.length > 1 ? scored[1].score : -1;
    if (best.score >= 50 && best.score - runnerUp >= 10) {
      return StatementAccountInference(
        suggestedAccountId: best.account.id,
        confidence: (best.score / 180).clamp(.55, 1),
        reason: 'Matched ${best.reasons.join(' and ')}',
        detectedInstitution: institution,
        detectedSuffix: suffix,
      );
    }
    if (accounts.length == 1) {
      return StatementAccountInference(
        suggestedAccountId: accounts.single.id,
        confidence: .35,
        reason: 'Only available account; please confirm',
        detectedInstitution: institution,
        detectedSuffix: suffix,
      );
    }
    return StatementAccountInference(
      suggestedAccountId: null,
      confidence: 0,
      reason: best.score > 0
          ? 'Account clues are ambiguous; choose an account'
          : 'No account details found; choose an account',
      detectedInstitution: institution,
      detectedSuffix: suffix,
    );
  }

  String _detectSuffix(String metadata) {
    final match = RegExp(
      r'(?:account|a\s*/?\s*c|iban|card)[^\r\n]{0,45}?([0-9][0-9\s-]{3,})',
      caseSensitive: false,
    ).firstMatch(metadata);
    if (match != null) {
      final digits = match.group(1)!.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 4) return digits.substring(digits.length - 4);
    }
    final standalone = RegExp(r'(?<!\d)(\d{10,24})(?!\d)')
        .allMatches(metadata)
        .map((match) => match.group(1)!)
        .toSet();
    if (standalone.length != 1) return '';
    final digits = standalone.single;
    return digits.substring(digits.length - 4);
  }

  String _detectInstitution(String normalized) {
    for (final entry in _institutionAliases.entries) {
      if (entry.value.any((alias) => _containsPhrase(normalized, alias))) {
        return entry.key;
      }
    }
    return '';
  }

  bool _institutionMatches(String institution, String accountText) {
    final normalized = _normalize(accountText);
    return _institutionAliases[institution]!.any(
      (alias) => _containsPhrase(normalized, alias),
    );
  }

  bool _containsPhrase(String text, String phrase) =>
      ' $text '.contains(' ${_normalize(phrase)} ');

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

const _institutionAliases = <String, List<String>>{
  'Meezan Bank': ['meezan', 'meezan bank'],
  'UBL': ['ubl', 'united bank', 'united bank limited'],
  'HBL': ['hbl', 'habib bank', 'habib bank limited'],
  'Bank Alfalah': ['bank alfalah', 'alfalah'],
  'Allied Bank': ['allied bank', 'abl'],
  'MCB': ['mcb', 'mcb bank', 'muslim commercial bank'],
  'Standard Chartered': ['standard chartered', 'scb'],
  'Faysal Bank': ['faysal bank', 'fbl'],
  'Askari Bank': ['askari bank', 'akbl'],
  'Bank Al Habib': ['bank al habib', 'bahl'],
  'JazzCash': ['jazzcash', 'jazz cash'],
  'Easypaisa': ['easypaisa', 'easy paisa'],
  'NayaPay': ['nayapay', 'naya pay'],
  'SadaPay': ['sadapay', 'sada pay'],
};
