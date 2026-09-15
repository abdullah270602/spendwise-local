import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/models/event_candidate.dart';
import 'package:spendwise/domain/parsers/pakistan/default_parsers.dart';
import 'package:spendwise/domain/parsing/parser_definition.dart';
import 'package:spendwise/domain/parsing/parser_definition_codec.dart';

/// Making a bank a row instead of a code change.
///
/// The two obligations are opposite. A definition has to survive the round
/// trip *exactly* — a pattern that comes back subtly different reads every
/// alert from that bank subtly wrong, and nothing on screen would say so.
/// And a definition that arrives broken has to be refused rather than run,
/// because a pattern out of a database is code.
void main() {
  const codec = ParserDefinitionCodec();

  ParserDefinition roundTrip(ParserDefinition original) {
    final decoded = codec.decode(
      id: original.id,
      version: original.version,
      sourceMatchJson: codec.encodeSourceMatchJson(original),
      rulesJson: codec.encodeRulesJson(original),
    );
    expect(decoded.refusals, isEmpty, reason: 'a built-in must not be refused');
    return decoded.definition!;
  }

  group('every built-in definition survives the round trip', () {
    // Not a sample: all of them, every rule, byte for byte. These are the
    // definitions the app has always used, and they are about to start
    // arriving from a table instead of from Dart.
    for (final original in pakistanParserDefinitions) {
      test(original.id, () {
        final restored = roundTrip(original);

        expect(restored.id, original.id);
        expect(restored.version, original.version);
        expect(restored.packageNames, original.packageNames);
        expect(restored.senders, original.senders);
        expect(restored.rules, hasLength(original.rules.length));

        for (var i = 0; i < original.rules.length; i++) {
          final before = original.rules[i];
          final after = restored.rules[i];
          expect(after.id, before.id);
          expect(
            after.pattern.pattern,
            before.pattern.pattern,
            reason: 'the pattern is the whole definition',
          );
          expect(
            after.pattern.isCaseSensitive,
            before.pattern.isCaseSensitive,
            reason: 'case sensitivity is not part of the pattern string, and '
                'losing it silently doubles what a rule matches',
          );
          expect(after.direction, before.direction);
          expect(after.type, before.type);
          expect(after.amountGroup, before.amountGroup);
          expect(after.referenceGroup, before.referenceGroup);
          expect(after.counterpartyGroup, before.counterpartyGroup);
          expect(after.confidence, before.confidence);
        }
      });
    }
  });

  group('a definition that arrives broken is refused, not run', () {
    ({ParserDefinition? definition, List<String> refusals}) decodeRules(
      String rulesJson,
    ) => codec.decode(
      id: 'test',
      version: 1,
      sourceMatchJson: '{}',
      rulesJson: rulesJson,
    );

    test('a pattern that repeats a repeating group is dropped', () {
      // The shape behind essentially every real catastrophic-backtracking
      // incident. Dart's RegExp backtracks, and this one does not fail
      // quickly — it fails eventually, on the isolate that is draining
      // notifications, so the app simply stops with nothing on screen to
      // explain it.
      final result = decodeRules(
        '[{"id":"greedy","pattern":"(a+)+\$","direction":"debit"}]',
      );
      expect(result.definition!.rules, isEmpty);
      expect(result.refusals.single, contains('unbounded time'));
    });

    test('a pattern that will not compile is dropped with the reason', () {
      final result = decodeRules(
        r'[{"id":"broken","pattern":"(?<amount","direction":"debit"}]',
      );
      expect(result.definition!.rules, isEmpty);
      expect(result.refusals.single, contains('will not compile'));
    });

    test('a rule with no direction is dropped', () {
      // Direction is the one thing the parser cannot infer, so a rule
      // without it would post money in whichever direction happened to be
      // the enum's first value.
      final result = decodeRules('[{"id":"vague","pattern":"PKR \\\\d+"}]');
      expect(result.definition!.rules, isEmpty);
      expect(result.refusals.single, contains('which way money moved'));
    });

    test('one bad rule does not take the good ones with it', () {
      final result = decodeRules(
        '[{"id":"greedy","pattern":"(a+)+\$","direction":"debit"},'
        r'{"id":"fine","pattern":"debited PKR (?<amount>[0-9,]+)",'
        '"direction":"debit"}]',
      );
      expect(result.definition!.rules.single.id, 'fine');
      expect(result.refusals, hasLength(1));
    });

    test('a definition whose rules were all refused still comes back', () {
      // It matches nothing and does no harm. Dropping the row instead would
      // make the bank disappear from the report meant to explain why it is
      // not being read.
      final result = decodeRules('[{"id":"greedy","pattern":"(a+)+\$"}]');
      expect(result.definition, isNotNull);
      expect(result.definition!.rules, isEmpty);
    });

    test('unreadable JSON refuses the whole definition', () {
      final result = decodeRules('not json at all');
      expect(result.definition, isNull);
      expect(result.refusals.single, contains('not readable JSON'));
    });

    test('confidence outside 0..1 is clamped rather than asserted on', () {
      // It would otherwise trip an assertion deep inside EventCandidate,
      // a long way from the row that caused it.
      final result = decodeRules(
        r'[{"id":"loud","pattern":"PKR (?<amount>[0-9]+)",'
        '"direction":"credit","confidence":4.5}]',
      );
      expect(result.definition!.rules.single.confidence, 1.0);
    });
  });

  test('an unknown candidate type falls back rather than failing', () {
    final result = codec.decode(
      id: 'test',
      version: 1,
      sourceMatchJson: '{}',
      rulesJson:
          r'[{"id":"r","pattern":"PKR (?<amount>[0-9]+)","direction":"debit",'
          '"type":"teleportation"}]',
    );
    expect(result.definition!.rules.single.type, CandidateType.unknown);
    expect(result.refusals, isEmpty);
  });

  test('source matching survives, because it decides what a rule sees', () {
    const original = ParserDefinition(
      id: 'example.bank',
      version: 3,
      packageNames: {'com.example.bank', 'com.example.bank.lite'},
      senders: {'ExampleBank'},
      rules: [],
    );
    final restored = roundTrip(original);
    expect(restored.packageNames, original.packageNames);
    expect(restored.senders, original.senders);
    expect(restored.version, 3);
  });
}
