import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/models/event_candidate.dart';
import 'package:spendwise/domain/models/raw_observation.dart';
import 'package:spendwise/domain/parsing/notification_parser.dart';
import 'package:spendwise/domain/parsing/template_skeleton.dart';

/// Six things a corpus taught the parser that no amount of reasoning had.
///
/// The app's rules were written against Pakistani bank alerts. Running them
/// unchanged over 9,874 real transactional messages from **25 Indian banks
/// they had never seen** read 81.9% of them. Four changes, each one found by
/// reading what actually failed rather than by guessing, took that to 96.3%.
///
/// The fixtures below are invented. What is real is the *shape* of each
/// failure and the count beside it.
void main() {
  EventCandidate? parse(String text) => const NotificationParser(
    currencies: {'INR'},
  ).parse(
    RawObservation(
      id: 'x',
      kind: ObservationKind.notification,
      observedAt: DateTime.utc(2026, 1, 1),
      body: text,
      accountId: 'acct',
    ),
  );

  group('a balance is not always labelled "balance"', () {
    test('"Avlbl Amt" is a balance', () {
      // The single commonest balance label in the corpus -- 1,212 messages --
      // and it contains neither "bal" nor "balance". One bank's standard
      // message quotes the payment, then "Total Bal", then "Avlbl Amt", so
      // one of the two balances always survived and the alert was thrown out
      // as having two amounts. That one gap was 73% of everything unread.
      final candidate = parse(
        'Rs.50 transferred from A/c ...9001 to:UPI/208916032757. '
        'Total Bal:Rs.4712.59CR. Avlbl Amt:Rs.4712.59',
      );
      expect(candidate, isNotNull);
      expect(candidate!.amount.minorUnits, 5000);
    });

    test('an available limit is a balance too', () {
      final candidate = parse(
        'INR 1948 was spent on your Credit Card XX9001 at A SHOP. '
        'Avbl Lmt: INR 46698.09',
      );
      expect(candidate!.amount.minorUnits, 194800);
    });

    test('but a bare "amount of" is the payment itself', () {
      // "Amount" needs the availability word in front of it. Without that
      // guard, the one figure in this message would have been read as a
      // balance and the payment lost.
      final candidate = parse('An amount of INR 5,000 has been debited');
      expect(candidate!.amount.minorUnits, 500000);
    });
  });

  test('a receipt with a support link is not advertising', () {
    // A message carrying a link is treated as marketing unless it also
    // reports a settlement -- and "sent" was missing from the settlement
    // vocabulary, though it is the commonest verb a wallet uses. That single
    // omission discarded 201 real payments as advertising.
    final candidate = parse(
      'Rs.25.00 sent to a-payee@examplepay from your a/c 91XX9001. '
      'Ref: 212888962605. View your past payments at https://example.test/msg',
    );
    expect(candidate, isNotNull);
    expect(candidate!.direction, EntryDirection.debit);
  });

  group('"transferred from" points both ways', () {
    test('from an account of yours, it is money leaving', () {
      // Read as money arriving *and* leaving at once, one bank's commonest
      // message contradicted itself and went unparsed -- 797 alerts, every
      // one a payment the owner had made.
      final candidate = parse(
        'Rs.500 transferred from A/c ...9001 to:UPI/208916032757',
      );
      expect(candidate, isNotNull);
      expect(candidate!.direction, EntryDirection.debit);
    });

    test('from a person, it is money arriving', () {
      final candidate = parse('INR 500 transferred from A SAMPLE PAYER');
      expect(candidate!.direction, EntryDirection.credit);
    });

    test('and an abbreviated account still reads as leaving', () {
      final candidate = parse(
        'Thx for txn of Rs.219.50 frm A/c X9001 to A MERCHANT. Ref IGXXXX1',
      );
      expect(candidate, isNotNull);
      expect(candidate!.direction, EntryDirection.debit);
    });
  });

  group('templates collapse only if every varying part is masked', () {
    const skeletonizer = TemplateSkeletonizer();

    test('a payment handle is one identifier, not two', () {
      // Split across the "@" it made a new template per payer: one bank sent
      // 573 messages that reduced to 457 templates, and its commonest
      // sentence appeared under two signatures purely because the handles
      // differed.
      final first = skeletonizer
          .of('Your VPA payer-one@examplepay is debited for Rs.110.00 '
              'and credited to shop-a@otherpay')
          .signature;
      final second = skeletonizer
          .of('Your VPA payer-two@otherpay is debited for Rs.700.00 '
              'and credited to shop-b@examplepay')
          .signature;
      expect(first, second);
    });

    test('a date written without separators is still a date', () {
      // "02may22". One bank wrote every date this way, which made a fresh
      // template for every calendar day and turned four sentences into 386.
      final first = skeletonizer
          .of('Your A/c X9001 debited by Rs.100 on 02may22 transfer to A SHOP')
          .signature;
      final second = skeletonizer
          .of('Your A/c X9001 debited by Rs.250 on 17jun22 transfer to B SHOP')
          .signature;
      expect(first, second);
      expect(first, contains('<date>'));
    });
  });
}
