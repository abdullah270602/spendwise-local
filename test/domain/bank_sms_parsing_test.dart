import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/domain.dart';

/// Pakistani bank SMS almost always quote the running balance beside the
/// transaction amount. Treating "two amounts" as unreadable meant the whole
/// SMS channel produced nothing at all.
void main() {
  const parser = NotificationParser();

  EventCandidate? parse(String text) => parser.parse(
    RawObservation(
      id: 'sms-1',
      kind: ObservationKind.notification,
      observedAt: DateTime.utc(2026, 9, 5, 12),
      body: text,
      accountId: 'acct-1',
      sourcePackage: 'com.google.android.apps.messaging',
    ),
  );

  test('reads a debit quoted alongside an available balance', () {
    final candidate = parse(
      'Your UBL a/c ****1234 has been debited with PKR 80.00 on '
      '05-SEP-25. Avl Bal: PKR 12,345.67',
    );
    expect(candidate, isNotNull);
    expect(candidate!.direction, EntryDirection.debit);
    expect(candidate.amount.minorUnits, 8000);
  });

  test('reads a credit quoted alongside an available balance', () {
    final candidate = parse(
      'Dear Customer, PKR 5,000.00 has been credited to your account '
      '****5678. Available Balance: PKR 20,000.00',
    );
    expect(candidate, isNotNull);
    expect(candidate!.direction, EntryDirection.credit);
    expect(candidate.amount.minorUnits, 500000);
  });

  test('reads a wallet transfer that states the new balance afterwards', () {
    final candidate = parse(
      'You have sent Rs. 80 to SAMPLE PERSON. Your new balance is Rs. 500',
    );
    expect(candidate, isNotNull);
    expect(candidate!.direction, EntryDirection.debit);
    expect(candidate.amount.minorUnits, 8000);
  });

  test('reads the short "Avbl Bal" form', () {
    final candidate = parse(
      'Rs.1,500 debited from a/c ***123 at SAMPLE SUPERMARKET. Avbl Bal Rs.9,000',
    );
    expect(candidate, isNotNull);
    expect(candidate!.amount.minorUnits, 150000);
  });

  test('still refuses when two non-balance amounts are present', () {
    // An amount plus a separate fee is genuinely ambiguous -- guessing which
    // one is the transaction would be worse than asking.
    expect(
      parse('PKR 80.00 debited and PKR 15.00 service fee charged'),
      isNull,
    );
  });

  test('names the transaction after the merchant, not the SMS short code', () {
    final candidate = parser.parse(
      RawObservation(
        id: 'sms-2',
        kind: ObservationKind.notification,
        observedAt: DateTime.utc(2026, 9, 5, 12),
        title: '8558',
        body: 'Rs.1,500 debited at SAMPLE SUPERMARKET. Avbl Bal Rs.9,000',
        accountId: 'acct-1',
        sourcePackage: 'com.google.android.apps.messaging',
      ),
    );
    expect(candidate!.description, 'SAMPLE SUPERMARKET');
  });

  test('a sender code alone is not used as the transaction name', () {
    final candidate = parser.parse(
      RawObservation(
        id: 'sms-3',
        kind: ObservationKind.notification,
        observedAt: DateTime.utc(2026, 9, 5, 12),
        title: '8558',
        body: 'PKR 300 debited. Avl Bal PKR 700',
        accountId: 'acct-1',
        sourcePackage: 'com.google.android.apps.messaging',
      ),
    );
    expect(candidate!.description, isNull);
  });

  test('stops the merchant name before trailing narration', () {
    final candidate = parse(
      'PKR 2,086.20 debited at DEMO PHARMACY as international transaction. '
      'Avl Bal PKR 5,000',
    );
    expect(candidate!.description, 'DEMO PHARMACY');
  });

  test('a card purchase is a debit even though "credit card" is named', () {
    // "Credit Card" is the instrument, not the direction. Reading it as
    // money-in cancelled the debit signal and left the alert unreadable.
    final candidate = parse(
      'Your Credit Card was used for PKR 3,200.00 at METRO. Avl Bal PKR 40,000',
    );
    expect(candidate, isNotNull);
    expect(candidate!.direction, EntryDirection.debit);
    expect(candidate.amount.minorUnits, 320000);
  });

  test('reads "Transfer to" as a debit', () {
    final candidate = parse('PKR 4,000 Funds Transfer to ALI. Bal PKR 1,000');
    expect(candidate, isNotNull);
    expect(candidate!.direction, EntryDirection.debit);
  });

  test('takes the credited amount, not the balance quoted after it', () {
    // The amount comes first and the balance last. An institution rule that
    // scans forward from "credited" lands on the balance, which would file
    // this as PKR 20,000 received instead of PKR 5,000.
    final candidate = parse(
      'An amount of PKR 5,000 has been credited to your account. '
      'Avl Bal PKR 20,000',
    );
    expect(candidate, isNotNull);
    expect(candidate!.direction, EntryDirection.credit);
    expect(candidate.amount.minorUnits, 500000);
  });

  test('money credited to someone else is never booked as income', () {
    // Reading "credited" as money-in here would record an outgoing payment
    // as earnings. Contradictory wording is worth a person's judgement.
    expect(
      parse('PKR 80 has been credited to SAMPLE PERSON from your account'),
      isNull,
    );
  });

  test('a lone amount is unaffected', () {
    final candidate = parse('Your account was debited PKR 1,500 at SHOP');
    expect(candidate, isNotNull);
    expect(candidate!.amount.minorUnits, 150000);
  });
}
