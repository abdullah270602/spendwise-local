import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/money_text.dart';

/// Reading money the way the rest of the world writes it.
///
/// The amount pattern this replaces matched a currency marker only *before*
/// the number, and multiplied by a hundred whatever the currency was. A
/// survey of 5,629 real bank-message formats across seventy countries found
/// the marker *after* the number in 90% of them, and ISO 4217 has currencies
/// with no minor unit and currencies with three.
///
/// So the old reader was wrong three ways outside Pakistan: it could not see
/// the amount at all in most of the world, and where it could, it was out by
/// a factor of a hundred for yen and by a factor of ten for dinars.
void main() {
  const pk = MoneyTextReader();

  group('the marker may come first or last', () {
    test('first, as Pakistan and India write it', () {
      final match = pk.findOnly('Meezan Bank PKR 5,000.00 sent to A PAYEE')!;
      expect(match.money.minorUnits, 500000);
      expect(match.money.currency, 'PKR');
      expect(match.markerLeads, isTrue);
    });

    test('last, as most of the world writes it', () {
      const reader = MoneyTextReader(currencies: {'RUB'});
      final match = reader.findOnly('Oplata 1.500,00 RUB')!;
      expect(match.money.minorUnits, 150000);
      expect(match.money.currency, 'RUB');
      expect(
        match.markerLeads,
        isFalse,
        reason: 'this spelling used to be invisible to the parser entirely',
      );
    });

    test('glued to the number, with no space at all', () {
      const reader = MoneyTextReader(currencies: {'THB'});
      final match = reader.findOnly('Balance 706.96THB')!;
      expect(match.money.minorUnits, 70696);
    });
  });

  group('a currency with no minor unit is not multiplied by a hundred', () {
    test('yen', () {
      const reader = MoneyTextReader(currencies: {'JPY'});
      expect(reader.findOnly('JPY 500')!.money.minorUnits, 500);
    });

    test('dong, written with dot grouping', () {
      // "325.440" is three hundred and twenty-five thousand dong, not three
      // hundred and twenty-five. A currency with no fraction cannot have one.
      const reader = MoneyTextReader(currencies: {'VND'});
      expect(reader.findOnly('PS: -325.440VND')!.money.minorUnits, -325440);
    });

    test('won, written with comma grouping', () {
      const reader = MoneyTextReader(currencies: {'KRW'});
      expect(reader.findOnly('잔액 1,014,145원')!.money.minorUnits, 1014145);
    });
  });

  group('a three-digit currency keeps its third digit', () {
    test('a dinar and a quarter is 1,250 fils, not 125', () {
      const reader = MoneyTextReader(currencies: {'KWD'});
      expect(reader.findOnly('KWD 1.250')!.money.minorUnits, 1250);
    });

    test('and a whole number still scales by a thousand', () {
      const reader = MoneyTextReader(currencies: {'BHD'});
      expect(reader.findOnly('BHD 12')!.money.minorUnits, 12000);
    });
  });

  group('which separator is the decimal point', () {
    test('when both appear, the last one wins', () {
      const reader = MoneyTextReader(currencies: {'EUR', 'USD'});
      expect(reader.findOnly('EUR 1.234,56')!.money.minorUnits, 123456);
      expect(reader.findOnly('USD 1,234.56')!.money.minorUnits, 123456);
    });

    test('a lone separator before three digits is grouping', () {
      // The case that has to be right: "Rs 5,000" is five thousand rupees,
      // and reading it as five is the worst possible failure.
      expect(pk.findOnly('Rs 5,000')!.money.minorUnits, 500000);
    });

    test('a lone separator before two digits is a decimal point', () {
      expect(pk.findOnly('Rs 5,00')!.money.minorUnits, 500);
    });

    test('a repeated separator is always grouping', () {
      const reader = MoneyTextReader(currencies: {'IDR'});
      expect(reader.findOnly('IDR 2.373.851')!.money.minorUnits, 237385100);
    });

    test('Indian lakh grouping survives', () {
      const reader = MoneyTextReader(currencies: {'INR'});
      expect(reader.findOnly('INR 3,65,485.97')!.money.minorUnits, 36548597);
    });
  });

  group('a shared marker is resolved by what the owner actually holds', () {
    test('one rupee account makes "Rs" unambiguous', () {
      expect(pk.findOnly('Rs. 1,250.50')!.money.currency, 'PKR');
    });

    test('accounts in two rupee currencies leave it unresolved', () {
      // "Rs" names neither, and guessing would file an Indian payment
      // against a Pakistani account or the reverse.
      const reader = MoneyTextReader(currencies: {'PKR', 'INR'});
      expect(reader.findOnly('Rs. 1,250.50'), isNull);
      expect(
        reader.findOnly('INR 1,250.50')!.money.currency,
        'INR',
        reason: 'the ISO code names one currency and always did',
      );
    });

    test('a marker for a currency the owner does not hold is still read', () {
      // Somebody with only a PKR account can still be shown a dollar charge;
      // refusing to read it would lose the transaction entirely.
      expect(pk.findOnly('Charged USD 19.35')!.money.currency, 'USD');
    });
  });

  group('what must not be read as money', () {
    test('a marker glued to the end of a word is not a currency', () {
      expect(pk.findAll('Please RSVP 5 days before'), isEmpty);
    });

    test('a bare number is not an amount', () {
      expect(pk.findAll('Your OTP is 447120'), isEmpty);
    });

    test('two amounts are reported, and findOnly refuses to choose', () {
      // A bank quoting the balance beside the payment is the oldest trap in
      // this app. Both are found; picking between them is somebody else's
      // job, and guessing here would pick the balance about half the time.
      const text = 'PKR 211.00 charged at A SHOP. Avl Bal: PKR 12,345.00';
      expect(pk.findAll(text), hasLength(2));
      expect(pk.findOnly(text), isNull);
      expect(pk.findAll(text).first.money.minorUnits, 21100);
    });

    test('the span is reported so a caller can tell them apart', () {
      const text = 'PKR 211.00 charged. Avl Bal: PKR 12,345.00';
      final all = pk.findAll(text);
      expect(all.first.start, 0);
      expect(
        text.substring(all.last.start, all.last.end),
        'PKR 12,345.00',
        reason:
            'the balance label sits just before this span, which is how '
            'it gets excluded',
      );
    });
  });

  group('two readings the old PKR-only parser refused', () {
    // Recorded rather than quietly changed. `Money.tryParsePkr` rejected
    // both of these as malformed; the new reader accepts both, and in each
    // case the new answer is the better one. Kept here so a future reader
    // finds the decision instead of rediscovering the difference.

    test('a dot before three digits is grouping, not a fraction', () {
      // PKR has two minor digits, so ".234" cannot be a rupee fraction. The
      // only reading left is a thousands group, and the old parser threw the
      // amount away rather than take it.
      expect(pk.findOnly('PKR 1.234')!.money.minorUnits, 123400);
    });

    test('a comma before two digits is a fraction, not a broken group', () {
      // Half the world writes ten rupees as "10,00". The old parser demanded
      // three digits after a comma and rejected this outright, losing the
      // transaction; reading it as ten is both likelier and safer than
      // reading nothing.
      expect(pk.findOnly('PKR 10,00')!.money.minorUnits, 1000);
    });
  });

  group('a marker binds to the number that follows it', () {
    test('a sender shortcode before the marker is not the amount', () {
      // Found by re-running a real ledger through the new reader. Pakistani
      // bank SMS arrive with the sender's shortcode as the first word --
      // "18258 PKR 40,000 received..." -- and reading the marker backwards
      // gave "18258 PKR", then a second amount, then the whole alert thrown
      // out as ambiguous. The transfer it belonged to silently stopped
      // pairing.
      final match = pk.findOnly(
        '18258 PKR 40,000 received from A PAYEE in your A/C *4988',
      )!;
      expect(match.money.minorUnits, 4000000);
      expect(match.markerLeads, isTrue);
    });

    test('but a trailing marker with nothing after it still counts', () {
      const reader = MoneyTextReader(currencies: {'RUB'});
      final match = reader.findOnly('Spisanie 1.500,00 RUB uspeshno')!;
      expect(match.money.minorUnits, 150000);
      expect(match.markerLeads, isFalse);
    });
  });

  test('a single-letter marker is only trusted by someone who holds it', () {
    // "R" is the rand, and also the first letter of half the words in a bank
    // message. Left unconditional it matched inside ordinary prose.
    const withRand = MoneyTextReader(currencies: {'ZAR'});
    expect(withRand.findOnly('R 500.00 debited')!.money.currency, 'ZAR');
    expect(pk.findAll('R 500.00 debited'), isEmpty);
  });

  test('a negative sign is kept on either side of the marker', () {
    expect(pk.findOnly('-PKR 500')!.money.minorUnits, -50000);
    expect(pk.findOnly('PKR -500')!.money.minorUnits, -50000);
  });
}
