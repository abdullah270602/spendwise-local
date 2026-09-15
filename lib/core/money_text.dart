import 'currency.dart';
import 'money.dart';

/// Finding money inside a sentence, in any of the ways the world writes it.
///
/// Separate from [Money] because this is the messy half: [Money] is an exact
/// integer, and this is the part that has to decide whether `1,234` means one
/// thousand or one and a bit.
///
/// ## The decimal problem
///
/// `1,234.56` and `1.234,56` are the same amount written by different halves
/// of the world, and `1,234` on its own is genuinely ambiguous — a thousand
/// two hundred and thirty-four, or one point two three four. The rule used
/// here, in order:
///
/// 1. If both separators appear, the **rightmost** one is the decimal point
///    and the other is grouping. This is unambiguous and needs no locale.
/// 2. If one separator appears once and is followed by exactly three digits,
///    it is grouping — unless the currency has three minor digits, where
///    `KWD 1.250` really is one dinar two hundred and fifty fils.
/// 3. If one separator appears once followed by one or two digits, it is a
///    decimal point.
/// 4. If a separator repeats, it is grouping.
///
/// The one case left unresolved is a three-digit group under a three-digit
/// currency, and there the currency's own convention decides — which is the
/// only information available.
class MoneyMatch {
  const MoneyMatch({
    required this.money,
    required this.start,
    required this.end,
    required this.marker,
    required this.markerLeads,
  });

  final Money money;

  /// Where the whole amount — marker included — sits in the source text, so a
  /// caller can tell an amount from the balance quoted beside it.
  final int start;
  final int end;

  /// The spelling that named the currency, as written.
  final String marker;

  /// Whether the marker came before the number. Ninety per cent of the
  /// world's bank messages put it after.
  final bool markerLeads;
}

/// Reads amounts out of free text.
class MoneyTextReader {
  /// [currencies] is what the owner actually holds, and it is what resolves
  /// a shared marker: `Rs` names four currencies in general and exactly one
  /// for somebody with a single Pakistani account. An empty set means "trust
  /// only markers that name a currency outright".
  const MoneyTextReader({this.currencies = const {'PKR'}});

  final Set<String> currencies;

  static final _digits = RegExp(r'[0-9]');

  /// A number with optional grouping and decimals. Deliberately
  /// permissive about which separator is which; [_amountOf] settles that
  /// afterwards.
  ///
  /// The grouped alternative demands at least one group, and comes first.
  /// Written as optional it matched a *prefix* of an ungrouped run --
  /// "1001" came back as "100" -- which silently divided amounts by ten.
  /// Groups of two are allowed as well as three, because Indian lakh
  /// grouping writes 3,65,485.97.
  static const _numberPattern =
      r'\d{1,3}(?:[.,     ]\d{2,3})+(?:[.,]\d{1,3})?|\d+(?:[.,]\d{1,3})?';

  /// Every currency whose markers may be trusted here, longest marker first
  /// so `Rs.` is tried before `R` and `US$` before `$`.
  List<({String marker, Currency currency})> _markers() {
    final known = currencies.map((code) => code.toUpperCase()).toSet();
    final out = <({String marker, Currency currency})>[];
    for (final currency in currencyTable) {
      for (final marker in currency.markers) {
        out.add((marker: marker, currency: currency));
      }
      // A shared spelling is only usable when the ledger has narrowed the
      // field: with accounts in both PKR and INR, "Rs" still names neither.
      if (!known.contains(currency.code)) continue;
      final rivals = currencyTable.where(
        (other) =>
            other.code != currency.code &&
            known.contains(other.code) &&
            other.ambiguousMarkers.any(currency.ambiguousMarkers.contains),
      );
      if (rivals.isNotEmpty) continue;
      for (final marker in currency.ambiguousMarkers) {
        out.add((marker: marker, currency: currency));
      }
    }
    out.sort((a, b) => b.marker.length.compareTo(a.marker.length));
    return out;
  }

  RegExp _pattern() {
    final alternatives = _markers()
        .map((entry) => RegExp.escape(entry.marker))
        .join('|');
    // Both orders in one pass, so a message that quotes the amount one way
    // and the balance the other is still read consistently.
    return RegExp(
      // The sign may sit on either side of a leading marker: banks
      // write both "-PKR 500" and "PKR -500", and reading only one of
      // them turns a refund into a charge.
      // The sign and any space after it are one optional unit, so an
      // absent sign does not drag the match back onto the space before
      // the marker.
      '(?:(?:(?<preSign>[+-])\\s*)?(?<lead>$alternatives)\\s*(?<leadSign>[+-])?'
      '\\s*(?<leadNumber>$_numberPattern)'
      '|(?<trailSign>[+-])?\\s*(?<trailNumber>$_numberPattern)'
      // A marker with a number after it belongs to that number, not to
      // the one before it. Without this, a message opening with the
      // sender's shortcode -- "18258 PKR 40,000 received..." -- read
      // "18258 PKR" as the amount and then found a second one, and the
      // whole alert was thrown out as ambiguous.
      '\\s*(?<trail>$alternatives)(?!\\s*[+-]?\\s*\\d))',
      caseSensitive: false,
    );
  }

