import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/domain.dart';

/// A telco or a merchant app describes a purchase in service words, not
/// banking words: nobody's phone bill says "debited". The direction vocabulary
/// was a closed list of bank verbs, so a real Rs 4,500 purchase read as
/// directionless and went to Review instead of the ledger.
void main() {
  RawObservation alert(String body, {String? title}) => RawObservation(
    id: 'obs-1',
    kind: ObservationKind.notification,
    observedAt: DateTime.utc(2026, 9, 6, 17, 45),
    title: title,
    body: body,
    sourcePackage: 'com.nayapay.android',
    accountId: 'wallet',
    externalId: 'ext-1',
  );

  const parser = NotificationParser();

  test('a subscription bought with money is money leaving', () {
    // Verbatim, from the phone. This is the reported bug.
    final result = parser.parseDetailed(
      alert(
        'Bundle Top-Up 📱 You subscribed to Zong My3 Family Sharing( 3 User) '
        'for Rs. 4,500. Enjoy the connection.',
        title: 'Bundle Top-Up 📱',
      ),
    );

    expect(
      result.status,
      ParseStatus.parsed,
      reason: result.reasons.join('; '),
    );
    expect(result.candidate?.direction, EntryDirection.debit);
    expect(result.candidate?.amount.minorUnits, 450000);
  });

  test('a renewal and a recharge read the same way', () {
    for (final body in const [
      'Your plan renewed for Rs. 1,200. Thanks for staying with us.',
      'You recharged with Rs 500. Enjoy!',
    ]) {
      final result = parser.parseDetailed(alert(body));
      expect(result.candidate?.direction, EntryDirection.debit, reason: body);
    }
  });

  group('but an invitation to spend is still not a purchase', () {
    test('present tense is an offer, not a settlement', () {
      // The tense is the whole discriminator: "subscribed" reports something
      // that happened, "subscribe" asks you to make it happen.
      final result = parser.parseDetailed(
        alert(
          'Subscribe to SpendWise Premium for Rs 500 and get 3 months free!',
        ),
      );
      expect(result.status, isNot(ParseStatus.parsed));
    });

    test('and marketing is still dropped before direction is considered', () {
      final result = parser.parseDetailed(
        alert(
          'Subscribe now to Zong Super Card for Rs 1,600 and PKR 500 '
          'cashback will be credited.',
        ),
      );
      expect(result.status, ParseStatus.unsupported);
      expect(result.parserId, 'pk.marketing');
    });
  });
}
