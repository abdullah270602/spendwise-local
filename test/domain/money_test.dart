import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/money.dart';

void main() {
  group('Money PKR parsing', () {
    test('accepts supported explicit forms exactly', () {
      expect(Money.parsePkr('PKR 10,000').minorUnits, 1000000);
      expect(Money.parsePkr('Rs. 1,250.5').minorUnits, 125050);
      expect(Money.parsePkr('-PKR 500.25').minorUnits, -50025);
      expect(Money.parsePkr('PKR -500').minorUnits, -50000);
      expect(Money.parsePkr('₨ 42').minorUnits, 4200);
    });

    test('rejects ambiguous or malformed values', () {
      for (final value in [
        '1000',
        r'$ 100',
        'PKR 10,00',
        'PKR 1.234',
        'PKR -+10',
        'USD 10',
      ]) {
        expect(Money.tryParsePkr(value), isNull, reason: value);
      }
    });
  });
}
