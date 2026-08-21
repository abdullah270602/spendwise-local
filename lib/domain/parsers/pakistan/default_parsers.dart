import '../../models/event_candidate.dart';
import '../../parsing/parser_definition.dart';

/// Sanitized, deterministic rules. Institution-specific definitions can be
/// registered beside these without changing the ledger or reconciler.
final pakistanParserDefinitions = <ParserDefinition>[
  ParserDefinition(
    id: 'pk.generic.debit',
    version: 1,
    rules: [
      ParserRule(
        id: 'debited',
        pattern: RegExp(
          r'(?:debited|paid|sent)\D{0,30}(?<amount>(?:PKR|Rs\.?)\s*[\d,]+(?:\.\d{1,2})?)(?:.*?\bref(?:erence)?[: #]*(?<reference>[A-Z0-9-]{4,}))?',
          caseSensitive: false,
        ),
        direction: EntryDirection.debit,
        type: CandidateType.purchase,
      ),
    ],
  ),
  ParserDefinition(
    id: 'pk.generic.credit',
    version: 1,
    rules: [
      ParserRule(
        id: 'credited',
        pattern: RegExp(
          r'(?:credited|received|refunded)\D{0,30}(?<amount>(?:PKR|Rs\.?)\s*[\d,]+(?:\.\d{1,2})?)(?:.*?\bref(?:erence)?[: #]*(?<reference>[A-Z0-9-]{4,}))?',
          caseSensitive: false,
        ),
        direction: EntryDirection.credit,
        type: CandidateType.income,
      ),
    ],
  ),
];
