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
      'You have sent Rs. 80 to ALI RAZA. Your new balance is Rs. 500',
    );
    expect(candidate, isNotNull);
    expect(candidate!.direction, EntryDirection.debit);
    expect(candidate.amount.minorUnits, 8000);
  });

  test('reads the short "Avbl Bal" form', () {
    final candidate = parse(
      'Rs.1,500 debited from a/c ***123 at IMTIAZ. Avbl Bal Rs.9,000',
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
        body: 'Rs.1,500 debited at IMTIAZ SUPERMARKET. Avbl Bal Rs.9,000',
        accountId: 'acct-1',
        sourcePackage: 'com.google.android.apps.messaging',
      ),
    );
    expect(candidate!.description, 'IMTIAZ SUPERMARKET');
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
      'PKR 2,086.20 debited at JENPHARM RETAIL as international transaction. '
      'Avl Bal PKR 5,000',
    );
    expect(candidate!.description, 'JENPHARM RETAIL');
  });

  test('a lone amount is unaffected', () {
    final candidate = parse('Your account was debited PKR 1,500 at SHOP');
    expect(candidate, isNotNull);
    expect(candidate!.amount.minorUnits, 150000);
  });
}
