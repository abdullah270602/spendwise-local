import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

/// Teaching the app a bank without changing the app.
///
/// `parser_definitions` has been in the schema since the first release —
/// `country`, `institution`, `source_match_json`, `rules_json`, `is_builtin`,
/// `enabled` — and nothing read it. The parser built its registry from a
/// hardcoded Dart list, so one more bank meant a code change, a release, and
/// waiting for people to install it.
///
/// These tests are about one claim: the table is now the source of truth. A
/// row added is a bank read; a row switched off is a rule that stops firing.
void main() {
  LocalLedger ledgerWithOneAccount() {
    final ledger = LocalLedger.openInMemoryForTests();
    ledger.rememberAndroidSources([
      {
        'packageName': 'com.example.newbank',
        'label': 'Newbank',
        'configured': true,
      },
    ]);
    ledger.addAccount(
      name: 'Everyday',
      type: AccountType.bank,
      accountSuffix: '9001',
      sourceIds: [ledger.sources().single.id],
    );
    return ledger;
  }

  void post(LocalLedger ledger, String key, String title, String text) =>
      ledger.ingestNotification({
        'notificationKey': key,
        'snapshotHash': 'snap:$key',
        'packageName': 'com.example.newbank',
        'postedAt': DateTime.utc(2026, 6, 2, 10).millisecondsSinceEpoch,
        'title': title,
        'text': text,
      });

  test('the definitions that ship with the app are written to the table', () {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);

    final ids = ledger.parserRegistry.definitions.map((d) => d.id).toSet();
    expect(
      ids,
      containsAll(<String>['pk.ibft', 'pk.card.purchase']),
      reason: 'the registry is now built from the table, not from Dart',
    );
    for (final definition in ledger.parserRegistry.definitions) {
      expect(
        definition.rules,
        isNotEmpty,
        reason: '${definition.id} arrived with no rules, so it reads nothing',
      );
    }
    expect(ledger.refusedParserRules, isEmpty);
  });

  test('a bank the app has never seen becomes readable by adding a row', () {
    // The whole point, and the fixture took a correction to make honestly.
    //
    // It first read "... moved out to GREEN GROCER from your A/C xxx9001",
    // and the app parsed it without any new rule at all -- because "from
    // your a/c" is itself one of the generic debit signals. The alert below
    // carries no direction word the app knows: "towards" is not a verb any
    // shipped rule reads, and nothing else in the sentence says which way
    // the money went.
    final ledger = ledgerWithOneAccount();
    addTearDown(ledger.close);

    const alert =
        'Newbank: PKR 2,340.00 towards GREEN GROCER on 02-Jun-2026. '
        'Slip 55123';

    post(ledger, 'before', 'Newbank', alert);
    expect(
      ledger.snapshot().transactions,
      isEmpty,
      reason:
          'no shipped rule reads "towards", and the generic fallback has '
          'no direction word to go on either',
    );

    ledger.upsertParserDefinition(
      id: 'example.newbank',
      version: 1,
      name: 'Newbank',
      country: 'PK',
      institution: 'Newbank',
      sourceMatch: const {
        'packageNames': ['com.example.newbank'],
      },
      rules: [
        {
          'id': 'amount-towards-payee',
          'pattern':
              r'(?<amount>PKR\s*[\d,]+(?:\.\d{2})?)\s+towards\s+'
              r'(?<counterparty>[A-Z][A-Z ]+[A-Z])',
          'caseSensitive': false,
          'direction': 'debit',
          'type': 'purchase',
          'confidence': 0.9,
        },
      ],
    );

    post(ledger, 'after', 'Newbank', alert);
    final posted = ledger.snapshot().transactions;
    expect(
      posted,
      hasLength(1),
      reason: 'the row taught the app a bank, with no code change',
    );
    expect(posted.single.amount.minorUnits, 234000);
    expect(posted.single.kind, TransactionKind.expense);
  });

  test('switching a definition off stops its rules firing', () {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);

    expect(
      ledger.parserRegistry.definitions.map((d) => d.id),
      contains('pk.ibft'),
    );
    ledger.setParserDefinitionEnabled('pk.ibft', false);
    expect(
      ledger.parserRegistry.definitions.map((d) => d.id),
      isNot(contains('pk.ibft')),
    );
    ledger.setParserDefinitionEnabled('pk.ibft', true);
    expect(
      ledger.parserRegistry.definitions.map((d) => d.id),
      contains('pk.ibft'),
    );
  });

  test('a definition switched off is not switched back on by an upgrade', () {
    // Re-seeding on every launch would quietly undo the owner's decision,
    // and they would have no way to tell it had happened.
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);

    ledger.setParserDefinitionEnabled('pk.ibft', false);
    ledger.upsertParserDefinition(
      id: 'pk.ibft',
      version: 99,
      name: 'pk.ibft',
      country: 'PK',
      institution: null,
      sourceMatch: const {},
      rules: const [],
      keepEnabledState: true,
    );

    expect(
      ledger.parserRegistry.definitions.map((d) => d.id),
      isNot(contains('pk.ibft')),
    );
  });

  test('a dangerous pattern in the table is refused, not run', () {
    // A regular expression out of a row is code, and this shape does not
    // fail quickly — it fails eventually, on the isolate draining
    // notifications, so the app looks dead for no visible reason.
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);

    ledger.upsertParserDefinition(
      id: 'example.hostile',
      version: 1,
      name: 'Hostile',
      country: null,
      institution: null,
      sourceMatch: const {},
      rules: const [
        {'id': 'runaway', 'pattern': r'(a+)+$', 'direction': 'debit'},
      ],
    );

    final definition = ledger.parserRegistry.definitions.firstWhere(
      (d) => d.id == 'example.hostile',
    );
    expect(definition.rules, isEmpty);
    expect(ledger.refusedParserRules, hasLength(1));
    expect(ledger.refusedParserRules.single, contains('unbounded time'));
  });

  test('the stored form is readable JSON, not an opaque blob', () {
    // Definitions are meant to be written by hand and shared. If the column
    // were a binary encoding, "add a bank" would still be a code change,
    // just in a different file.
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);

    final stored = ledger.parserDefinitionRows().firstWhere(
      (row) => row['id'] == 'pk.card.purchase',
    );
    final rules = jsonDecode(stored['rules_json'] as String) as List;
    expect(rules, isNotEmpty);
    expect((rules.first as Map)['direction'], 'debit');
    expect((rules.first as Map)['pattern'], isA<String>());
    expect(stored['country'], 'PK');
    expect(stored['is_builtin'], 1);
  });
}
