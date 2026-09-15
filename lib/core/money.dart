import 'currency.dart';

/// An exact monetary value stored as minor units (paisa for PKR).
final class Money implements Comparable<Money> {
  const Money({required this.minorUnits, this.currency = 'PKR'})
    : assert(currency != '');

  const Money.pkr(this.minorUnits) : currency = 'PKR';

  final int minorUnits;
  final String currency;

  bool get isNegative => minorUnits < 0;
  bool get isZero => minorUnits == 0;
  Money get absolute => Money(minorUnits: minorUnits.abs(), currency: currency);

  /// Reads an amount a person typed into a field, in the currency that
  /// field is labelled with.
  ///
  /// Separate from reading a bank's sentence, which is [MoneyTextReader]'s
  /// job: there is no marker to find and no ambiguity about which currency
  /// is meant, because the field says so. What there is, and what the old
  /// code got wrong, is how many minor units the currency has. Every typed
  /// amount was multiplied by a hundred, so a yen balance was entered a
  /// hundred times too large and a dinar balance ten times too small -- in
  /// a field that was already displaying the right currency code beside it.
  static Money? tryParseTyped(String input, {required String currency}) {
    final digits = minorDigitsFor(currency);
    // A currency with no minor unit cannot take a decimal at all, and
    // `{1,0}` is not a valid quantifier, so the fraction group only exists
    // when there is a fraction to hold.
    final fraction = digits == 0 ? '' : '(?:[.,](\\d{1,$digits}))?';
    final match = RegExp(
      '^\\s*([+-])?\\s*((?:\\d{1,3}(?:,\\d{3})+)|\\d+)'
      '$fraction'
      '\\s*\$',
    ).firstMatch(input);
    if (match == null) return null;
    final whole = int.tryParse(match.group(2)!.replaceAll(',', ''));
    if (whole == null) return null;
    final fractionText = digits == 0 ? null : match.group(3);
    final minor = fractionText == null
        ? 0
        : int.parse(fractionText.padRight(digits, '0'));
    var multiplier = 1;
    for (var i = 0; i < digits; i++) {
      multiplier *= 10;
    }
    final sign = match.group(1) == '-' ? -1 : 1;
    return Money(
      minorUnits: sign * ((whole * multiplier) + minor),
      currency: currency,
    );
  }

  Money operator +(Money other) {
    _requireSameCurrency(other);
    return Money(minorUnits: minorUnits + other.minorUnits, currency: currency);
  }

  Money operator -(Money other) {
    _requireSameCurrency(other);
    return Money(minorUnits: minorUnits - other.minorUnits, currency: currency);
  }

  void _requireSameCurrency(Money other) {
    if (currency != other.currency) {
      throw ArgumentError('Cannot combine $currency and ${other.currency}');
    }
  }

  @override
  int compareTo(Money other) {
    _requireSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      minorUnits == other.minorUnits &&
      currency == other.currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  @override
  String toString() {
    final absoluteValue = minorUnits.abs();
    final whole = absoluteValue ~/ 100;
    final fraction = (absoluteValue % 100).toString().padLeft(2, '0');
    return '${minorUnits < 0 ? '-' : ''}$currency $whole.$fraction';
  }
}
