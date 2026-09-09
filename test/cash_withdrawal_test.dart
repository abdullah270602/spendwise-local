import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/models/event_candidate.dart';
import 'package:spendwise/domain/models/raw_observation.dart';
import 'package:spendwise/domain/parsing/notification_parser.dart';

/// Money leaving an account to become notes in a pocket is not money spent.
///
/// The app filed it as spending, which made the totals roughly right and the
/// breakdown fiction: a withdrawal appeared as one large purchase, and
/// everything actually bought with those notes appeared nowhere, because
/// nothing sends a notification when you hand over a banknote.
///
/// Recognising it is the first half. It is deliberately hard to satisfy: a
/// false positive turns money that was genuinely spent into money the owner
/// believes is still in their pocket, inflating what the app says is
/// available. A false negative only leaves the old behaviour.
void main() {
  RawObservation observe(String body, {String title = 'Example Bank'}) =>
      RawObservation(
        id: 'obs-${body.hashCode}',
        kind: ObservationKind.notification,
        sourcePackage: 'com.example.bank',
        title: title,
        body: body,
        observedAt: DateTime(2026, 9, 6, 19, 11),
        accountId: 'bank',
      );

  CandidateType? typeOf(String body, {String title = 'Example Bank'}) {
    final result = const NotificationParser().parseDetailed(
      observe(body, title: title),
    );
    return result.candidate?.type;
  }

  group('recognised as cash', () {
    test('an over-the-counter withdrawal, as a real bank writes it', () {
      // The shape of a real message, with every identifying detail replaced:
      // the branch, the account digits, the reference and the amount are all
      // invented. This is a public repo.
      expect(
        typeOf(
          'PKR 12,300.00 cash withdrawn from MAIN ROAD BR ABC from A/C '
          'xxx1234 MAIN ROAD BR ABC on 06-Sep-2026 at 19:11 TID:111222 '
          'UAN 021111000000',
        ),
        CandidateType.cashWithdrawal,
      );
    });

    test('the machine, however the bank words it', () {
      for (final body in [
        'Rs 5,000 ATM withdrawal from A/C xxx1234 on 06-Sep-2026',
        'Cash withdrawal of PKR 5,000.00 from your account xxx1234',
        'Your a/c xxx1234 has been debited PKR 5,000 for cash withdrawn at ATM',
      ]) {
        expect(
          typeOf(body),
          CandidateType.cashWithdrawal,
          reason: 'not recognised: $body',
        );
      }
    });
  });

  group('not cash, and this is the half that matters', () {
    test('a card payment is not a withdrawal even at a cash-named shop', () {
      // The word "cash" appears; nothing was withdrawn.
      expect(
        typeOf('PKR 2,400 paid to CASH AND CARRY MART from A/C xxx1234'),
        isNot(CandidateType.cashWithdrawal),
      );
    });

    test('a purchase at a terminal stays a purchase', () {
      expect(
        typeOf(
          'PKR 2,400 spent at POS terminal, ATM/Debit card xxx1234, '
          'MAIN ROAD BR ABC',
        ),
        isNot(CandidateType.cashWithdrawal),
        reason: 'a card used at a till is not a withdrawal',
      );
    });

    test('marketing about ATMs at the end of a real debit does not count', () {
      // The verb and the marker both appear, far apart, and the transaction
      // itself is a purchase. Requiring them close together is what stops
      // this, and a long promotional tail is exactly how banks write.
      expect(
        typeOf(
          'PKR 2,400 debited from A/C xxx1234 for purchase at MAIN ROAD '
          'STORE. Did you know you can now withdraw without a card at any '
          'of our 900 ATMs nationwide? Terms apply.',
        ),
        isNot(CandidateType.cashWithdrawal),
      );
    });

    test('money arriving is never a withdrawal', () {
      expect(
        typeOf('PKR 50,000 credited to A/C xxx1234, salary'),
        CandidateType.income,
      );
    });

    test('the word alone is not enough', () {
      // No cash, no ATM anywhere near it -- a transfer out described with the
      // same verb must not become cash the owner thinks they are holding.
      expect(
        typeOf('PKR 9,000 withdrawn from A/C xxx1234 and sent to A KHAN'),
        isNot(CandidateType.cashWithdrawal),
      );
    });
  });
}
