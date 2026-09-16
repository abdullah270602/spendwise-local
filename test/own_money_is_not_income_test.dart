import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/money.dart';
import 'package:spendwise/domain/models/canonical_transaction.dart';
import 'package:spendwise/domain/models/event_candidate.dart';
import 'package:spendwise/domain/models/own_identity.dart';
import 'package:spendwise/domain/models/raw_observation.dart';
import 'package:spendwise/domain/parsing/notification_parser.dart';
import 'package:spendwise/domain/reconciliation/reconciler.dart';
import 'package:spendwise/domain/routing/account_router.dart';

/// Four ways a person's own money was counted as somebody paying them, and
/// one payment that reached the ledger twice.
///
/// Every one of these was found by exporting a real ledger with its raw
/// evidence attached and running the alerts back through this pipeline. The
/// fixtures below keep the *shape* of those alerts — the word order, where
/// the number sits, which app said it — and nothing else: names, account
/// tails, IBANs, references and merchants are invented.
///
/// The most important case here is the last one. Every rule that turns a
/// lone alert into a transfer has to refuse to fire on a payment to a
/// stranger who banks where the owner also banks, because that failure is
/// silent and it hides money genuinely leaving.
void main() {
  const bank = 'acct-bank';
  const wallet = 'acct-wallet';
  const other = 'acct-other';

  const accounts = [
    AccountProfile(
      id: bank,
      name: 'Everyday',
      institution: 'Northbank',
      suffix: '9001',
    ),
    AccountProfile(
      id: wallet,
      name: 'Pocket',
      institution: 'Pocket',
      suffix: '9003',
    ),
    AccountProfile(
      id: other,
      name: 'Second',
      institution: 'Southbank',
      suffix: '9002',
    ),
  ];

  const identity = OwnIdentity(
    names: {'Sample Owner', 'S.Owner'},
    accountSuffixes: {bank: '9001', wallet: '9003', other: '9002'},
    accountAliases: {
      bank: {'Everyday', 'Northbank'},
      wallet: {'Pocket'},
      other: {'Second', 'Southbank'},
    },
  );

  RawObservation alertFrom(
    String package,
    String title,
    String body,
    DateTime at, {
    String? accountId,
  }) => RawObservation(
    id: 'obs-${at.microsecondsSinceEpoch}-$package',
    kind: ObservationKind.notification,
    observedAt: at,
    title: title,
    body: body,
    accountId: accountId,
    sourcePackage: package,
  );

  EventCandidate candidateOf(RawObservation observation) {
    final parsed = const NotificationParser().parse(observation);
    expect(parsed, isNotNull, reason: 'the parser read nothing from the alert');
    return parsed!;
  }

  group('one alert can name both ends of a movement', () {
    test('a wallet top-up says which account funded it', () {
      // Rewritten from a real wallet alert. The bank behind the wallet sends
      // nothing at all when the wallet pulls from it, so the opposing leg the
      // pairing pass waits for never arrives, and this used to be filed as
      // income — money the owner already had, counted as money earned.
      final observation = alertFrom(
        'com.example.pocket',
        'Money, meet wallet',
        'Rs. 10,000 loaded through Northbank-9001 linked account. '
            'Just like that.',
        DateTime.utc(2026, 5, 1, 10),
        accountId: wallet,
      );
      final candidate = candidateOf(observation);
      expect(
        candidate.direction,
        EntryDirection.credit,
        reason:
            '"loaded through" is money arriving; it used to read as no '
            'direction at all and the alert went unparsed',
      );

      final result = const Reconciler(ownIdentity: identity)
          .reconcile([candidate]);
      final entry = result.transactions.single;
      expect(entry.kind, TransactionKind.transfer);
      expect(entry.fromAccountId, bank);
      expect(entry.toAccountId, wallet);
    });

    test('but not when the tail names more than one account', () {
      // Wallets opened against one phone number all carry the same four
      // digits as their "account tail", so a message quoting those digits
      // names every one of them and therefore none. This is not a contrived
      // case: it was true of three of the accounts in the ledger this test
      // came from.
      const shared = OwnIdentity(
        names: {'Sample Owner'},
        accountSuffixes: {bank: '9009', wallet: '9009', other: '9009'},
        accountAliases: {
          bank: {'Pocket'},
          wallet: {'Pocket'},
          other: {'Pocket'},
        },
      );
      final observation = alertFrom(
        'com.example.pocket',
        'Money, meet wallet',
        'Rs. 10,000 loaded through Pocket-9009 linked account.',
        DateTime.utc(2026, 5, 1, 10),
        accountId: wallet,
      );
      final result = const Reconciler(ownIdentity: shared)
          .reconcile([candidateOf(observation)]);
      expect(result.transactions.single.kind, isNot(TransactionKind.transfer));
    });
  });

  group('a lone credit from yourself is not income', () {
    // The bank that sent the money does not always say so. When only the
    // receiving side speaks there is no pair to make — but the counterparty
    // is the account holder's own name, and booking that as income at full
    // confidence inflated a month by the whole amount with nothing on screen
    // to notice.
    EventCandidate lonelyCredit() => candidateOf(
      alertFrom(
        'com.example.messages',
        'Northbank',
        'Northbank PKR 40,000.00 received from S.OWNER AC# xxxPYMT '
            'PK11SBNK01090 as RAAST payment to your AC# 9001 on '
            '13-May-2026 at 18:08',
        DateTime.utc(2026, 5, 13, 13, 8),
        accountId: bank,
      ),
    );

    test('it is held for review rather than posted', () {
      final result = const Reconciler(ownIdentity: identity)
          .reconcile([lonelyCredit()]);
      final entry = result.transactions.single;
      expect(entry.kind, TransactionKind.income);
      expect(
        entry.needsReview,
        isTrue,
        reason: 'money arriving from yourself is a question, not income',
      );
    });

    test('and becomes a transfer once a paired alert has named the bank', () {
      // An earlier transfer between the same two accounts settled as a pair,
      // and in doing so said which bank "PK11SBNK" is. That is enough for a
      // later lone alert to name where the money came from.
      final sent = candidateOf(
        alertFrom(
          'com.example.messages',
          'Northbank',
          'Northbank PKR 15,000.00 sent to S.OWNER PK11SBNKxx002 as RAAST '
              'payment from your AC# xxx9001 on 01-May-2026 at 01:31 '
              'TID:111111.',
          DateTime.utc(2026, 5, 1, 20, 31),
          accountId: bank,
        ),
      );
      final arrived = candidateOf(
        alertFrom(
          'com.example.messages',
          'Southbank',
          'Southbank PKR 15,000 received from SAMPLE OWNER NORTHBANK '
              'LIMITED in your Southbank A/C *9002 on 01-MAY-2026 01:31 '
              'via your Raast ID.',
          DateTime.utc(2026, 5, 1, 20, 31, 30),
          accountId: other,
        ),
      );

      final result = const Reconciler(ownIdentity: identity)
          .reconcile([sent, arrived, lonelyCredit()]);

      final lone = result.transactions.firstWhere(
        (item) => item.amount.minorUnits == 4000000,
      );
      expect(lone.kind, TransactionKind.transfer);
      expect(lone.fromAccountId, other);
      expect(lone.toAccountId, bank);
    });

    test('and a stranger at the same bank is still a payment', () {
      // The one that must not break. A bank code belongs to every customer
      // of that bank, so this carries the same "PK11SBNK" as the owner's own
      // account — and reading it as a transfer would take real money leaving
      // the ledger and file it as money that never left.
      final sent = candidateOf(
        alertFrom(
          'com.example.messages',
          'Northbank',
          'Northbank PKR 15,000.00 sent to S.OWNER PK11SBNKxx002 as RAAST '
              'payment from your AC# xxx9001 on 01-May-2026 at 01:31 '
              'TID:111111.',
          DateTime.utc(2026, 5, 1, 20, 31),
          accountId: bank,
        ),
      );
      final arrived = candidateOf(
        alertFrom(
          'com.example.messages',
          'Southbank',
          'Southbank PKR 15,000 received from SAMPLE OWNER NORTHBANK '
              'LIMITED in your Southbank A/C *9002 on 01-MAY-2026 01:31 '
              'via your Raast ID.',
          DateTime.utc(2026, 5, 1, 20, 31, 30),
          accountId: other,
        ),
      );
      final toStranger = candidateOf(
        alertFrom(
          'com.example.messages',
          'Northbank',
          'Northbank PKR 6,000.00 sent to R.STRANGER PK11SBNKxx070 as RAAST '
              'payment from your AC# xxx9001 on 09-May-2026 at 14:38 '
              'TID:222222.',
          DateTime.utc(2026, 5, 9, 9, 38),
          accountId: bank,
        ),
      );

      final result = const Reconciler(ownIdentity: identity)
          .reconcile([sent, arrived, toStranger]);
      final payment = result.transactions.firstWhere(
        (item) => item.amount.minorUnits == 600000,
      );
      expect(payment.kind, TransactionKind.expense);
      expect(payment.accountId, bank);
    });
  });

  test('a card tap reported twice is one payment', () {
    // The bank's SMS always carries a reference and the wallet app reporting
    // the same tap never does. That asymmetry used to settle the question by
    // itself: a reference on one side and none on the other was read as a
    // mismatch, so this whole class of duplicate was undetectable and the
    // payment landed in the ledger twice.
    final sms = candidateOf(
      alertFrom(
        'com.example.messages',
        'Northbank',
        'Northbank PKR 141.00 charged at CORNER BAKERY L for card used, '
            'from A/C xxx9001 on 09-May-2026 at 14:31 TID:333333',
        DateTime.utc(2026, 5, 9, 9, 31, 28),
        accountId: bank,
      ),
    );
    // Built by hand rather than parsed, and that is itself a finding: a card
    // wallet's notification is the merchant, the amount and the card, with no
    // word for the direction anywhere in it. The real one only parsed because
    // the card happened to be called "<Bank> Debit" and the parser read the
    // word "Debit" out of the account's own name. Leaning on that here would
    // be testing an accident.
    final walletApp = EventCandidate(
      id: 'candidate:wallet-tap',
      observation: alertFrom(
        'com.example.wallet',
        'CORNER & BAKERY',
        'CORNER & BAKERY Rs141 with Everyday',
        DateTime.utc(2026, 5, 9, 9, 31, 29),
        accountId: bank,
      ),
      accountId: bank,
      amount: Money.pkr(14100),
      direction: EntryDirection.debit,
      occurredAt: DateTime.utc(2026, 5, 9, 9, 31, 29),
      description: 'CORNER & BAKERY',
      confidence: 0.8,
      type: CandidateType.purchase,
    );

    final result = const Reconciler(ownIdentity: identity)
        .reconcile([sms, walletApp]);
    expect(
      result.transactions,
      hasLength(1),
      reason: 'one tap, two apps, one entry',
    );
    expect(result.transactions.single.evidenceIds, hasLength(2));
    expect(result.transactions.single.amount, Money.pkr(14100));
  });

  group('an app attached to one account speaks for that account', () {
    test('naming another bank in the text does not move the alert', () {
      // Wallets name the bank behind them in almost every message. Reading
      // that mention as the subject filed a top-up of the wallet against the
      // bank the money came out of.
      final routed = const AccountRouter().route(
        text:
            'Money, meet wallet Rs. 10,000 loaded through Northbank-9001 '
            'linked account.',
        accounts: accounts,
      );
      expect(routed, isNotNull);
      expect(
        routed!.namesAccountNumber,
        isFalse,
        reason:
            'the alert named a bank, not an account number, so the app it '
            'arrived from keeps it',
      );
    });

    test('quoting an account number does', () {
      final routed = const AccountRouter().route(
        text: 'Northbank PKR 141.00 charged from A/C xxx9001 on 09-May-2026',
        accounts: accounts,
      );
      expect(routed!.accountId, bank);
      expect(routed.namesAccountNumber, isTrue);
    });
  });
}
