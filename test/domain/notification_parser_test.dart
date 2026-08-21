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
    expect(parser.parse(observation('Paid PKR 100. Balance PKR 900')), isNull);
    expect(parser.parse(observation('Paid PKR 100', accountId: null)), isNull);
  });
}
