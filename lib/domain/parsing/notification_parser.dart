import '../../core/money.dart';
import '../models/event_candidate.dart';
import '../models/raw_observation.dart';
import '../parsers/pakistan/default_parsers.dart';
import 'parser_definition.dart';

final class NotificationParser {
  const NotificationParser({this.registry});
  final ParserRegistry? registry;

  static final RegExp _moneyPattern = RegExp(
    r'(?<![A-Za-z])(?:[+-]\s*)?(?:PKR|Rs\.?|₨)\s*[+-]?\s*(?:(?:\d{1,3}(?:,\d{3})+)|\d+)(?:\.\d{1,2})?',
    caseSensitive: false,
  );
  static final RegExp _debitWords = RegExp(
    r'\b(debit(?:ed)?|paid|sent|spent|purchase(?:d)?|withdrawn?|deducted|transferred\s+to)\b',
    caseSensitive: false,
  );
  static final RegExp _creditWords = RegExp(
    r'\b(credit(?:ed)?|received|deposited|refunded|transferred\s+from)\b',
    caseSensitive: false,
  );
  static final RegExp _referencePattern = RegExp(
    r'\b(?:ref(?:erence)?|txn|transaction|trace|rrn)\s*(?:no\.?|id|#|:|-)?\s*([A-Z0-9-]{4,})',
    caseSensitive: false,
  );

  /// Returns null unless there is exactly one explicit PKR amount and a clear
  /// debit/credit signal. This intentionally prefers review over guessing.
  EventCandidate? parse(RawObservation observation) {
    return parseDetailed(observation).candidate;
  }

  ParserResult parseDetailed(RawObservation observation) {
    if (observation.accountId == null) {
      return const ParserResult(
        status: ParseStatus.invalid,
        parserId: 'none',
        parserVersion: 0,
        confidence: 0,
        reasons: ['No account is mapped to this source.'],
      );
    }
    final text =
        observation.snapshot?.combinedText ??
        '${observation.title ?? ''} ${observation.body}'.trim();
    final amountMatches = _moneyPattern.allMatches(text).toList();
    if (amountMatches.length != 1) {
      return ParserResult(
        status: amountMatches.isEmpty
            ? ParseStatus.unsupported
            : ParseStatus.ambiguous,
        parserId: 'pk.prescreen',
        parserVersion: 1,
        confidence: 0,
        reasons: const ['Expected exactly one explicit PKR amount.'],
      );
    }
    final configured = registry ?? ParserRegistry(pakistanParserDefinitions);
    for (final definition in configured.matching(observation)) {
      final result = _applyDefinition(definition, observation);
      if (result != null) return result;
    }

    final money = Money.tryParsePkr(amountMatches.single.group(0)!);
    if (money == null || money.isZero) {
      return const ParserResult(
        status: ParseStatus.invalid,
        parserId: 'pk.generic.fallback',
        parserVersion: 1,
        confidence: 0,
        reasons: ['Invalid or zero amount.'],
      );
    }

    final hasDebit = _debitWords.hasMatch(text) || money.isNegative;
    final hasCredit =
        _creditWords.hasMatch(text) ||
        amountMatches.single.group(0)!.trimLeft().startsWith('+');
    if (hasDebit == hasCredit) {
      return const ParserResult(
        status: ParseStatus.ambiguous,
        parserId: 'pk.generic.fallback',
        parserVersion: 1,
        confidence: 0.3,
        reasons: ['Direction is ambiguous.'],
      );
    }
    final direction = hasDebit ? EntryDirection.debit : EntryDirection.credit;
    final reference = _referencePattern
        .firstMatch(text)
        ?.group(1)
        ?.toUpperCase();

    final candidate = EventCandidate(
      id: 'candidate:${observation.id}',
      observation: observation,
      accountId: observation.accountId!,
      amount: money.absolute,
      direction: direction,
      occurredAt: observation.observedAt,
      reference: reference,
      description: observation.title?.trim().isNotEmpty == true
          ? observation.title!.trim()
          : null,
      type: direction == EntryDirection.debit
          ? CandidateType.purchase
          : CandidateType.income,
      parserId: 'pk.generic.fallback',
      parserVersion: 1,
      confidence: 0.75,
      reasons: const ['One amount and one direction signal matched.'],
    );
    return ParserResult(
      status: ParseStatus.parsed,
      parserId: candidate.parserId,
      parserVersion: candidate.parserVersion,
      confidence: candidate.confidence,
      reasons: candidate.reasons,
      candidate: candidate,
    );
  }

  ParserResult? _applyDefinition(
    ParserDefinition definition,
    RawObservation observation,
  ) {
    final text =
        observation.snapshot?.combinedText ??
        '${observation.title ?? ''} ${observation.body}';
    for (final rule in definition.rules) {
      final match = rule.pattern.firstMatch(text);
      if (match == null) continue;
      String? named(String name) {
        try {
          return match.namedGroup(name);
        } on ArgumentError {
          return null;
        }
      }

      final amountText = named(rule.amountGroup);
      final amount = amountText == null ? null : Money.tryParsePkr(amountText);
      if (amount == null || amount.isZero) continue;
      final candidate = EventCandidate(
        id: 'candidate:${observation.id}',
        observation: observation,
        accountId: observation.accountId!,
        amount: amount.absolute,
        direction: rule.direction,
        occurredAt: observation.observedAt,
        counterparty: named(rule.counterpartyGroup)?.trim(),
        reference:
            (named(rule.referenceGroup) ??
                    _referencePattern.firstMatch(text)?.group(1))
                ?.trim()
                .toUpperCase(),
        description: observation.title,
        confidence: rule.confidence,
        type: rule.type,
        parserId: definition.id,
        parserVersion: definition.version,
        reasons: ['Matched rule ${rule.id}.'],
      );
      return ParserResult(
        status: ParseStatus.parsed,
        parserId: definition.id,
        parserVersion: definition.version,
        confidence: rule.confidence,
        reasons: candidate.reasons,
        candidate: candidate,
      );
    }
    return null;
  }
}
