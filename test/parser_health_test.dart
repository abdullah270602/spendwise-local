import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

/// The number that decides how the parser should grow, and which the app
/// never showed: how much of what a given bank sends does it read without
/// asking.
///
/// Everything here was already being stored — the raw alert, its parse
/// status, the reason it stopped, which parser read it. The report asks the
/// question; it records nothing new.
void main() {
  LocalLedger ledgerWithTwoBanks() {
    final ledger = LocalLedger.openInMemoryForTests();
    ledger.rememberAndroidSources([
      {
        'packageName': 'com.example.north',
        'label': 'Northbank',
        'configured': true,
      },
      {
        'packageName': 'com.example.south',
        'label': 'Southbank',
        'configured': true,
      },
    ]);
    final sources = ledger.sources();
    ledger.addAccount(
      name: 'Everyday',
      type: AccountType.bank,
      accountSuffix: '9001',
      sourceIds: [
        sources.firstWhere((s) => s.packageName == 'com.example.north').id,
      ],
    );
    ledger.addAccount(
      name: 'Second',
      type: AccountType.bank,
      accountSuffix: '9002',
      sourceIds: [
        sources.firstWhere((s) => s.packageName == 'com.example.south').id,
      ],
    );
    return ledger;
  }

  void post(
    LocalLedger ledger,
    String package,
    String key,
    String title,
    String text,
    DateTime at,
  ) => ledger.ingestNotification({
    'notificationKey': key,
    'snapshotHash': 'snap:$key',
    'packageName': package,
    'postedAt': at.millisecondsSinceEpoch,
    'title': title,
    'text': text,
  });

  test('it counts what each source sent and what became of it', () {
    final ledger = ledgerWithTwoBanks();
    addTearDown(ledger.close);
    final day = DateTime.utc(2026, 5, 4, 9);

    // Read cleanly: an amount and a direction.
    post(
      ledger,
      'com.example.north',
      'n1',
      'Northbank',
      'Northbank PKR 1,250.00 charged at CORNER BAKERY from A/C xxx9001',
      day,
    );
    // No amount anywhere. Correctly skipped, and it must not count against
    // the parser: declining to invent a transaction is the right answer.
    post(
      ledger,
      'com.example.north',
      'n2',
      'Northbank',
      'Your one-time passcode is 447120. Do not share it with anyone.',
      day.add(const Duration(hours: 1)),
    );
    // An amount, but nothing saying which way it went.
    post(
      ledger,
      'com.example.south',
      's1',
      'Southbank',
      'Southbank PKR 3,000.00 Ref 8891 A/C xxx9002',
      day.add(const Duration(hours: 2)),
    );

    final health = ledger.parserHealth();
    final north = health.sources.firstWhere((s) => s.label == 'Northbank');
    final south = health.sources.firstWhere((s) => s.label == 'Southbank');

    expect(north.parsed, 1);
    expect(
      north.ignored,
      1,
      reason: 'a passcode is not a failed parse, it is a correct refusal',
    );
    expect(
      north.attempted,
      1,
      reason: 'the denominator is alerts that looked like money',
    );
    expect(north.coverage, 1.0);

    expect(south.parsed, 0);
    expect(south.review + south.error, 1);
    expect(south.coverage, 0.0);

    expect(
      health.needingWork.first.label,
      'Southbank',
      reason: 'the list is a queue of work, worst first',
    );
  });

  test('it says which parser did the reading', () {
    final ledger = ledgerWithTwoBanks();
    addTearDown(ledger.close);
    post(
      ledger,
      'com.example.north',
      'n1',
      'Northbank',
      'Northbank PKR 1,250.00 charged at CORNER BAKERY from A/C xxx9001',
      DateTime.utc(2026, 5, 4, 9),
    );

    final north = ledger.parserHealth().sources.firstWhere(
      (s) => s.label == 'Northbank',
    );
    expect(north.parsers, isNotEmpty);
    expect(
      north.parsers.keys.single,
      'pk.card.purchase',
      reason:
          'the report names the parser, so a person can see that this '
          'bank is recognised by sentence shape and not by anything written '
          'for it',
    );
    expect(
      north.onLastResort,
      0,
      reason:
          'a shape rule did match, so this alert was not scraped by the '
          'amount-and-a-verb parser of last resort',
    );
  });

  test('it carries the parser own words about what stopped it', () {
    final ledger = ledgerWithTwoBanks();
    addTearDown(ledger.close);
    post(
      ledger,
      'com.example.south',
      's1',
      'Southbank',
      'Southbank PKR 3,000.00 Ref 8891 A/C xxx9002',
      DateTime.utc(2026, 5, 4, 9),
    );

    final south = ledger.parserHealth().sources.firstWhere(
      (s) => s.label == 'Southbank',
    );
    expect(south.reasons, isNotEmpty);
    expect(
      south.reasons.first.reason,
      isNot(contains('Instance of')),
      reason: 'these are read by a person deciding what to teach the parser',
    );
    expect(south.reasons.first.count, 1);
  });

  test('a source that has produced nothing at all still appears', () {
    // The one case a report built only from captured rows could never show,
    // and the likeliest reason somebody thinks the app is broken: a bank
    // whose app posts nothing the listener ever sees.
    final ledger = ledgerWithTwoBanks();
    addTearDown(ledger.close);
    post(
      ledger,
      'com.example.north',
      'n1',
      'Northbank',
      'Northbank PKR 1,250.00 charged at CORNER BAKERY from A/C xxx9001',
      DateTime.utc(2026, 5, 4, 9),
    );

    final south = ledger.parserHealth().sources.firstWhere(
      (s) => s.label == 'Southbank',
    );
    expect(south.total, 0);
    expect(
      south.coverage,
      isNull,
      reason:
          'zero out of zero is not zero, and printing 0% would send '
          'somebody hunting a parser bug that does not exist',
    );
  });

  test('an empty ledger reports nothing rather than a perfect score', () {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    expect(ledger.parserHealth().coverage, isNull);
  });
}