  /// Every amount in [text], in the order they appear.
  List<MoneyMatch> findAll(String text) {
    final byMarker = {
      for (final entry in _markers()) entry.marker.toLowerCase(): entry.currency,
    };
    final matches = <MoneyMatch>[];
    for (final match in _pattern().allMatches(text)) {
      final leads = match.namedGroup('lead') != null;
      final marker = leads ? match.namedGroup('lead')! : match.namedGroup('trail')!;
      final number = leads
          ? match.namedGroup('leadNumber')!
          : match.namedGroup('trailNumber')!;
      final sign = leads
          ? (match.namedGroup('preSign') ?? match.namedGroup('leadSign'))
          : match.namedGroup('trailSign');
      final currency = byMarker[marker.toLowerCase()];
      if (currency == null) continue;
      // A marker glued to the end of a word ("...RSVP") is not a currency,
      // and a number glued to the front of one is not an amount.
      // Located rather than computed: an optional sign and optional
      // spacing make the marker's offset within the match variable,
      // and guessing it once pointed this check at a space and read
      // the letter before it as if it were glued to the marker.
      final markerAt =
          match.start +
          match[0]!.toLowerCase().indexOf(marker.toLowerCase());
      if (leads && markerAt > 0 && _isWordish(text[markerAt - 1])) {
        continue;
      }
      final minor = _amountOf(number, currency);
      if (minor == null) continue;
      matches.add(
        MoneyMatch(
          money: Money(
            minorUnits: (sign == '-' ? -1 : 1) * minor,
            currency: currency.code,
          ),
          start: match.start,
          end: match.end,
          marker: marker,
          markerLeads: leads,
        ),
      );
    }
    return matches;
  }

  /// The single amount in [text], or null when there is none or more than
  /// one. Kept because "exactly one amount" is the app's oldest safety rule:
  /// a message quoting two numbers is usually quoting a balance, and reading
  /// the wrong one is worse than reading neither.
  MoneyMatch? findOnly(String text) {
    final all = findAll(text);
    return all.length == 1 ? all.single : null;
  }

  static bool _isWordish(String character) =>
      RegExp(r'[A-Za-z0-9]').hasMatch(character);

  /// Turns the digits of a written number into minor units.
  int? _amountOf(String raw, Currency currency) {
    final text = raw.trim();
    if (!_digits.hasMatch(text)) return null;

    final lastComma = text.lastIndexOf(',');
    final lastDot = text.lastIndexOf('.');
    var decimalAt = -1;

    if (lastComma >= 0 && lastDot >= 0) {
      // Rule 1: whichever comes last is the decimal point.
      decimalAt = lastComma > lastDot ? lastComma : lastDot;
    } else if (lastComma >= 0 || lastDot >= 0) {
      final only = lastComma >= 0 ? lastComma : lastDot;
      final separator = text[only];
      final repeats = separator.allMatches(text).length > 1;
      final trailing = text.length - only - 1;
      if (repeats) {
        // Rule 4.
        decimalAt = -1;
      } else if (trailing == 3) {
        // Rule 2: three digits reads as a group, unless the currency counts
        // in thousandths and so genuinely writes three decimals.
        decimalAt = currency.minorDigits == 3 ? only : -1;
      } else if (trailing >= 1 && trailing <= 3) {
        // Rule 3.
        decimalAt = only;
      }
    }

    final wholeText = decimalAt < 0 ? text : text.substring(0, decimalAt);
    final fractionText = decimalAt < 0 ? '' : text.substring(decimalAt + 1);
    final whole = int.tryParse(wholeText.replaceAll(RegExp(r'[^0-9]'), ''));
    if (whole == null) return null;

    if (currency.minorDigits == 0) {
      // A currency with no minor unit cannot carry a fraction. If a message
      // writes one anyway the separator was grouping, and reading it as a
      // decimal would divide the amount by a thousand.
      final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
      return int.tryParse(digits);
    }

    if (fractionText.isEmpty) return whole * currency.multiplier;
    final normalized = fractionText
        .padRight(currency.minorDigits, '0')
        .substring(0, currency.minorDigits);
    final fraction = int.tryParse(normalized);
    if (fraction == null) return null;
    return whole * currency.multiplier + fraction;
  }
}
