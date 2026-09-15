import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

/// Banks do not settle together, and the app used to charge people for it.
///
/// One side alerts immediately; the other arrives an hour later, or never.
/// Somebody who does not want to wait fixes the first alert by hand — "this
/// was a move to my other account" — and that answer is locked. When the
/// second leg finally turns up there is no longer a candidate for it to pair
/// with, so it stood alone and posted as income.
///
/// The transfer was counted, and then the same money was counted again as
/// money earned. Five thousand moved; ten thousand in the ledger.
void main() {
  ({LocalLedger ledger, String north, String south}) twoBanks() {
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
    final north = ledger.addAccount(
      name: 'Everyday',
      type: AccountType.bank,
      accountSuffix: '9001',
      sourceIds: [
        sources.firstWhere((s) => s.packageName == 'com.example.north').id,
      ],
    );
    final south = ledger.addAccount(
      name: 'Second',
      type: AccountType.bank,
      accountSuffix: '9002',
      sourceIds: [
        sources.firstWhere((s) => s.packageName == 'com.example.south').id,
      ],
    );
    ledger.setOwnNames(['Sample Owner', 'S.Owner']);
    return (ledger: ledger, north: north, south: south);
  }

  // The reference varies per call, because it varies per payment. Reusing
  // one TID made two separate payments collapse into a single entry -- which
  // is correct behaviour (one reference is one payment) and made a test look
  // like it was proving something it was not.
  // The amount is written out in full rather than assembled as
  // "\$rupees,000", which produced "PKR 5000,000.00" -- a number no bank
  // would send, and one the old amount pattern happened to read as 5000
  // while a stricter reader reads the grouping and gets five million.
  void postSent(
    LocalLedger ledger,
    DateTime at, {
    String amount = '5,000.00',
    String reference = '111111',
  }) => ledger.ingestNotification({
    'notificationKey': 'sent-$at-$reference',
    'snapshotHash': 'snap:sent-$at-$reference',
    'packageName': 'com.example.north',
    'postedAt': at.millisecondsSinceEpoch,
    'title': 'Northbank',
    'text':
        'Northbank PKR $amount sent to S.OWNER from your '
        'A/C xxx9001 TID:$reference',
  });

  void postReceived(
    LocalLedger ledger,
    DateTime at, {
    String amount = '5,000.00',
    String who = 'SAMPLE OWNER',
  }) => ledger.ingestNotification({
    'notificationKey': 'got-$at-$who',
    'snapshotHash': 'snap:got-$at-$who',
    'packageName': 'com.example.south',
    'postedAt': at.millisecondsSinceEpoch,
    'title': 'Southbank',
    'text': 'Southbank PKR $amount received from $who in your A/C *9002',
  });

  void answerAsTransfer(
    LocalLedger ledger,
    CanonicalTransaction entry,
    String from,
    String to,
  ) => ledger.updateTransaction(
    id: entry.id,
    kind: TransactionKind.transfer,
    description: 'To my other account',
    occurredAt: entry.occurredAt,
    amountMinor: entry.amount.minorUnits,
    fromAccountId: from,
    toAccountId: to,
    categoryId: 'transfer',
  );

  test('a leg arriving after the owner answered is not a second event', () {
    final setup = twoBanks();
    final ledger = setup.ledger;
    addTearDown(ledger.close);
    final start = DateTime.utc(2026, 6, 1, 10);

    postSent(ledger, start);
    answerAsTransfer(
      ledger,
      ledger.snapshot().transactions.single,
      setup.north,
      setup.south,
    );

    // Twenty minutes later — past the ten-minute pairing window, and long
    // past the moment anybody would still be waiting.
    postReceived(ledger, start.add(const Duration(minutes: 20)));

    final entries = ledger.snapshot().transactions;
    expect(
      entries,
      hasLength(1),
      reason: 'the late alert describes money that is already in the ledger',
    );
    expect(entries.single.kind, TransactionKind.transfer);
    expect(
      entries.fold<int>(0, (sum, item) => sum + item.amount.minorUnits),
      500000,
      reason: 'five thousand moved; it used to read as ten',
    );
  });

  test('and it is kept as evidence for the answer, not thrown away', () {
    // The alert is still the bank's own account of what happened. Dropping
    // it would make the entry unverifiable against a statement.
    final setup = twoBanks();
    final ledger = setup.ledger;
    addTearDown(ledger.close);
    final start = DateTime.utc(2026, 6, 1, 10);

    postSent(ledger, start);
    answerAsTransfer(
      ledger,
      ledger.snapshot().transactions.single,
      setup.north,
      setup.south,
    );
    postReceived(ledger, start.add(const Duration(minutes: 20)));

    final id = ledger.snapshot().transactions.single.id;
    expect(
      ledger.evidenceForTransaction(id),
      hasLength(2),
      reason: 'both banks spoke, and both accounts of it are kept',
    );
  });

  test('a payment from somebody else is still a payment', () {
    // The rule that must not overreach. Money genuinely arriving from
    // another person, for the same amount, inside the same window, is
    // income — and swallowing it would be far worse than duplicating one,
    // because nothing on screen would ever say it happened.
    final setup = twoBanks();
    final ledger = setup.ledger;
    addTearDown(ledger.close);
    final start = DateTime.utc(2026, 6, 1, 10);

    postSent(ledger, start);
    answerAsTransfer(
      ledger,
      ledger.snapshot().transactions.single,
      setup.north,
      setup.south,
    );
    postReceived(
      ledger,
      start.add(const Duration(minutes: 20)),
      who: 'R. STRANGER',
    );

    final entries = ledger.snapshot().transactions;
    expect(
      entries,
      hasLength(2),
      reason: 'a stranger paying you is a real event of its own',
    );
    expect(
      entries.fold<int>(0, (sum, item) => sum + item.amount.minorUnits),
      1000000,
    );
  });

  test('a leg pointing the wrong way for that side is not swallowed', () {
    // The answered transfer goes north to south. Another *debit* on north
    // for the same amount is a second payment, not the other half of this
    // one — the direction is the whole test.
    final setup = twoBanks();
    final ledger = setup.ledger;
    addTearDown(ledger.close);
    final start = DateTime.utc(2026, 6, 1, 10);

    postSent(ledger, start);
    answerAsTransfer(
      ledger,
      ledger.snapshot().transactions.single,
      setup.north,
      setup.south,
    );
    postSent(
      ledger,
      start.add(const Duration(minutes: 25)),
      reference: '222222',
    );

    expect(ledger.snapshot().transactions, hasLength(2));
  });
}
