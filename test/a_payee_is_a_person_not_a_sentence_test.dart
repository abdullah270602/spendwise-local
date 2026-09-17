import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';

/// Entries named after the machinery instead of the person.
///
/// A RAAST alert puts the beneficiary's IBAN and the name of the instrument
/// between "sent to" and "from your A/C", and the shaped rules capture
/// whatever runs between those two anchors. So an entry arrived called
/// "S.Karim PK68MFB as RAAST payment" — a name, half an account number and
/// a description of the payment rail, in the place where a person's name
/// should be.
///
/// Two separate faults. The narration was never trimmed, although the
/// generic reader has always stopped at "as" and "via". And the IBAN was
/// only recognised unmasked, while banks mask it at least four ways, so
/// every masked one skipped the fold that turns an account number into a
/// bank and four digits.
///
/// The stored counterparty keeps the account number: the reconciler reads
/// the bank code out of it to pair the two legs of a transfer between the
/// owner's own accounts. Only the name on screen drops it. Every name and
/// number below is invented.
void main() {
  const parser = NotificationParser();

  ({String? counterparty, String? shown}) read(String body) {
    final candidate = parser
        .parseDetailed(
          RawObservation(
            id: 'obs',
            kind: ObservationKind.notification,
            observedAt: DateTime.utc(2026, 9, 12),
            title: 'Northbank',
            body: body,
            accountId: 'acct-bank',
            sourcePackage: 'com.example.messages',
          ),
        )
        .candidate;
    return (
      counterparty: candidate?.counterparty,
      shown: candidate?.description,
    );
  }

  String sent(String beneficiary) =>
      'Northbank PKR 5,000.00 sent to $beneficiary as RAAST payment '
      'from your AC# xxx9001 on 12-Sep-2026 TID:441002';

  test('the rail is not part of who was paid', () {
    final entry = read(sent('S.KARIM'));
    expect(entry.counterparty, 'S.KARIM');
    expect(entry.shown, 'S.KARIM');
  });

  test('a masked account number is not part of the name either', () {
    for (final masked in [
      'PK68MFBLxxxx1234',
      r'PK68MFBL****1234',
      'PK68MFBL\u2022\u2022\u2022\u20221234',
    ]) {
      final entry = read(sent('S.KARIM $masked'));
      expect(
        entry.shown,
        'S.KARIM',
        reason: '$masked was left sitting in the name',
      );
      expect(
        entry.counterparty,
        contains('PK68MFBL'),
        reason:
            'the reconciler reads the bank code out of this to pair the '
            'two legs of a transfer between the owner own accounts',
      );
    }
  });

  test('a truncated one names the person and drops the fragment', () {
    // "PK68MFB" says neither which bank nor which account.
    final entry = read(sent('S.KARIM PK68MFB'));
    expect(entry.shown, 'S.KARIM');
  });

  test('an unmasked account number reads as it always did', () {
    final entry = read(sent('A.IBRAHIM PK91NBPA0099887766550123'));
    expect(entry.shown, 'A.IBRAHIM');
  });

  test('a name already written down is repaired where it sits', () {
    // Re-reading the alerts fixes what the parser does next and cannot fix
    // these: an entry the owner has confirmed or filed is locked, and
    // reconcile is right never to rewrite one. The rows are repaired in
    // place instead.
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    ledger.addAccount(name: 'Everyday', type: AccountType.bank);
    final account = ledger.snapshot().accounts.single;

    final id = ledger.addManualTransaction(
      kind: TransactionKind.expense,
      amountMinor: 76000,
      occurredAt: DateTime.utc(2026, 9, 17, 12),
      accountId: account.id,
      description: 'S.KARIM PK68TMFBxx226 as RAAST payment',
      categoryId: 'groceries',
    );
    final typed = ledger.addManualTransaction(
      kind: TransactionKind.expense,
      amountMinor: 50000,
      occurredAt: DateTime.utc(2026, 9, 17, 13),
      accountId: account.id,
      description: 'Waqas Shabbir',
      categoryId: 'transport',
    );

    ledger.resetPayeeNameRepairForTests();
    ledger.rerunMigrationsForTests();

    String nameOf(String wanted) => ledger
        .snapshot()
        .transactions
        .firstWhere((item) => item.id == wanted)
        .description!;

    expect(nameOf(id), 'S.KARIM');
    expect(
      nameOf(typed),
      'Waqas Shabbir',
      reason: 'a name somebody typed is not of that shape and is not touched',
    );
  });

  test('a Raast ID is narration too', () {
    final entry = read(
      'Northbank PKR 5,000.00 sent to S.KARIM via Raast ID 03001234567 '
      'from your AC# xxx9001',
    );
    expect(entry.shown, 'S.KARIM');
  });
}
