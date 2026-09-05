import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/routing/account_router.dart';

void main() {
  const router = AccountRouter();

  const meezan = AccountProfile(
    id: 'meezan',
    name: 'Meezan Debit',
    institution: 'Meezan Bank',
    suffix: '4821',
  );
  const ubl = AccountProfile(
    id: 'ubl',
    name: 'UBL Current',
    institution: 'UBL',
    suffix: '9012',
  );
  const nayapay = AccountProfile(id: 'nayapay', name: 'NayaPay');
  const accounts = [meezan, ubl, nayapay];

  test('routes a Meezan SMS to the Meezan account, not the SMS app owner', () {
    final routing = router.route(
      text: 'Meezan Bank: PKR 1,060 debited from your a/c ****4821',
      sender: 'Meezan',
      accounts: accounts,
    );
    expect(routing?.accountId, 'meezan');
  });

  test('routes by account number even when no institution is named', () {
    final routing = router.route(
      text: 'PKR 500 debited from account ending 9012',
      accounts: accounts,
    );
    expect(routing?.accountId, 'ubl');
  });

  test('does not mistake an amount for an account number', () {
    // "PKR 4,821" strips to 4821, which is Meezan's registered tail. Only
    // digits in an account context may be read as an account number.
    final routing = router.route(
      text: 'PKR 4,821 spent at SOME SHOP',
      accounts: accounts,
    );
    expect(routing, isNull);
  });

  test('matches a one-word institution inside a longer account name', () {
    final routing = router.route(
      text: 'Your Meezan account was debited PKR 300',
      accounts: accounts,
    );
    expect(routing?.accountId, 'meezan');
  });

  test('abstains when the alert names nothing identifying', () {
    final routing = router.route(
      text: 'PKR 300 debited at a shop',
      accounts: accounts,
    );
    expect(routing, isNull);
  });

  test('abstains rather than guess between two equally-named accounts', () {
    const first = AccountProfile(id: 'a', name: 'Savings', institution: 'HBL');
    const second = AccountProfile(id: 'b', name: 'Savings', institution: 'HBL');
    final routing = router.route(
      text: 'HBL Savings: PKR 100 debited',
      accounts: const [first, second],
    );
    expect(routing, isNull);
  });

  test('the account number outweighs a merely mentioned institution', () {
    // A transfer message names the other bank, but the account tail says
    // which of the user's accounts this alert is actually about.
    final routing = router.route(
      text: 'PKR 5,000 sent from a/c ****9012 to Meezan Bank',
      accounts: accounts,
    );
    expect(routing?.accountId, 'ubl');
  });
}
