import 'dart:convert';

import '../models/event_candidate.dart';
import 'parser_definition.dart';

/// Turns a parser definition into rows and back.
///
/// `parser_definitions` has been in the schema since the first release, with
/// `country`, `institution`, `source_match_json`, `rules_json`, `is_builtin`
/// and `enabled` — and nothing ever read it. The parser only ever built its
/// registry from a hardcoded list, so supporting one more bank meant editing
/// Dart, shipping a release, and waiting for people to install it.
///
/// This is the piece that makes a bank a row instead. Nothing here decides
/// policy about *where* definitions come from; it only settles the format so
/// the ledger can store them.
///
/// ## On trusting a pattern from a database
///
/// A regular expression read from a row is code. Dart's `RegExp` backtracks,
/// so a pattern like `(a+)+$` against a long non-matching line does not merely
/// fail — it hangs the isolate that is draining notifications, and the app
/// looks dead for reasons nothing on screen can explain.
///
/// So [decodeRule] refuses rather than throws, and refuses generously:
/// anything that will not compile, and anything carrying the nested-quantifier
/// shapes that cause catastrophic backtracking, is dropped with a reason. A
/// dropped rule costs a bank alert going to Review, which is recoverable. A
/// pattern that hangs costs the app.
///
/// This is not a security boundary — a determined author can still write a
/// slow pattern, and the real fix is a matcher with guaranteed linear time.
/// It is a guard against the accident, which is the case that actually
/// happens.
class ParserDefinitionCodec {
  const ParserDefinitionCodec();

  /// Nested quantifiers — a repeated group that is itself repeatable — are
  /// the shape behind almost every real catastrophic-backtracking incident.
  /// Deliberately crude: it will refuse some patterns that would have been
  /// fine, and that trade is the right way round.
  static final _nestedQuantifier = RegExp(
    r'\([^)]*[+*][^)]*\)\s*[+*{]|\([^)]*\{\d+,\}?[^)]*\)\s*[+*{]',
  );

  /// A pattern long enough that nobody wrote it deliberately by hand.
  static const maxPatternLength = 2000;

  Map<String, Object?> encodeSourceMatch(ParserDefinition definition) => {
    'packageNames': definition.packageNames.toList()..sort(),
    'senders': definition.senders.toList()..sort(),
  };

  List<Map<String, Object?>> encodeRules(ParserDefinition definition) => [
    for (final rule in definition.rules)
      {
        'id': rule.id,
        'pattern': rule.pattern.pattern,
        'caseSensitive': rule.pattern.isCaseSensitive,
        'direction': rule.direction.name,
        'type': rule.type.name,
        'amountGroup': rule.amountGroup,
        'referenceGroup': rule.referenceGroup,
        'counterpartyGroup': rule.counterpartyGroup,
        'confidence': rule.confidence,
      },
  ];

  String encodeSourceMatchJson(ParserDefinition definition) =>
      jsonEncode(encodeSourceMatch(definition));

  String encodeRulesJson(ParserDefinition definition) =>
      jsonEncode(encodeRules(definition));

  /// One rule, or null with the reason it was refused.
  ///
  /// Returns rather than throws because a single bad rule in a definition
  /// must not take the rest of the definition — or every other definition —
  /// down with it.
  ({ParserRule? rule, String? refusal}) decodeRule(Object? raw) {
    if (raw is! Map) return (rule: null, refusal: 'Rule is not an object.');
    final id = raw['id'];
    final pattern = raw['pattern'];
    if (id is! String || id.isEmpty) {
      return (rule: null, refusal: 'Rule has no id.');
    }
    if (pattern is! String || pattern.isEmpty) {
      return (rule: null, refusal: 'Rule "$id" has no pattern.');
    }
    if (pattern.length > maxPatternLength) {
      return (
        rule: null,
        refusal: 'Rule "$id" pattern is ${pattern.length} characters long.',
      );
    }
    if (_nestedQuantifier.hasMatch(pattern)) {
      return (
        rule: null,
        refusal:
            'Rule "$id" repeats a group that already repeats, which can take '
            'unbounded time to fail.',
      );
    }
    final direction = EntryDirection.values
        .where((value) => value.name == raw['direction'])
        .firstOrNull;
    if (direction == null) {
      return (rule: null, refusal: 'Rule "$id" does not say which way money moved.');
    }
    final RegExp compiled;
    try {
      compiled = RegExp(
        pattern,
        caseSensitive: raw['caseSensitive'] as bool? ?? true,
      );
    } on FormatException catch (error) {
      return (rule: null, refusal: 'Rule "$id" will not compile: ${error.message}');
    }
    final confidence = (raw['confidence'] as num?)?.toDouble() ?? 0.9;
    return (
      rule: ParserRule(
        id: id,
        pattern: compiled,
        direction: direction,
        type:
            CandidateType.values
                .where((value) => value.name == raw['type'])
                .firstOrNull ??
            CandidateType.unknown,
        amountGroup: raw['amountGroup'] as String? ?? 'amount',
        referenceGroup: raw['referenceGroup'] as String? ?? 'reference',
        counterpartyGroup: raw['counterpartyGroup'] as String? ?? 'counterparty',
        // Out-of-range confidence would trip an assertion deep inside
        // EventCandidate, far from the row that caused it.
        confidence: confidence.clamp(0.0, 1.0),
      ),
      refusal: null,
    );
  }

  /// One definition, plus every rule that had to be dropped and why.
  ///
  /// A definition whose rules were all refused still comes back, with no
  /// rules. It matches nothing and does no harm, and keeping it means the
  /// row stays visible rather than vanishing from a report that is supposed
  /// to explain why a bank is not being read.
  ({ParserDefinition? definition, List<String> refusals}) decode({
    required String id,
    required int version,
    required String sourceMatchJson,
    required String rulesJson,
  }) {
    final refusals = <String>[];
    Object? sourceMatch;
    Object? rules;
    try {
      sourceMatch = jsonDecode(sourceMatchJson);
      rules = jsonDecode(rulesJson);
    } on FormatException catch (error) {
      return (
        definition: null,
        refusals: ['Definition "$id" is not readable JSON: ${error.message}'],
      );
    }
    if (rules is! List) {
      return (definition: null, refusals: ['Definition "$id" has no rule list.']);
    }

    final decoded = <ParserRule>[];
    for (final raw in rules) {
      final attempt = decodeRule(raw);
      if (attempt.rule != null) {
        decoded.add(attempt.rule!);
      } else if (attempt.refusal != null) {
        refusals.add(attempt.refusal!);
      }
    }

    Set<String> names(Object? value) => value is List
        ? value.whereType<String>().where((item) => item.isNotEmpty).toSet()
        : const {};

    return (
      definition: ParserDefinition(
        id: id,
        version: version,
        packageNames: sourceMatch is Map
            ? names(sourceMatch['packageNames'])
            : const {},
        senders: sourceMatch is Map ? names(sourceMatch['senders']) : const {},
        rules: decoded,
      ),
      refusals: refusals,
    );
  }
}
