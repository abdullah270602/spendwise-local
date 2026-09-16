import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/parsing/template_skeleton.dart';

/// Recognising that two alerts are the same sentence.
///
/// A bank fills in one sentence over and over, so two of its alerts differ
/// only in the amount, the date, the account tail, the reference and the
/// name of whoever was paid. Take those out and what is left identifies the
/// *kind* of message — which is what would let the app ask about an unknown
/// shape once instead of once per alert.
///
/// Every number quoted below was measured on a real exported ledger of 32
/// alerts. The fixtures here keep those shapes and invent every value.
void main() {
  const sk = TemplateSkeletonizer();

  String signatureOf(String text) => sk.of(text).signature;

  group('two alerts from one bank reduce to one sentence', () {
    test('a card purchase, whatever was bought and for how much', () {
      final first = signatureOf(
        'Northbank PKR 211.00 charged at CORNER BAKERY L for card used, '
        'from A/C xxx9001 (MAIN BRANCH) on 07-Sep-2026 at 12:58 TID:755016',
      );
      final second = signatureOf(
        'Northbank PKR 1,650.00 charged at ASLAM CASH AND for card used, '
        'from A/C xxx9001 (MAIN BRANCH) on 12-Sep-2026 at 19:30 TID:158785',
      );
      expect(first, second);
      expect(first, contains('charged at <party> for card used'));
      expect(
        first,
        contains('from <account>'),
        reason:
            'the account is a slot of its own; letting the name run '
            'swallow it hid it from the rule that knows how to read it',
      );
    });

    test('a wallet payment, whoever it went to', () {
      final first = signatureOf(
        "Off it goes Rs. 110 sent to Sample Payee. Your wallet's seen "
        'better days.',
      );
      final second = signatureOf(
        "Off it goes Rs. 1,000 sent to Another Person. Your wallet's seen "
        'better days.',
      );
      expect(first, second);
    });

    test('a transfer, whatever IBAN the payee banks at', () {
      // These two differ only in the payee's IBAN. Left unmasked they were
      // two templates, which is how a bank with one sentence looks like a
      // bank with several.
      final first = signatureOf(
        'Northbank PKR 40,000.00 received from S.OWNER AC# xxxPYMT '
        'PK11SBNK01090 as RAAST payment to your AC# 9001 on 13-Sep-2026',
      );
      final second = signatureOf(
        'Northbank PKR 15,000.00 received from R.PERSON AC# xxxPYMT '
        'PK24NBNK00030 as RAAST payment to your AC# 9001 on 10-Sep-2026',
      );
      expect(first, second);
    });
  });

  group('what must stay in the sentence', () {
    test('two genuinely different wordings stay different', () {
      // "for card used" and "as internet purchase" are different events and
      // must not collapse. Over-masking would merge them and the app would
      // learn one rule for two things.
      final card = signatureOf(
        'Northbank PKR 211.00 charged at A SHOP for card used, from '
        'A/C xxx9001 on 07-Sep-2026 at 12:58 TID:755016',
      );
      final online = signatureOf(
        'Northbank PKR 211.00 charged at A SHOP as internet purchase, from '
        'A/C xxx9001 on 07-Sep-2026 at 12:58 TID:755016',
      );
      expect(card, isNot(online));
    });

    test('money in and money out stay different', () {
      final out = signatureOf(
        'Northbank PKR 500 sent to A PAYEE on 01-Jan-2026',
      );
      final into = signatureOf(
        'Northbank PKR 500 received from A PAYEE on 01-Jan-2026',
      );
      expect(out, isNot(into));
    });

    test('a clock is not a payee', () {
      // "on <date> at 12:58" read the time as the counterparty until dates
      // and times were claimed before the name run.
      final signature = signatureOf(
        'Northbank PKR 500 charged at A SHOP on 07-Sep-2026 at 12:58',
      );
      expect(signature, contains('at <time>'));
      expect(signature, isNot(contains('at <party> <party>')));
    });

    test('"for" does not introduce a payee', () {
      // Bank messages use "for" for everything else -- "for card used",
      // "for info 111...". Masking after it erased the constant words that
      // tell two templates apart.
      final signature = signatureOf(
        'Northbank PKR 500 charged at A SHOP for card used, from A/C xxx9001',
      );
      expect(signature, contains('for card used'));
    });
  });

  test('the fingerprint is stable and follows the signature', () {
    final one = sk.of('Northbank PKR 211.00 sent to A PAYEE on 01-Jan-2026');
    final same = sk.of('Northbank PKR 999.00 sent to B PAYEE on 09-Sep-2026');
    final other = sk.of('Northbank PKR 211.00 received from A PAYEE');
    expect(one.fingerprint, same.fingerprint);
    expect(one.fingerprint, isNot(other.fingerprint));
    expect(one.fingerprint, hasLength(16));
  });

  test('the slots are reported in the order they appeared', () {
    final skeleton = sk.of(
      'Northbank PKR 211.00 charged at A SHOP from A/C xxx9001 '
      'on 07-Sep-2026 at 12:58 TID:755016',
    );
    expect(skeleton.slots.first, SkeletonSlot.amount);
    expect(skeleton.slots, contains(SkeletonSlot.party));
    expect(skeleton.slots, contains(SkeletonSlot.account));
    expect(skeleton.slots, contains(SkeletonSlot.date));
    expect(skeleton.slots, contains(SkeletonSlot.time));
    expect(skeleton.slots, contains(SkeletonSlot.reference));
  });

  test('a merchant that leads the sentence is not yet recognised', () {
    // An honest limitation, recorded rather than hidden. A card wallet names
    // the shop first, with no preposition to anchor on -- "CORNER BAKERY
    // Rs141 with Everyday" -- so two such alerts stay two templates. Masking
    // a leading capitalised run would collapse them, and would also mask the
    // bank's own name at the start of every other message in this file.
    final first = sk.of('CORNER BAKERY Rs141 with Everyday');
    final second = sk.of('A PLUS PHARMACY Rs1,700 with Everyday');
    expect(
      first.signature,
      isNot(second.signature),
      reason:
          'when this starts passing, the limitation has been fixed and '
          'this test should be replaced rather than deleted',
    );
  });
}
