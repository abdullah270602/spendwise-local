import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/domain.dart';

void main() {
  test('empty identity matches nothing', () {
    const identity = OwnIdentity();
    expect(identity.isConfigured, isFalse);
    expect(identity.matchesOwnName('Abdullah Naseem'), isFalse);
    expect(identity.matchesAccount('a/c 1234', 'meezan'), isFalse);
  });

  test('matches own name as a whole word inside counterparty text', () {
    const identity = OwnIdentity(names: {'Abdullah Naseem'});
    expect(identity.isConfigured, isTrue);
    expect(
      identity.matchesOwnName('IBFT TO ABDULLAH NASEEM A/C XXXX1234'),
      isTrue,
    );
    expect(identity.matchesOwnName('IBFT TO ABDULLAH NASEEMA'), isFalse);
    expect(identity.matchesOwnName('IBFT TO SOMEONE ELSE'), isFalse);
    expect(identity.matchesOwnName(null), isFalse);
  });

  test('matches a configured account suffix inside counterparty digits', () {
    const identity = OwnIdentity(accountSuffixes: {'meezan': '4821'});
    expect(
      identity.matchesAccount('Transfer to Meezan a/c ending 4821', 'meezan'),
      isTrue,
    );
    expect(
      identity.matchesAccount('Transfer to Meezan a/c ending 4821', 'ubl'),
      isFalse,
      reason: 'suffix is only registered against the meezan account',
    );
    expect(identity.matchesAccount('no digits here', 'meezan'), isFalse);
    expect(identity.matchesAccount(null, 'meezan'), isFalse);
  });
}
