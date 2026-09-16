import '../../core/money.dart';
import '../../core/money_text.dart';
import '../models/event_candidate.dart';
import '../models/raw_observation.dart';
import '../parsers/pakistan/default_parsers.dart';
import 'parser_definition.dart';

final class NotificationParser {
  const NotificationParser({this.registry, this.currencies = const {'PKR'}});
  final ParserRegistry? registry;

  /// The currencies the owner actually holds.
  ///
  /// Used only to settle a shared marker: "Rs" names four currencies in
  /// general and exactly one for somebody with a single Pakistani account.
  /// A marker that names a currency outright is read whether or not it is
  /// in this set, because a dollar charge on a rupee card is still a real
  /// charge.
  final Set<String> currencies;

  MoneyTextReader get _money => MoneyTextReader(currencies: currencies);

  // Bank SMS nearly always quote the running balance beside the transaction
  // amount ("...debited PKR 80. Avl Bal: PKR 12,345"). Matched against the
  // text *preceding* an amount: a balance label, then anything but a digit,
  // so "Bal: ", "Avbl Bal ", and "new balance is Rs. " all qualify while an
  // earlier, unrelated number cannot be skipped over.
  /// Labels a bank puts in front of a figure that is not the payment.
  ///
  /// Every term here was counted in a corpus of 9,874 real transactional
  /// messages from 25 banks, not guessed. The list used to be `bal` or
  /// `balance` alone, and the single commonest label in that corpus --
  /// "Avlbl Amt", 1,212 occurrences -- contains neither: one bank's
  /// standard message quotes the payment, then "Total Bal", then "Avlbl
  /// Amt", so one of the two balances was always left in and the alert was
  /// thrown out as having two amounts. That single gap accounted for 73%
  /// of everything the parser could not read.
  ///
  /// "Amount" needs the availability word in front of it, because a bare
  /// "amount of Rs.X has been debited" is the payment itself.
  static final RegExp _balanceLabelBefore = RegExp(
    r'(?:\bbal(?:ance)?\b'
    r'|\b(?:avl|avbl|avlbl|aval|avail|available|remaining|closing|opening)\.?\s*(?:amt|amount|lmt|limit)\b'
    r'|\b(?:credit\s+)?(?:lmt|limit)\b)'
    r'[^0-9]{0,15}$',
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

  /// Money leaving an account to become notes in a pocket, rather than to
  /// buy anything.
  ///
  /// Deliberately hard to satisfy. Calling a card payment a withdrawal turns
  /// money that was genuinely spent into money the owner believes is still in
  /// their pocket -- it inflates what the app says is available and hides the
  /// spending underneath. Failing to spot a real withdrawal only leaves the
  /// old behaviour, which is recoverable by hand. So this asks for two
  /// independent signals close together and refuses anything that also smells
  /// of a merchant.
  ///
  /// The signals are structural rather than any one bank's template: banks do
  /// not publish those, and a regex written against a guessed format is a
  /// regex that misfiles real money. Widen it when a real message proves it
  /// too narrow, never in anticipation.
  static bool _looksLikeCash(RawObservation observation) {
    final text = '${observation.title} ${observation.body}'.toLowerCase();
    final withdrawal = RegExp(r'\bwithdraw(?:n|al|als|s)?\b').firstMatch(text);
    if (withdrawal == null) return false;
    // "Cash" or "ATM" has to be near the verb, not merely somewhere in a long
    // message that ends in a marketing line about ATM services.
    final around = text.substring(
      (withdrawal.start - 24).clamp(0, text.length),
      (withdrawal.end + 24).clamp(0, text.length),
    );
    if (!RegExp(r'\b(?:cash|atm)\b').hasMatch(around)) return false;
    // A named merchant, a card terminal or an online purchase means the money
    // bought something, whatever verb the bank chose to describe it with.
    return !RegExp(
      r'\b(?:pos|point\s+of\s+sale|merchant|online|e-?commerce|'
      r'purchase\s+at|paid\s+to)\b',
    ).hasMatch(text);
  }

  static final RegExp _debitWords = RegExp(
    r'\b(?:debit(?:ed)?|paid|sent|spent|purchase(?:d)?|withdrawn?|withdrawal|'
    r'deducted|charged|transfer(?:red)?\s+to|used\s+(?:at|for|on)|'
    // A telco or a merchant app reports a purchase in service words, never in
    // banking ones: "You subscribed to X for Rs 4,500" is money leaving even
    // though no bank verb appears. Past tense only -- "subscribe to our
    // newsletter" is an invitation, and "subscribe now" is already marketing.
    r'subscribed\s+to|renewed|recharged\s+(?:with|for)|topped\s+up\s+with|'
    // "credited to <someone> from your account" is money leaving. Marking
    // the source side as a debit signal makes such wording read as
    // contradictory, so it goes to review instead of being booked as income.
    // Banks abbreviate, and "frm A/c X to Y" is money leaving just as
    // plainly as "from your account". Without the short form, one
    // bank's entire internet-banking receipt read as having no
    // direction at all.
    r'(?:from|frm)\s+(?:your\s+)?(?:a\/?c|acct|account)\b)',
    caseSensitive: false,
  );
  // "Credit Card" names the instrument, not the direction. Counting it as
  // money-in filed card purchases as income.
  static final RegExp _creditWords = RegExp(
    // "transferred from" is money arriving only when what follows is a
    // person. "Rs.X transferred from A/c ...1234 to:UPI/567" is money
    // leaving, and reading it both ways at once made one bank's
    // commonest message contradict itself -- 797 alerts in a 25-bank
    // corpus, every one of them a payment the owner had made.
    r'\b(?:credited|received|deposited|refunded|'
    r'transfer(?:red)?\s+from(?!\s+(?:your\s+)?(?:a\/?c|acct|account)\b)|'
    // A wallet reports money arriving from a linked bank in its own
    // words: "Rs. 10,000 loaded through Northbank-9001 linked account".
    // Nothing in that sentence is a banking verb, so the alert used to
    // read as having no direction at all and went unparsed. The
    // preposition is what settles it, and why this is not simply the word
    // "loaded": "topped up WITH Rs.500" is money leaving, and stays a
    // debit above.
    r'(?:loaded|funded|top(?:ped)?(?:\s*-?\s*up)?|added)\s+'
    r'(?:through|from|via|using)\b|'
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
    // "sent" belongs here and its absence was expensive. A message
    // carrying a link is treated as marketing unless it also reports a
    // settlement, and a wallet's standard receipt -- "Rs.25 sent to X
    // from your a/c. View your past payments at https://..." -- says
    // "sent" and nothing else. Measured on a corpus of 25 banks, that
    // one missing word discarded 201 real payments as advertising.
    r'sent|'
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

  /// Reads [observation] into a candidate transaction.
  ///
  /// [assumeDirection] is the answer to the one question this parser cannot
  /// settle on its own: which way the money went. It is used *only* where the
  /// text gives no usable signal, never to override wording that is clear —
  /// so a person answering "money out" in Review supplies the missing half
  /// and the parser still contributes the amount, the counterparty and the
  /// reference it did manage to read.
  /// Parses, then asks one further question of whatever came back: was this
  /// money leaving to become notes in a pocket?
  ///
  /// Asked here rather than inside each parser because there are several --
  /// a bank-specific definition, the generic fallback -- and a rule that only
  /// some of them apply is a rule that holds for some banks and not others.
  ParserResult parseDetailed(
    RawObservation observation, {
    EntryDirection? assumeDirection,
  }) {
    final result = _parse(observation, assumeDirection: assumeDirection);
    final candidate = result.candidate;
    if (candidate == null ||
        candidate.direction != EntryDirection.debit ||
        candidate.type == CandidateType.cashWithdrawal ||
        !_looksLikeCash(observation)) {
      return result;
    }
    return ParserResult(
      status: result.status,
      parserId: result.parserId,
      parserVersion: result.parserVersion,
      confidence: result.confidence,
      reasons: [
        ...result.reasons,
        'Reads as money withdrawn as cash, not money spent.',
      ],
      candidate: EventCandidate(
        id: candidate.id,
        observation: candidate.observation,
        accountId: candidate.accountId,
        amount: candidate.amount,
        direction: candidate.direction,
        occurredAt: candidate.occurredAt,
        counterparty: candidate.counterparty,
        reference: candidate.reference,
        description: candidate.description,
        confidence: candidate.confidence,
        type: CandidateType.cashWithdrawal,
        parserId: candidate.parserId,
        parserVersion: candidate.parserVersion,
        reasons: candidate.reasons,
      ),
    );
  }

  ParserResult _parse(
    RawObservation observation, {
    EntryDirection? assumeDirection,
  }) {
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
            'No amount was found in this alert.'
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
        amountMatches.single.money,
      );
      if (result != null) return result;
    }

    final money = amountMatches.single.money;
    if (money.isZero) {
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
        // A leading plus is a direction signal in its own right, and in much
        // of the world it is the *only* one: a terse log line says "+1,500
        // RUB" and nothing else. Read from the matched span rather than from
        // a parsed sign, because the sign may sit either side of the marker.
        text
            .substring(amountMatches.single.start, amountMatches.single.end)
            .trimLeft()
            .startsWith('+');
    if (hasDebit == hasCredit && assumeDirection == null) {
      return ParserResult(
        status: ParseStatus.ambiguous,
        parserId: 'pk.generic.fallback',
        parserVersion: 1,
        confidence: 0.3,
        // Which of the two it is matters to the person answering: a word we
        // do not know is a gap the app should close, while two words that
        // disagree is a message only they can settle.
        reasons: [
          hasDebit
              ? 'This says money left and arrived at once.'
              : 'Nothing here says which way the money went.',
        ],
      );
    }
    final direction = assumeDirection != null && hasDebit == hasCredit
        ? assumeDirection
        : (hasDebit ? EntryDirection.debit : EntryDirection.credit);
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

  /// Whether a notification's title is the app talking rather than naming
  /// anybody.
  ///
  /// A bank titles its alerts with its own name, which is a reasonable thing
  /// to call an entry when nothing better is known. A wallet titles them with
  /// copy -- "Off it goes", "Cha-Ching!", "Card in action", "Money sent" --
  /// and using that as the name filled a real ledger with entries called
  /// "Money sent", three in a row, telling the owner nothing about where the
  /// money went.
  ///
  /// Detected by what slogans carry and names do not: a pictograph or an
  /// exclamation mark. Checked by code point rather than by regex so that
  /// Arabic, Urdu and CJK names -- which are names -- are untouched, and so
  /// that no escape has to survive being written into this file.
  static bool _isSlogan(String heading) {
    if (heading.contains('!')) return true;
    for (final rune in heading.runes) {
      final pictographic =
          (rune >= 0x2190 && rune <= 0x2BFF) ||
          (rune >= 0x1F000 && rune <= 0x1FAFF) ||
          rune == 0xFE0F;
      if (pictographic) return true;
    }
    return false;
  }

  static String? _describe(String? title, String? counterparty) {
    final name = _displayName(counterparty);
    if (name != null && name.isNotEmpty) return name;
    final heading = title?.trim();
    if (heading == null || heading.isEmpty) return null;
    // Nothing is better than something wrong here: the ledger already falls
    // back to "Payment" or "Money received", which at least does not pretend
    // to name a party.
    if (_isSlogan(heading)) return null;
    return _hasWords(heading) ? heading : null;
  }

  /// Whether a title contains a word, in any script.
  ///
  /// The point of the check is to reject a title that is only a sender's
  /// short code -- "18258" tells a reader nothing. It used to ask for two
  /// Latin letters, which also rejected every bank that titles its alerts in
  /// Arabic, Urdu, Hindi or Chinese, and named those entries "Payment"
  /// instead. Written over code points rather than as a character class so
  /// it holds for scripts nobody thought to list.
  static bool _hasWords(String heading) {
    var run = 0;
    for (final rune in heading.runes) {
      final separator =
          rune <= 0x2F ||
          (rune >= 0x30 && rune <= 0x40) ||
          (rune >= 0x5B && rune <= 0x60) ||
          (rune >= 0x7B && rune <= 0x7E);
      if (separator) {
        run = 0;
        continue;
      }
      run++;
      if (run >= 2) return true;
    }
    return false;
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
  List<MoneyMatch> _transactionAmounts(String text) {
    final all = _money.findAll(text);
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
    Money transactionAmount,
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
      final ruleAmount = _money.findOnly(named(rule.amountGroup) ?? '')?.money;
      final amount = transactionAmount.isZero ? ruleAmount : transactionAmount;
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
