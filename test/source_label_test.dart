import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/source_label.dart';

/// Review asks "nothing from X parsed as a transaction". If X is a package id
/// the question is about someone else's phone as far as the reader is
/// concerned, and an unanswerable question is worse than no question.
void main() {
  group('naming an app', () {
    test('Android knows best, so ask it first', () {
      expect(
        sourceLabel(
          packageName: 'com.android.messaging',
          stored: 'com.android.messaging',
          installedLabels: const {'com.android.messaging': 'Messages'},
        ),
        'Messages',
      );
    });

    test('a live label beats a stale stored one', () {
      expect(
        sourceLabel(
          packageName: 'pk.com.telenor.phoenix',
          stored: 'Telenor Phoenix',
          installedLabels: const {'pk.com.telenor.phoenix': 'easypaisa'},
        ),
        'easypaisa',
      );
    });

    test('a stored name is used when the app is no longer installed', () {
      expect(
        sourceLabel(
          packageName: 'com.techlogix.mobilinkcustomer',
          stored: 'JazzCash',
          installedLabels: const {},
        ),
        'JazzCash',
      );
    });

    test('a package id stored as the name is not a name', () {
      // This is the reported bug: the ledger falls back to the package id,
      // and that id was then shown to the user verbatim.
      expect(
        sourceLabel(
          packageName: 'com.android.messaging',
          stored: 'com.android.messaging',
          installedLabels: const {},
        ),
        'Messaging',
      );
    });

    test("and neither is Android's own placeholder", () {
      expect(
        sourceLabel(
          packageName: 'com.example.wallet',
          stored: 'Unknown app',
          installedLabels: const {},
        ),
        'Wallet',
      );
    });

    test('an alert with no package at all keeps whatever it had', () {
      expect(
        sourceLabel(
          packageName: null,
          stored: 'Unknown app',
          installedLabels: const {},
        ),
        'Unknown app',
      );
    });
  });

  group('making a package id look like a word', () {
    test('the last meaningful segment wins', () {
      expect(prettyPackageLabel('com.android.messaging'), 'Messaging');
      expect(prettyPackageLabel('pk.com.telenor.phoenix'), 'Phoenix');
    });

    test('packaging suffixes are skipped, not read out', () {
      // `com.nayapay.android` is NayaPay, not "Android".
      expect(prettyPackageLabel('com.nayapay.android'), 'Nayapay');
      expect(prettyPackageLabel('com.ubl.digital.app'), 'Digital');
    });

    test('separators and version digits are dropped', () {
      expect(prettyPackageLabel('com.bank.my_bank2'), 'My bank');
    });

    test('something that is not a package id is left alone', () {
      expect(prettyPackageLabel(''), '');
      expect(prettyPackageLabel('...'), '...');
    });
  });
}
