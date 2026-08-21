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

  /// Parses explicit Pakistani-rupee amounts such as `PKR 10,000`,
  /// `Rs. 1,250.50`, and `-PKR 500`. Bare numbers and malformed grouping are
  /// deliberately rejected so notification prose is not mistaken for money.
  static Money? tryParsePkr(String input) {
    final match = RegExp(
      r'^\s*([+-])?\s*(?:PKR|Rs\.?|₨)\s*([+-])?\s*((?:\d{1,3}(?:,\d{3})+)|\d+)(?:\.(\d{1,2}))?\s*$',
      caseSensitive: false,
    ).firstMatch(input);
    if (match == null) return null;
    final leadingSign = match.group(1);
    final trailingSign = match.group(2);
    if (leadingSign != null && trailingSign != null) return null;
    final whole = int.tryParse(match.group(3)!.replaceAll(',', ''));
    if (whole == null) return null;
    final fractionText = match.group(4);
    final fraction = fractionText == null
        ? 0
        : int.parse(fractionText.padRight(2, '0'));
    final sign = (leadingSign ?? trailingSign) == '-' ? -1 : 1;
    return Money.pkr(sign * ((whole * 100) + fraction));
  }

  static Money parsePkr(String input) =>
      tryParsePkr(input) ??
      (throw FormatException('Invalid PKR amount', input));

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
