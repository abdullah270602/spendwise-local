import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/money.dart';

/// Amounts a person types into a field, as opposed to amounts a bank writes
/// into a sentence.
///
/// This file used to test `Money.parsePkr`, which took a marker-and-number
/// string and always multiplied by a hundred. Reading a bank's sentence is
/// now `MoneyTextReader`'s job and is tested in `money_text_test.dart`; what
/// is left here is the other half — a field that is already labelled with a
/// currency, where the only question is how many minor units that currency
/// has.
///
/// That question had no answer before. Every typed amount was multiplied by
/// a hundred, so an opening balance in yen was entered a hundred times too
/// large and one in dinars ten times too small, in a field that was already
/// displaying the right currency code beside it.
void main() {
  group('a typed amount is read in the currency of its field', () {
    test('two decimals, as most currencies have', () {
      expect(
        Money.tryParseTyped('10,000', currency: 'PKR')!.minorUnits,
        1000000,
      );
      expect(
        Money.tryParseTyped('1,250.5', currency: 'PKR')!.minorUnits,
        125050,
      );
      expect(Money.tryParseTyped('42', currency: 'PKR')!.minorUnits, 4200);
      expect(
        Money.tryParseTyped('-500.25', currency: 'PKR')!.minorUnits,
        -50025,
      );
    });

    test('none at all, for a currency that has no minor unit', () {
      // Five hundred yen is five hundred, not fifty thousand.
      expect(Money.tryParseTyped('500', currency: 'JPY')!.minorUnits, 500);
      expect(
        Money.tryParseTyped('1,014,145', currency: 'KRW')!.minorUnits,
        1014145,
      );
    });

    test('three, for a currency that counts in thousandths', () {
      expect(Money.tryParseTyped('1.250', currency: 'KWD')!.minorUnits, 1250);
      expect(Money.tryParseTyped('12', currency: 'BHD')!.minorUnits, 12000);
    });

    test('the currency travels with the amount', () {
      expect(Money.tryParseTyped('42', currency: 'AED')!.currency, 'AED');
    });

    test('a code the table has never heard of is assumed to have two', () {
      // The commonest case and the least damaging guess.
      expect(Money.tryParseTyped('42', currency: 'XYZ')!.minorUnits, 4200);
    });
  });

  group('what a field refuses', () {
    test('anything that is not a plain number', () {
      for (final value in ['', 'abc', '10.00.00', '-+10', '1 000', 'PKR 10']) {
        expect(
          Money.tryParseTyped(value, currency: 'PKR'),
          isNull,
          reason: value,
        );
      }
    });

    test('more decimals than the currency has', () {
      expect(Money.tryParseTyped('10.234', currency: 'PKR'), isNull);
      expect(
        Money.tryParseTyped('10.234', currency: 'KWD')!.minorUnits,
        10234,
        reason: 'three decimals is exactly right for a dinar',
      );
    });

    test('a decimal at all, where the currency has none', () {
      expect(Money.tryParseTyped('500.50', currency: 'JPY'), isNull);
    });
  });
}
