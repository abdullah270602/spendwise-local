/// Reduces an alert to the sentence its bank always sends, with the parts
/// that change taken out.
///
/// A bank does not write a new message for every payment. It fills in one
/// sentence, over and over — so two alerts from the same bank differ only in
/// their amount, date, account tail and reference. Take those out and what is
/// left is the bank's *template*, and two messages with the same template are
/// the same kind of event.
///
/// This is worth having because of what it makes possible. The app currently
/// learns a bank only when somebody writes a rule for it. With templates it
/// can notice that a source has started sending a shape it has never seen,
/// ask about that shape **once**, and then read every future message of that
/// shape exactly. Ten alerts a person cannot file become one question rather
/// than ten.
///
/// Deliberately not a parser. It extracts nothing and decides nothing; it
/// only says "these two messages are the same sentence". Every slot it masks
/// is one the app can already find by other means, which is what keeps it
/// honest — it is not guessing at structure, it is erasing what it knows.
library;

import '../../core/money_text.dart';

/// What a masked span was.
enum SkeletonSlot { amount, party, account, date, time, reference, number }

String _token(SkeletonSlot slot) => '<${slot.name.toUpperCase()}>';

class TemplateSkeleton {
  const TemplateSkeleton({required this.signature, required this.slots});

  /// The bank's sentence with its variable parts replaced by tokens.
  final String signature;

  /// Which slots were masked, in the order they appeared. Two messages with
  /// the same signature necessarily have the same list.
  final List<SkeletonSlot> slots;

