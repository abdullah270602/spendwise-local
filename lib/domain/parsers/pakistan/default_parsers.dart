import '../../models/event_candidate.dart';
import '../../parsing/parser_definition.dart';

/// Sanitized, deterministic rules. Institution-specific definitions can be
/// registered beside these without changing the ledger or reconciler.
final pakistanParserDefinitions = <ParserDefinition>[
  // The dominant shape of a Pakistani bank alert, and the one the generic
  // rules read worst:
  //
  //   Meezan Bank PKR 4,000.00 sent to M SAMPLE PAYEE UBL-xxx9002 from your
  //   A/C xxx9001 of MAIN BRANCH LHR on 27-Aug-2026 at 16:51
  //   Fee: Rs.4.00 TID:100001 UAN 021111000000
  //
  // The amount leads, the verb follows it, and the beneficiary carries their
  // own bank tag. The generic "verb then amount" rules cannot see any of it,
  // so these alerts fell through to the fallback, which produced no
  // counterparty at all and titled a transfer after the sending bank.
  ParserDefinition(
    id: 'pk.ibft',
    version: 1,
    rules: [
      ParserRule(
        id: 'sent-to-beneficiary-from-your-account',
        // The counterparty group deliberately keeps the beneficiary's bank tag
        // and masked digits: they are what lets the reconciler recognise a
        // move between two accounts the user owns. The display name is
        // trimmed later, for the title only.
        pattern: RegExp(
          r'(?<amount>(?:PKR|Rs\.?)\s*[\d,]+(?:\.\d{1,2})?)'
          // "has been", "was", "successfully" -- banks pad the verb
          // differently and the padding carries no meaning.
          r'(?:\s+(?:has|have|been|was|is|successfully|already))*\s+'
          r'(?:sent|transferred|remitted|paid)\s+to\s+'
          r'(?<counterparty>\S(?:.|\n){1,90}?)\s+'
          // "from your A/C", "from your account", "from your JazzCash
          // account" -- the wallet may name itself in the middle.
          r'from\s+your\s+(?:[A-Za-z]+\s+)?(?:a\s*\/?\s*c|account|wallet)\b'
          r'(?:(?:.|\n)*?\bTID\s*[:#-]?\s*(?<reference>[A-Za-z0-9-]{4,}))?',
          caseSensitive: false,
        ),
        direction: EntryDirection.debit,
        // Deliberately not CandidateType.transfer. This names the instrument
        // (an interbank transfer), but whether it was a move between the
        // user's own accounts is the reconciler's call, made by pairing two
        // legs. Marking it here would invite a later rule to treat every
        // payment to a friend as a transfer and drop it out of spending.
        type: CandidateType.unknown,
        confidence: 0.95,
      ),
      ParserRule(
        id: 'received-into-your-account-from-sender',
        pattern: RegExp(
          r'(?<amount>(?:PKR|Rs\.?)\s*[\d,]+(?:\.\d{1,2})?)'
          r'(?:\s+(?:has|have|been|was|is|successfully|already))*\s+'
          r'(?:received|credited)\s+(?:in(?:to)?|to)\s+your\s+'
          r'(?:[A-Za-z]+\s+)?(?:a\s*\/?\s*c|account|wallet)\b[^.]{0,60}?'
          r'\bfrom\s+(?<counterparty>\S.{1,90}?)'
          r'(?=\s+(?:on|via|through|dated|TID|Ref)\b|[.,]|$)'
          r'(?:(?:.|\n)*?\bTID\s*[:#-]?\s*(?<reference>[A-Za-z0-9-]{4,}))?',
          caseSensitive: false,
        ),
        direction: EntryDirection.credit,
        type: CandidateType.unknown,
        confidence: 0.95,
      ),
    ],
  ),
  // Card and wallet purchases: the merchant follows "at", and the amount can
  // sit on either side of the verb.
  ParserDefinition(
    id: 'pk.card.purchase',
    version: 1,
    rules: [
      ParserRule(
        id: 'purchase-at-merchant',
        pattern: RegExp(
          r'(?<amount>(?:PKR|Rs\.?)\s*[\d,]+(?:\.\d{1,2})?)[^.]{0,40}?'
          r'\b(?:spent|used|purchase(?:d)?|debited|paid|charged)\b'
          r"[^.]{0,40}?\bat\s+(?<counterparty>[A-Za-z0-9][A-Za-z0-9.&'\s-]{1,44}?)"
          // Same stop list the generic merchant matcher uses. Leaving out
          // "as"/"for"/"by" swept trailing narration into the shop's name
          // ("DEMO PHARMACY as international transaction").
          r'(?=\s*[.,;]|\s+(?:of|on|via|as|for|using|by|dated|IBAN|A\/?c|'
          r'Ref|Reference|TID|Trx|Avbl|Avl|Bal|Rs\.?|PKR)\b|$)',
          caseSensitive: false,
        ),
        direction: EntryDirection.debit,
        type: CandidateType.purchase,
        confidence: 0.93,
      ),
    ],
  ),
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
