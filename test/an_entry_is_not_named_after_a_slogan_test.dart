import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/models/raw_observation.dart';
import 'package:spendwise/domain/parsing/notification_parser.dart';

/// What a ledger entry is called when the alert names nobody.
///
/// A bank titles its alerts with its own name, and falling back to that is
/// reasonable. A wallet titles them with copy — "Off it goes", "Cha-Ching!",
/// "Card in action", "Money sent" — and the fallback took it literally. A
/// real ledger ended up with three consecutive entries called "Money sent",
/// which is both wrong and useless: it names no party and says nothing the
/// amount and the minus sign had not already said.
void main() {
  String? nameOf(String title, String body) => const NotificationParser()
      .parse(
        RawObservation(
          id: 'x',
          kind: ObservationKind.notification,
          observedAt: DateTime.utc(2026, 1, 1),
          body: body,
          title: title,
          accountId: 'acct',
        ),
      )
      ?.description;

  group('a wallet slogan is not a name', () {
    for (final slogan in const [
      'Off it goes 💸',
      'Cha-Ching! 🤑',
      'Card in action 💳',
      'Money, meet wallet 🤑',
      'Money sent 💸',
    ]) {
      test('"$slogan" is refused', () {
        expect(
          nameOf(slogan, '$slogan Rs. 1,500 debited from your wallet'),
          isNull,
          reason:
              'the ledger falls back to "Payment", which at least does '
              'not pretend to name anybody',
        );
      });
    }
  });

  group('but a real name still wins', () {
    test('the counterparty, whenever there is one', () {
      expect(
        nameOf(
          'Off it goes 💸',
          'Off it goes 💸 Rs. 110 sent to A Sample Payee.',
        ),
        'A Sample Payee',
        reason:
            'the slogan rule must never reach a transaction that named '
            'somebody',
      );
    });

    test('a bank name in the title, when nobody else is named', () {
      expect(
        nameOf('Northbank', 'Northbank PKR 141.00 debited from your account'),
        'Northbank',
      );
    });

    test('a merchant found in the body', () {
      expect(
        nameOf(
          'Northbank',
          'Northbank PKR 211.00 charged at CORNER BAKERY for card used',
        ),
        'CORNER BAKERY',
      );
    });
  });

  test('a name in another script is a name, not a slogan', () {
    // The rule is about pictographs and exclamation marks, not about being
    // non-Latin. Checked by code point precisely so that Arabic, Urdu and
    // CJK titles survive.
    expect(
      nameOf('بنك الشمال', 'بنك الشمال PKR 500 debited from your account'),
      'بنك الشمال',
    );
  });
}
