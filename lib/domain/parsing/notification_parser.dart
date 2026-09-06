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
  // Bank SMS nearly always quote the running balance beside the transaction
  // amount ("...debited PKR 80. Avl Bal: PKR 12,345"). Matched against the
  // text *preceding* an amount: a balance label, then anything but a digit,
  // so "Bal: ", "Avbl Bal ", and "new balance is Rs. " all qualify while an
  // earlier, unrelated number cannot be skipped over.
  static final RegExp _balanceLabelBefore = RegExp(
    r'\bbal(?:ance)?\b[^0-9]{0,15}$',
    caseSensitive: false,
  );

  /// A charge quoted beside the amount is not the amount. Pakistani transfer
  /// alerts routinely end "... Fee: Rs.15.00", which used to make the alert
  /// ambiguous and drop a real payment on the floor.
  static final RegExp _chargeLabelBefore = RegExp(
    r'\b(?:fee|fees|charges?|service\s+charge|tax|fed|wht|excise|'
    r'stamp\s+duty)\b[^0-9]{0,12}$',
    caseSensitive: false,
  );
  static final RegExp _debitWords = RegExp(
    r'\b(?:debit(?:ed)?|paid|sent|spent|purchase(?:d)?|withdrawn?|withdrawal|'
    r'deducted|charged|transfer(?:red)?\s+to|used\s+(?:at|for|on)|'
    // "credited to <someone> from your account" is money leaving. Marking
    // the source side as a debit signal makes such wording read as
    // contradictory, so it goes to review instead of being booked as income.
    r'from\s+your\s+(?:account|a\/?c))\b',
    caseSensitive: false,
  );
  // "Credit Card" names the instrument, not the direction. Counting it as
  // money-in filed card purchases as income.
  static final RegExp _creditWords = RegExp(
    r'\b(?:credited|received|deposited|refunded|transfer(?:red)?\s+from|'
    r'credit(?!\s+card\b))\b',
    caseSensitive: false,
  );
  static final RegExp _referencePattern = RegExp(
    r'\b(?:ref(?:erence)?|txn|transaction|trace|rrn|tid)\s*(?:no\.?|id|#|:|-)?\s*([A-Z0-9-]{4,})',
    caseSensitive: false,
  );
  // Bounded by common trailing markers so a bank's own boilerplate (IBAN,
  // account suffix, reference, timestamp) is never swept into the name.
  // Stops at sentence punctuation even with no space before it, so
  // "at SAMPLE SUPERMARKET. Avbl Bal Rs.9,000" yields the shop and not the
  // balance sentence trailing it.
  static const _counterpartyStop =
      r'(?=\s*[.,;]|\s+(?:of|on|via|as|for|using|by|dated|IBAN|A\/?c|Ref|'
      r'Reference|TID|Trx|Rs\.?|PKR|₨)|$)';
  static final RegExp _debitCounterpartyPattern = RegExp(
    r'\b(?:sent|paid|transfer(?:red)?)\s+to\s+([A-Za-z][A-Za-z.\s]{1,40}?)' +
        _counterpartyStop,
    caseSensitive: false,
  );
  static final RegExp _creditCounterpartyPattern = RegExp(
    r'\b(?:received|transfer(?:red)?)\s+from\s+([A-Za-z][A-Za-z.\s]{1,40}?)' +
        _counterpartyStop,
    caseSensitive: false,
  );
  static final RegExp _merchantPattern = RegExp(
    r'\bat\s+([A-Za-z][A-Za-z0-9.\s&\x27-]{1,40}?)' + _counterpartyStop,
    caseSensitive: false,
  );
  // Marketing copy reads exactly like a transaction alert -- one amount, one
  // direction word ("PKR 5,000 cashback will be credited"). Deliberately
  // narrow: only phrases that never appear in a real settlement alert, so a
  // genuine transaction is never held back. "available balance" must keep
  // parsing, hence no bare "avail"/"offer".
  /// Phrases that only ever appear in marketing, never in a settlement alert.
  /// A message matching one of these with no settlement verb anywhere in it is
  /// dropped outright rather than queued for review -- a lottery advert is not
  /// a decision anyone should have to make.
  static final RegExp _marketingPattern = RegExp(
    r'\b(?:congratulations|congrats|you\s+(?:have\s+)?won|you\s+could\s+win|'
    r'stand\s+a\s+chance|lucky\s+draw|prize|jackpot|lottery|giveaway|'
    r'limited\s+time|offer\s+valid|hurry|last\s+chance|don\S{0,2}t\s+miss|'
    r'apply\s+now|subscribe\s+now|activate\s+now|buy\s+now|order\s+now|'
    r'refer\s+a\s+friend|referral\s+bonus|download\s+the\s+app|'
    r'terms\s+and\s+conditions|t&c\s*(?:apply|s)|unsubscribe|'
    r'to\s+opt\s*-?\s*out|dial\s+\*\d|sms\s+\w+\s+to\s+\d{3,})\b',
    caseSensitive: false,
  );

  /// Something actually happened to money. Marketing copy can borrow a verb
  /// ("PKR 5,000 will be credited"), so the future tense is excluded: a real
  /// alert reports a settlement that already occurred.
  static final RegExp _settlementWords = RegExp(
    r'\b(?:debited|credited|withdrawn|deposited|purchased?|'
    r'paid|spent|charged|received|transferred|refunded|'
    r'avbl\s*bal|available\s+balance|closing\s+balance)\b',
    caseSensitive: false,
  );

  /// Marketing that borrows a settlement verb in the future tense is still
  /// marketing: "PKR 500 cashback will be credited" has not happened yet.
  static final RegExp _futureSettlement = RegExp(
    r'\b(?:will\s+be|shall\s+be|to\s+be|would\s+be|gets?|get)\s+'
    r'(?:\w+\s+){0,2}(?:credited|debited|refunded|deposited|added)\b',
    caseSensitive: false,
  );

  static final RegExp _promotionalPattern = RegExp(
    r'\b(cashback|discount|voucher|promo(?:tion|tional)?|congratulations|'
    r'prize|lucky draw|limited time|special offer|offer valid|t&c|'
    r'terms and conditions|apply now|activate now|subscribe now|'
    r'refer a friend|referral bonus)\b',
    caseSensitive: false,
  );

  /// A verification code quotes the amount of a purchase that has not gone
  /// through yet; the bank sends the real alert separately. Booking the OTP
  /// would double-count the purchase.
  static final RegExp _oneTimeCodePattern = RegExp(
    r'\b(?:otp|one[\s-]?time\s+(?:password|pin|code)|'
    r'verification\s+code|security\s+code|do\s+not\s+share\s+(?:this|the))'
    r'\b',
    caseSensitive: false,
  );

  /// Roman Urdu is the native register of Pakistani telco and lender adverts,
  /// and never of a bank settlement alert. A link with a call to action is the
  /// same tell in any language.
  static final RegExp _localMarketingPattern = RegExp(
    r'\b(?:karein|kijiye|kariye|karo|kro|hasil|muft|sirf\s+rs|'
    r'recharge\s+me|mila\s+kr|dial\s+kar|ab\s+sirf|bohat\s+kuch)\b'
    r'|https?://',
    caseSensitive: false,
  );

  static bool _isMarketing(String text) {
    final settled = _settlementWords.hasMatch(text);
    if (_localMarketingPattern.hasMatch(text) && !settled) return true;
    if (!_marketingPattern.hasMatch(text)) return false;
    if (_futureSettlement.hasMatch(text)) return true;
    return !settled;
  }

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

    // Marketing is discarded here rather than queued: it is noise, not a
    // question. A message only survives this gate if it reports a settlement
    // that has already happened.
    if (_isMarketing(text)) {
      return const ParserResult(
        status: ParseStatus.unsupported,
        parserId: 'pk.marketing',
        parserVersion: 1,
        confidence: 0,
        reasons: ['Promotional message, not a transaction.'],
      );
    }

    // An OTP names an amount for a purchase that has not settled. The bank
    // sends the settlement separately, so reading this one too would book the
    // same purchase twice.
    if (_oneTimeCodePattern.hasMatch(text)) {
      return const ParserResult(
        status: ParseStatus.unsupported,
        parserId: 'pk.otp',
        parserVersion: 1,
        confidence: 0,
        reasons: ['A verification code, not a transaction.'],
      );
    }

    final amountMatches = _transactionAmounts(text);
    if (amountMatches.length != 1) {
      return ParserResult(
        status: amountMatches.isEmpty
            ? ParseStatus.unsupported
            : ParseStatus.ambiguous,
        parserId: 'pk.prescreen',
        parserVersion: 1,
        confidence: 0,
        reasons: [
          if (amountMatches.isEmpty)
            'No PKR amount was found in this alert.'
          else
            'Found ${amountMatches.length} amounts and could not tell which is the transaction.',
        ],
      );
    }
    final configured = registry ?? ParserRegistry(pakistanParserDefinitions);
    for (final definition in configured.matching(observation)) {
      final result = _applyDefinition(
        definition,
        observation,
        amountMatches.single.group(0)!,
      );
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
    final counterparty = _counterparty(text, direction);

    // Exactly one explicit amount plus exactly one direction signal, against a
    // known account, is a deterministic read -- strong enough to post without
    // asking. Corroborating detail lifts it further; marketing copy keeps the
    // old review-first confidence so it can never post unseen.
    final promotional = _promotionalPattern.hasMatch(text);
    final confidence = promotional
        ? 0.75
        : 0.8 +
              (reference != null ? 0.05 : 0.0) +
              (counterparty != null ? 0.05 : 0.0);

    final candidate = EventCandidate(
      id: 'candidate:${observation.id}',
      observation: observation,
      accountId: observation.accountId!,
      amount: money.absolute,
      direction: direction,
      occurredAt: observation.observedAt,
      reference: reference,
      counterparty: counterparty,
      description: _describe(observation.title, counterparty),
      type: direction == EntryDirection.debit
          ? CandidateType.purchase
          : CandidateType.income,
      parserId: 'pk.generic.fallback',
      parserVersion: 1,
      confidence: confidence,
      reasons: [
        'One amount and one direction signal matched.',
        if (promotional) 'Text reads as promotional; confirm before posting.',
      ],
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

  /// Best-effort only: a bounded "sent/paid/transferred to X", "received/
  /// transferred from X", or "at X" match. Returns null rather than risk a
  /// wrong name — an unset counterparty is a lesser harm than a mislabeled
  /// one.
  /// What to call this transaction in the ledger.
  ///
  /// The notification title is often just the SMS short code the bank sends
  /// from ("8558"), which tells the reader nothing. The merchant or
  /// counterparty is the useful name, so it wins; a title is used only when
  /// it actually contains words.
  /// A beneficiary arrives as "M SAMPLE PAYEE UBL-xxx9002": the person, then
  /// their bank and masked account. The masked part has to stay on the
  /// candidate -- it is how a move between two accounts the user owns is
  /// recognised -- but it has no business being the transaction's name.
  static final RegExp _beneficiaryTag = RegExp(
    r'\s+[A-Za-z][A-Za-z]*(?:-[A-Za-z]+)*-x{2,}[A-Za-z0-9]*\s*$',
    caseSensitive: false,
  );

  /// A Pakistani IBAN: PK, two check digits, a four-letter bank code, then the
  /// account. RAAST alerts name the beneficiary only by this, so the readable
  /// part is the bank and the last four digits.
  static final RegExp _ibanPattern = RegExp(
    r'\bPK\d{2}([A-Z]{4})(\d[\dA-Z]{6,20})\b',
    caseSensitive: false,
  );

  static String? _describe(String? title, String? counterparty) {
    final name = _displayName(counterparty);
    if (name != null && name.isNotEmpty) return name;
    final heading = title?.trim();
    if (heading == null || heading.isEmpty) return null;
    return RegExp(r'[A-Za-z]{2,}').hasMatch(heading) ? heading : null;
  }

  /// The counterparty as stored keeps every identifier, because that is what
  /// recognises a move between two accounts the user owns. This is the same
  /// counterparty with the machine-readable parts folded down to something a
  /// person would write on a receipt.
  static String? _displayName(String? counterparty) {
    var name = counterparty?.trim();
    if (name == null || name.isEmpty) return null;
    name = name.replaceFirst(_beneficiaryTag, '').trim();

    final iban = _ibanPattern.firstMatch(name);
    if (iban != null) {
      final bank = iban.group(1)!.toUpperCase();
      final digits = iban.group(2)!;
      final tail = digits.length <= 4
          ? digits
          : digits.substring(digits.length - 4);
      final prefix = name.substring(0, iban.start).trim();
      // "RAAST IBAN:" adds nothing once the bank is named.
      final label = prefix
          .replaceAll(
            RegExp(r'\b(?:IBAN|RAAST|A\/?C)\b[:\s]*', caseSensitive: false),
            '',
          )
          .trim();
      return label.isEmpty ? '$bank ••$tail' : '$label · $bank ••$tail';
    }
    return name.isEmpty ? null : name;
  }

  /// Amounts that could be the transaction itself, with balance figures set
  /// aside. Falls back to every match when filtering leaves nothing, so an
  /// unusual phrasing degrades to "ambiguous" rather than to a wrong read.
  static List<RegExpMatch> _transactionAmounts(String text) {
    final all = _moneyPattern.allMatches(text).toList();
    if (all.length <= 1) return all;
    final withoutBalances = all
        .where(
          (match) =>
              !_balanceLabelBefore.hasMatch(text.substring(0, match.start)),
        )
        .toList();
    final candidates = withoutBalances.isEmpty ? all : withoutBalances;
    if (candidates.length <= 1) return candidates;
    final withoutCharges = candidates
        .where(
          (match) =>
              !_chargeLabelBefore.hasMatch(text.substring(0, match.start)),
        )
        .toList();
    return withoutCharges.isEmpty ? candidates : withoutCharges;
  }

  String? _counterparty(String text, EntryDirection direction) {
    final match = direction == EntryDirection.debit
        ? (_debitCounterpartyPattern.firstMatch(text) ??
              _merchantPattern.firstMatch(text))
        : _creditCounterpartyPattern.firstMatch(text);
    final name = match?.group(1)?.trim();
    return name == null || name.isEmpty ? null : name;
  }

  ParserResult? _applyDefinition(
    ParserDefinition definition,
    RawObservation observation,
    String transactionAmountText,
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

      // An institution rule locates the amount by scanning forward from its
      // keyword, which lands on the balance when the wording puts the figure
      // first ("PKR 5,000 has been credited to your account. Avl Bal PKR
      // 20,000"). The prescreen already set balance figures aside and left
      // exactly one plausible transaction amount, so that value wins; the
      // rule still supplies direction, counterparty, and reference.
      final ruleAmount = Money.tryParsePkr(named(rule.amountGroup) ?? '');
      final amount = Money.tryParsePkr(transactionAmountText) ?? ruleAmount;
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
        description: _describe(
          observation.title,
          named(rule.counterpartyGroup)?.trim(),
        ),
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