  /// A short, stable key for storing and comparing templates.
  String get fingerprint {
    var hash = 0xcbf29ce484222325;
    for (final unit in signature.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}

class TemplateSkeletonizer {
  const TemplateSkeletonizer({this.reader = const MoneyTextReader()});

  final MoneyTextReader reader;

  /// The other side of the payment: a shop or a person, named after the
  /// preposition that introduces it.
  ///
  /// Masked because it is the one variable part that is *words* rather
  /// than digits, and leaving it in defeated the whole exercise. Measured
  /// on a real ledger, thirty-two alerts produced twenty-eight distinct
  /// templates -- almost no collapse at all -- because every shop and every
  /// payee made a new one. One wallet was sending four sentences and
  /// looked like it was sending twelve.
  ///
  /// The run stops at a word that begins the next clause. Without that,
  /// "from your A/C xxx9001" would read the account as the counterparty,
  /// and "charged at A SHOP for card used" would swallow the rest of the
  /// sentence.
  static const _clauseStops =
      'on|from|as|via|for|in|at|to|of|by|is|was|has|been|your|the|with|'
      'using|against|dated|ref|tid|avl|avbl|bal|balance|'
      // An account is a slot of its own, and letting the name run
      // swallow "A/C xxx9001" hid it from the rule that knows how to
      // read it.
      r'a\/?c|acct|account|card|wallet';

  /// Only `to`, `from`, `at` and `@` introduce a counterparty. `for` and
  /// `by` were tried and dropped: bank messages use them for everything
  /// else -- "for card used", "for info 111...", "for BILL PAYMENT" --
  /// and masking after them erased the constant words that tell two
  /// templates apart.
  static final _party = RegExp(
    r'\b(?:to|from|at|@)\s+'
    '((?:(?!(?:$_clauseStops)\\b)[A-Za-z0-9&.\'*#+/-]+)'
    '(?:\\s+(?:(?!(?:$_clauseStops)\\b)[A-Za-z0-9&.\'*#+/-]+))*)',
    caseSensitive: false,
  );

  /// A masked account tail as banks actually print one: some masking
  /// character, then the digits they were willing to show. Matched before
  /// bare numbers, because `xxx4007` is an account and `4007` alone might be
  /// anything.
  static final _account = RegExp(
    r'(?:[*xX••]{2,}|\bA\/?C#?\s*|\bAcct\.?\s*|\bAccount\s*)'
    r'[-\s]*[*xX••]*\d{3,}',
    caseSensitive: false,
  );

  /// A reference, which banks label even when they label nothing else.
  static final _reference = RegExp(
    r'\b(?:TID|Trx(?:\s*ID)?|Tx\s*ID|Ref(?:erence)?|RRN|Slip|Auth)\b'
    r'[:\s#-]*[A-Z0-9-]{4,}',
    caseSensitive: false,
  );

  /// Dates in the shapes bank messages use, numeric or with a month name.
  /// Dates in the shapes bank messages use, numeric or with a month name.
  ///
  /// The separators are optional because one large bank writes "on 02may22"
  /// with none at all -- which made a fresh template for every calendar day
  /// and turned four sentences into several hundred.
  static final _date = RegExp(
    r'\b\d{1,4}[-/.]\d{1,2}[-/.]\d{1,4}\b'
    r'|\b\d{1,2}[-\s]?'
    r'(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*'
    r'[-\s]?\d{2,4}\b',
    caseSensitive: false,
  );

  /// A payment handle: the `name@bank` address UPI and its relatives use.
  ///
  /// One identifier, and it has to be masked as one. Split across the `@`
  /// it made a new template for every payer: one bank sent 573 messages
  /// that reduced to 457 templates, and its single commonest sentence
  /// appeared 86 times under two different signatures purely because the
  /// handles differed.
  static final _handle = RegExp(
    r'(?<![A-Za-z0-9@.])[A-Za-z0-9][A-Za-z0-9._-]{1,}@[A-Za-z][A-Za-z0-9]{1,}',
  );

  /// An IBAN, or the masked head of one. Two alerts differing only in the
  /// payee's IBAN are the same sentence, and leaving the digits in made
  /// them two templates.
  ///
  /// The shape is fixed by the standard: a country code, two check digits,
  /// then the bank's own identifier -- and banks print that much even when
  /// they mask the rest.
  static final _iban = RegExp(
    r'(?<![A-Za-z0-9])[A-Za-z]{2}[0-9]{2}[A-Za-z]{4}[0-9A-Za-z*\u2022]{2,}',
  );

  static final _time = RegExp(r'\b\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AaPp][Mm])?');

  /// Anything else long enough to be an identifier rather than a quantity.
  static final _number = RegExp(r'\b\d{3,}\b');

  static final _whitespace = RegExp(r'\s+');

  TemplateSkeleton of(String text) {
    // Masked in a deliberate order, longest-lived first: an amount knows its
    // own span exactly, an account tail carries its masking characters, and
    // a bare run of digits is the last resort. Reversed so each replacement
    // cannot disturb the offsets of the ones still to come.
    final spans = <({int start, int end, SkeletonSlot slot})>[];

    void claim(int start, int end, SkeletonSlot slot) {
      for (final taken in spans) {
        if (start < taken.end && end > taken.start) return;
      }
      spans.add((start: start, end: end, slot: slot));
    }

    for (final match in reader.findAll(text)) {
      claim(match.start, match.end, SkeletonSlot.amount);
    }
    // Ordering matters twice over. Dates, times and references are claimed
    // first because they are certain, and without that "on <date> at 12:58"
    // read the clock as a payee. The name run is claimed next, ahead of the
    // account and bare-number rules, so an identifier written inside a
    // payee's name -- "A.PAYEE PK00BANKxx123" -- stays part of the name
    // instead of being split into three tokens.
    for (final entry in <(RegExp, SkeletonSlot)>[
      (_reference, SkeletonSlot.reference),
      (_date, SkeletonSlot.date),
      (_time, SkeletonSlot.time),
    ]) {
      for (final match in entry.$1.allMatches(text)) {
        claim(match.start, match.end, entry.$2);
      }
    }
    // Before the name run: a handle sits exactly where a payee's name sits,
    // and the name rule would otherwise take half of it.
    for (final match in _handle.allMatches(text)) {
      claim(match.start, match.end, SkeletonSlot.account);
    }
    for (final match in _party.allMatches(text)) {
      final name = match.group(1);
      if (name == null || name.trim().isEmpty) continue;
      final at = match.start + match[0]!.indexOf(name);
      claim(at, at + name.length, SkeletonSlot.party);
    }
    for (final entry in <(RegExp, SkeletonSlot)>[
      (_iban, SkeletonSlot.account),
      (_account, SkeletonSlot.account),
      (_number, SkeletonSlot.number),
    ]) {
      for (final match in entry.$1.allMatches(text)) {
        claim(match.start, match.end, entry.$2);
      }
    }

    spans.sort((a, b) => a.start.compareTo(b.start));
    final buffer = StringBuffer();
    var cursor = 0;
    for (final span in spans) {
      buffer
        ..write(text.substring(cursor, span.start))
        ..write(_token(span.slot));
      cursor = span.end;
    }
    buffer.write(text.substring(cursor));

    return TemplateSkeleton(
      signature: buffer
          .toString()
          .toLowerCase()
          .replaceAll(_whitespace, ' ')
          .trim(),
      slots: [for (final span in spans) span.slot],
    );
  }
}
