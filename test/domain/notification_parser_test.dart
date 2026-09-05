import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/domain.dart';

void main() {
  const parser = NotificationParser();
  final time = DateTime.utc(2026, 8, 21, 12);

  RawObservation observation(String body, {String? accountId = 'hbl'}) =>
      RawObservation(
        id: body,
        kind: ObservationKind.notification,
        observedAt: time,
        body: body,
        accountId: accountId,
        sourcePackage: 'com.bank',
      );

  test('parses a debit with a stable reference', () {
    final result = parser.parse(
      observation('Your account was debited PKR 10,000. Ref: AB12CD'),
    );
    expect(result, isNotNull);
    expect(result!.amount, const Money.pkr(1000000));
    expect(result.direction, EntryDirection.debit);
    expect(result.reference, 'AB12CD');
  });

  test('parses signed credit notification', () {
    final result = parser.parse(observation('+PKR 250.50 received'));
    expect(result!.direction, EntryDirection.credit);
    expect(result.amount.minorUnits, 25050);
  });

  test('refuses ambiguous observations', () {
    expect(parser.parse(observation('Balance is PKR 10,000')), isNull);
    expect(parser.parse(observation('Paid PKR 100', accountId: null)), isNull);
    // Two amounts that could each be the transaction stay refused.
    expect(
      parser.parse(observation('Paid PKR 100 plus PKR 20 service fee')),
      isNull,
    );
  });

  test('reads the amount when the other figure is labelled as a balance', () {
    // Bank SMS quote the running balance next to the amount. Refusing these
    // as "ambiguous" silenced the entire SMS channel.
    final result = parser.parse(observation('Paid PKR 100. Balance PKR 900'));
    expect(result, isNotNull);
    expect(result!.direction, EntryDirection.debit);
    expect(result.amount.minorUnits, 10000);
  });

  test('extracts counterparty and TID from a real-shaped bank SMS', () {
    final result = parser.parse(
      observation(
        'Dear NAME, an amount of Rs. 80 has been successfully sent to '
        'Jane Doe of IBAN No: ****6642 on 2026-08-22 at 22:29:38. '
        'TID:721537571898 via RAAST',
      ),
    );
    expect(result, isNotNull);
    expect(result!.direction, EntryDirection.debit);
    expect(result.counterparty, 'Jane Doe');
    expect(result.reference, '721537571898');
  });

  test('extracts counterparty for a credit notification', () {
    final result = parser.parse(
      observation('Rs. 500 received from John Smith via RAAST'),
    );
    expect(result!.direction, EntryDirection.credit);
    expect(result.counterparty, 'John Smith');
  });

  test('extracts a merchant name for card purchases', () {
    final result = parser.parse(
      observation('Rs. 1,200 paid at Corner Store on 2026-08-22'),
    );
    expect(result!.direction, EntryDirection.debit);
    expect(result.counterparty, 'Corner Store');
  });

  test('leaves counterparty null rather than guess when unclear', () {
    final result = parser.parse(observation('Rs. 100 debited from account'));
    expect(result!.counterparty, isNull);
  });
}
