import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/domain.dart';

/// Real alerts from a real Pakistani phone, verbatim.
///
/// The parser is the product. Every alert here was, at some point, either
/// dropped on the floor or filed wrong, so each one stays as a regression:
/// if a change to the engine breaks one of these, it broke somebody's ledger.
///
/// The distinction these lock in is between the *counterparty* and the
/// *display name*. The counterparty keeps every identifier the bank printed,
/// because that is what recognises a move between two accounts the user owns.
/// The display name is what a person would write on a receipt.
void main() {
  ParserResult read(String body, {String title = 'Bank'}) =>
      const NotificationParser().parseDetailed(
        RawObservation(
          id: 'obs',
          kind: ObservationKind.notification,
          observedAt: DateTime.utc(2026, 9, 6),
          title: title,
          body: body,
          accountId: 'meezan',
          sourcePackage: 'com.google.android.apps.messaging',
        ),
      );

  group('interbank transfers out — the most common alert in Pakistan', () {
    test('beneficiary at another bank, with a fee quoted after it', () {
      final result = read(
        'Meezan Bank PKR 4,000.00 sent to M SAMPLE PAYEE UBL-xxx9002 from '
        'your A/C xxx9001 of MAIN BRANCH LHR on 27-Aug-2026 at 16:51 '
        'Fee: Rs.4.00 TID:100001 UAN 021111000000 ZONG',
      );

      expect(result.status, ParseStatus.parsed);
      expect(result.parserId, 'pk.ibft');
      expect(result.candidate?.amount.minorUnits, 400000);
      expect(result.candidate?.direction, EntryDirection.debit);
      expect(result.candidate?.description, 'M SAMPLE PAYEE');
      expect(
        result.candidate?.counterparty,
        contains('9002'),
        reason: 'the beneficiary account must survive for own-transfer pairing',
      );
      expect(result.candidate?.reference, '100001');
    });

    test('beneficiary at a wallet, hyphenated institution tag', () {
      final result = read(
        'Meezan Bank PKR 4,000.00 sent to DEMO DEMO '
        'EASYPAISA-TELENOR-xxxBANK from your A/C xxx9001 of MAIN BRANCH '
        'LHR on 30-Aug-2026 at 18:30 Fee: Rs.4.00 TID:100002 '
        'UAN 021111000000 ZONG',
      );

      expect(result.status, ParseStatus.parsed);
      expect(result.candidate?.amount.minorUnits, 400000);
      expect(result.candidate?.description, 'DEMO DEMO');
    });

    test('a large transfer is not confused by its own fee', () {
      final result = read(
        'Meezan Bank PKR 40,000.00 sent to TEST USER ASKARI-xxxBANK from '
        'your A/C xxx9001 of MAIN BRANCH LHR on 04-Sep-2026 at 13:26 '
        'Fee: Rs.15.00 TID:100003 UAN 021111000000 ZONG',
      );

      expect(result.candidate?.amount.minorUnits, 4000000);
      expect(
        result.candidate?.description,
        'TEST USER',
        reason: 'ASKARI is the beneficiary bank, not part of the name',
      );
    });

    test('RAAST names the beneficiary only by IBAN', () {
      final result = read(
        'RAAST Payment Rs. 80.0 successfully sent to RAAST IBAN: '
        'PK00NAYA0000000000009005 from your JazzCash account.',
        title: 'RAAST Payment',
      );

      expect(result.status, ParseStatus.parsed);
      expect(result.candidate?.amount.minorUnits, 8000);
      expect(result.candidate?.direction, EntryDirection.debit);
      expect(
        result.candidate?.description,
        'NAYA ••9005',
        reason: 'an IBAN is not a name; the bank and last four are',
      );
      expect(
        result.candidate?.counterparty,
        contains('PK00NAYA0000000000009005'),
        reason: 'the IBAN digits are how this pairs with the NayaPay leg',
      );
    });
  });

  group('an own-account move is recognised from the digits', () {
    const ownNayaPay = OwnIdentity(
      names: {'Your Full Name'},
      accountSuffixes: {'nayapay': '9005'},
    );

    test('the RAAST beneficiary IBAN matches the configured NayaPay account', () {
      final result = read(
        'RAAST Payment Rs. 80.0 successfully sent to RAAST IBAN: '
        'PK00NAYA0000000000009005 from your JazzCash account.',
      );

      expect(
        ownNayaPay.matchesAccount(result.candidate?.counterparty, 'nayapay'),
        isTrue,
        reason: 'JazzCash to your own NayaPay is a move, not spending',
      );
    });

    test('a stranger at another bank does not match', () {
      final result = read(
        'Meezan Bank PKR 4,000.00 sent to M SAMPLE PAYEE UBL-xxx9002 from '
        'your A/C xxx9001 on 27-Aug-2026 Fee: Rs.4.00 TID:100001',
      );

      expect(
        ownNayaPay.matchesAccount(result.candidate?.counterparty, 'nayapay'),
        isFalse,
      );
    });
  });

  group('card purchases keep their merchant', () {
    test('a POS purchase is named after the shop', () {
      final result = read(
        'Meezan Bank PKR 1,060.00 spent using Meezan Card 9004 at SAMPLE '
        'SUPERMARKET. Avbl Bal PKR 8,190.00',
      );

      expect(result.status, ParseStatus.parsed);
      expect(result.candidate?.amount.minorUnits, 106000);
      expect(result.candidate?.direction, EntryDirection.debit);
      expect(result.candidate?.description, 'SAMPLE SUPERMARKET');
    });
  });

  group('noise never becomes a decision', () {
    test('a purchase OTP is not the purchase', () {
      final result = read(
        'Meezan Bank Your e-commerce transaction OTP is 3609 for amount '
        'PKR 2086.20 using Meezan Card 9004 at DEMO PHARMACY. '
        'Valid for 5 mins.',
      );
      expect(result.status, ParseStatus.unsupported);
      expect(result.parserId, 'pk.otp');
    });

    test('a Roman Urdu loan advert is marketing', () {
      final result = read(
        '8558 Rs.4000 tak ka loan hasil karein! Aasani se cash loan ke liye '
        'JazzCash App use karein ya *786*4# dial karein!',
      );
      expect(result.status, ParseStatus.unsupported);
      expect(result.parserId, 'pk.marketing');
    });
  });
}
