import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/models/account.dart';
import 'package:spendwise/domain/models/canonical_transaction.dart';

/// A withdrawal moves money to a pocket. It is not spending, and the app
/// filed it as spending -- which made the totals roughly right and the
/// breakdown fiction, because everything actually bought with those notes
/// sends no notification and appeared nowhere.
///
/// The dangerous half of fixing that is the cutoff. Reconciliation rebuilds
/// automatic transactions from stored evidence every time it runs, so without
/// one, the first run after this arrived would reach back through every
/// withdrawal ever made and declare all of it cash still in a pocket. Months
/// of money long spent would reappear as money available.
void main() {
  LocalLedger openLedger() {
    final ledger = LocalLedger.openInMemoryForTests();
    addTearDown(ledger.close);
    ledger.rememberAndroidSources([
      {'packageName': 'pk.bank.app', 'label': 'Bank', 'configured': true},
    ]);
    ledger.addAccount(
      name: 'Everyday',
      type: AccountType.bank,
      openingBalanceMinor: 0,
      sourceIds: [ledger.sources().single.id],
    );
    return ledger;
  }

  void alert(
    LocalLedger ledger,
    String body, {
    String key = 'a',
    DateTime? at,
  }) {
    final when = (at ?? DateTime.now()).millisecondsSinceEpoch;
    ledger.ingestNotification({
      'id': key,
      'packageName': 'pk.bank.app',
      'notificationKey': key,
      'snapshotHash': key,
      'title': 'Bank',
      'text': body,
      'postedAt': when,
      'capturedAt': when,
    });
  }

  Account? cashAccount(LocalLedger ledger) {
    final cash = ledger.snapshot().accounts.where(
      (account) => account.type == AccountType.cash,
    );
    return cash.isEmpty ? null : cash.first;
  }

  test('cash arrives once setup is done, not before', () {
    // Before setup there is deliberately no cash bucket. Seven places in the
    // app ask whether the owner has any accounts yet -- onboarding's "add
    // your first one" among them -- and a bucket present from the very first
    // launch makes every one of those answers "yes" forever, so somebody new
    // would never be asked for their bank at all.
    final fresh = LocalLedger.openInMemoryForTests();
    addTearDown(fresh.close);
    expect(cashAccount(fresh), isNull);

    fresh.completeOnboarding();
    expect(cashAccount(fresh), isNotNull);
    expect(cashAccount(fresh)!.name, 'Cash');
  });

  test('a withdrawal makes one even if setup was skipped', () {
    // Somebody can walk past the accounts card. If a withdrawal turns up
    // anyway, it still has somewhere to land.
    final ledger = openLedger();
    expect(cashAccount(ledger), isNull);
    alert(ledger, 'PKR 3,000.00 cash withdrawn from A/C xxx1234');
    expect(cashAccount(ledger), isNotNull);
  });

  test('an ordinary payment does not put anything in it', () {
    final ledger = openLedger();
    alert(ledger, 'PKR 2,400 debited from A/C xxx1234 at MAIN ROAD STORE');
    expect(
      ledger.snapshot().transactions.where(
        (item) => item.kind == TransactionKind.transfer,
      ),
      isEmpty,
    );
  });

  test('a withdrawal makes the account and moves the money into it', () {
    final ledger = openLedger();
    alert(
      ledger,
      'PKR 12,300.00 cash withdrawn from MAIN ROAD BR ABC from A/C xxx1234 '
      'TID:111222',
    );

    final cash = cashAccount(ledger);
    expect(cash, isNotNull, reason: 'the first withdrawal creates it');
    expect(cash!.name, 'Cash');

    final moved = ledger
        .snapshot()
        .transactions
        .where((item) => item.kind == TransactionKind.transfer)
        .toList();
    expect(moved, hasLength(1));
    expect(moved.single.toAccountId, cash.id);
    expect(moved.single.amount.minorUnits, 1230000);
  });

  test('it is not spending, and does not read as spending', () {
    final ledger = openLedger();
    alert(
      ledger,
      'PKR 12,300.00 cash withdrawn from MAIN ROAD BR ABC from A/C xxx1234',
    );
    final spending = ledger.snapshot().transactions.where(
      (item) => item.kind == TransactionKind.expense,
    );
    expect(
      spending,
      isEmpty,
      reason: 'money in a pocket has not been spent yet',
    );
  });

  test('a withdrawal from before the account existed is left alone', () {
    // The cutoff. This is the whole reason the cash account carries its own
    // creation time rather than the code simply routing every withdrawal it
    // can see.
    final ledger = openLedger();
    alert(
      ledger,
      'PKR 9,000.00 cash withdrawn from MAIN ROAD BR ABC from A/C xxx1234',
      key: 'old',
      at: DateTime.now().subtract(const Duration(days: 120)),
    );

    // Nothing has created a cash account yet at the moment that old alert is
    // reconciled, so it stays what it always was.
    final beforeCash = ledger
        .snapshot()
        .transactions
        .where((item) => item.kind == TransactionKind.expense)
        .toList();
    expect(beforeCash, hasLength(1), reason: 'history keeps its meaning');

    // Now a withdrawal today, which does create the account.
    alert(
      ledger,
      'PKR 3,000.00 cash withdrawn from MAIN ROAD BR ABC from A/C xxx1234',
      key: 'new',
    );

    final cash = cashAccount(ledger);
    expect(cash, isNotNull);

    final transfers = ledger
        .snapshot()
        .transactions
        .where((item) => item.kind == TransactionKind.transfer)
        .toList();
    expect(
      transfers,
      hasLength(1),
      reason: 'only the withdrawal made after the account began is routed',
    );
    expect(transfers.single.amount.minorUnits, 300000);

    // And the old one is still an expense, not retroactively rewritten.
    final expenses = ledger
        .snapshot()
        .transactions
        .where((item) => item.kind == TransactionKind.expense)
        .toList();
    expect(expenses, hasLength(1));
    expect(expenses.single.amount.minorUnits, 900000);
  });

  test('reconciling again does not multiply the cash account', () {
    final ledger = openLedger();
    alert(ledger, 'PKR 3,000.00 cash withdrawn from A/C xxx1234', key: 'one');
    alert(ledger, 'PKR 4,000.00 cash withdrawn from A/C xxx1234', key: 'two');
    ledger.reconcilePendingEvidence();

    expect(
      ledger.snapshot().accounts.where((a) => a.type == AccountType.cash),
      hasLength(1),
    );
  });

  test('the cash account never swallows the alert that created it', () {
    // Found the hard way. Alerts are routed to accounts partly by name, and
    // an account called "Cash" matches the word "cash" in "cash withdrawn" --
    // so the second withdrawal was attributed to the cash account itself
    // rather than to the bank it actually left, and then routed nowhere
    // because it was already "in" cash. Cash is not a routing candidate: it
    // has no app and no account number, so a name match is the only way an
    // alert could ever reach it, and any alert that does is misrouted.
    final ledger = openLedger();
    alert(ledger, 'PKR 3,000.00 cash withdrawn from A/C xxx1234', key: 'one');
    alert(ledger, 'PKR 4,000.00 cash withdrawn from A/C xxx1234', key: 'two');

    final bank = ledger.snapshot().accounts.firstWhere(
      (account) => account.type == AccountType.bank,
    );
    final transfers = ledger
        .snapshot()
        .transactions
        .where((item) => item.kind == TransactionKind.transfer)
        .toList();

    expect(transfers, hasLength(2), reason: 'both left the bank');
    for (final moved in transfers) {
      expect(
        moved.fromAccountId,
        bank.id,
        reason: 'a withdrawal leaves the bank, never the pocket',
      );
    }
  });

  test('an ordinary payment is untouched by any of this', () {
    final ledger = openLedger();
    alert(ledger, 'PKR 3,000.00 cash withdrawn from A/C xxx1234', key: 'cash');
    alert(
      ledger,
      'PKR 2,400 debited from A/C xxx1234 at MAIN ROAD STORE',
      key: 'shop',
    );
    final expenses = ledger
        .snapshot()
        .transactions
        .where((item) => item.kind == TransactionKind.expense)
        .toList();
    expect(expenses, hasLength(1));
    expect(expenses.single.amount.minorUnits, 240000);
  });
}
