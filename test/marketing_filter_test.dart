import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/domain.dart';

/// Promotional traffic is noise, not a decision. These lock the line between
/// "advert" and "a real alert that happens to use a marketing word", because
/// getting it wrong in the greedy direction silently eats real money.
void main() {
  RawObservation alert(String body) => RawObservation(
    id: 'obs',
    kind: ObservationKind.notification,
    observedAt: DateTime.utc(2026, 9, 6),
    body: body,
    accountId: 'meezan',
    sourcePackage: 'com.meezan',
  );

  ParserResult parse(String body) =>
      const NotificationParser().parseDetailed(alert(body));

  group('dropped outright, never queued for review', () {
    const adverts = [
      'Congratulations! You could win PKR 500,000 in our lucky draw. '
          'T&Cs apply.',
      'Limited time offer: get 20% cashback on all groceries. Apply now!',
      'Refer a friend and earn PKR 1,000 referral bonus. Download the app '
          'today.',
      'Hurry! Last chance to activate now and stand a chance to win a car.',
      'Spend PKR 5,000 this month and PKR 500 cashback will be credited to '
          'your account. T&Cs apply.',
    ];

    for (final body in adverts) {
      test('"${body.substring(0, 34)}…"', () {
        final result = parse(body);
        expect(result.status, ParseStatus.unsupported);
        expect(result.parserId, 'pk.marketing');
      });
    }
  });

  group('real alerts survive a marketing word', () {
    test('a settled cashback credit is money in', () {
      final result = parse(
        'PKR 250.00 cashback credited to your account 1234. '
        'Avbl Bal PKR 9,250.00',
      );
      expect(result.status, ParseStatus.parsed);
      expect(result.candidate?.direction, EntryDirection.credit);
    });

    test('a discounted purchase is still a purchase', () {
      final result = parse(
        'PKR 1,060.00 debited at SAMPLE SUPERMARKET after discount. '
        'Avbl Bal PKR 8,190.00',
      );
      expect(result.status, ParseStatus.parsed);
      expect(result.candidate?.direction, EntryDirection.debit);
    });

    test('salary with terms boilerplate is not an advert', () {
      final result = parse(
        'PKR 150,000.00 has been credited to your account 9001. '
        'Closing balance PKR 120,450.00',
      );
      expect(result.status, ParseStatus.parsed);
    });
  });

  group('the real pile, from the device', () {
    test('a Roman Urdu loan advert is marketing', () {
      final result = parse(
        '8558 Rs.4000 tak ka loan hasil karein! Aasani se cash loan ke liye '
        'JazzCash App use karein ya *786*4# dial karein! '
        'https://www.example.com/promo ZONG',
      );
      expect(result.status, ParseStatus.unsupported);
      expect(result.parserId, 'pk.marketing');
    });

    test('a telco recharge advert is marketing', () {
      final result = parse(
        'ZONG Zong Super Card sy 10GB Data aur bohat kuch 30 din kly ab sirf '
        'Rs1600 recharge me. Activation klye 310 mila kr',
      );
      expect(result.status, ParseStatus.unsupported);
      expect(result.parserId, 'pk.marketing');
    });

    test('a purchase OTP is not the purchase', () {
      final result = parse(
        'Meezan Bank Your e-commerce transaction OTP is 3609 for amount '
        'PKR 2086.20 using Meezan Card 9004 at DEMO PHARMACY. '
        'Valid for 5 mins. ZONG',
      );
      expect(result.status, ParseStatus.unsupported);
      expect(
        result.parserId,
        'pk.otp',
        reason: 'the bank sends the settlement separately; booking both '
            'double-counts the purchase',
      );
    });

    test('a transfer fee no longer hides the transfer', () {
      final result = parse(
        'Meezan Bank PKR 40,000.00 sent to TEST USER ASKARI-xxxBANK from '
        'your A/C xxx9001 of MAIN BRANCH LHR on 04-Sep-2026 at 13:26 '
        'Fee: Rs.15.00 TID:100003 UAN 021111000000 ZONG',
      );
      expect(
        result.status,
        ParseStatus.parsed,
        reason: 'a charge quoted beside the amount is not a second candidate',
      );
      expect(result.candidate?.direction, EntryDirection.debit);
      expect(result.candidate?.amount.minorUnits, 4000000);
    });
  });

  test('an advert with no amount is dropped as marketing, not as unreadable', () {
    // Both paths end in "ignored", but the reason is what the user reads.
    final result = parse('Congratulations! Big prizes await. Dial *123 now.');
    expect(result.parserId, 'pk.marketing');
    expect(result.reasons.single, contains('Promotional'));
  });
}
