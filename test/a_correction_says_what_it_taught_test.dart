import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/domain/domain.dart';
import 'package:spendwise/features/transactions/transaction_details_screen.dart';

/// Correcting the same shop every week and never being told it landed.
///
/// Three filings of one payee under one category write a standing rule and
/// every filing after that is automatic. That has been true since the
/// feature shipped, and `categoryRuleThreshold`, `category_confirmations`
/// and `category_rule_id` had no reader outside the ledger — no view model,
/// no widget. The only place the rule of three was written down at all was a
/// help `brief:`, which is copied to the clipboard for pasting into an
/// external assistant. The app explained its learning to a language model
/// and not to its owner.
///
/// It mattered: a parser bug meant nothing was being learned from one
/// wallet's alerts for months, and the absence of a signal is what made the
/// absence of learning invisible.
void main() {
  LocalLedger walletLedger() {
    final ledger = LocalLedger.openInMemoryForTests();
    ledger.rememberAndroidSources([
      {
        'packageName': 'com.example.wallet',
        'label': 'Wallet',
        'configured': true,
      },
    ]);
    ledger.addAccount(
      name: 'Pocket',
      type: AccountType.wallet,
      accountSuffix: '9003',
      sourceIds: [ledger.sources().single.id],
    );
    return ledger;
  }

  void post(LocalLedger ledger, String key, int amount, int day) =>
      ledger.ingestNotification({
        'notificationKey': key,
        'snapshotHash': 'snap:$key',
        'packageName': 'com.example.wallet',
        'postedAt': DateTime.utc(2026, 6, day, 10).millisecondsSinceEpoch,
        'title': 'Money sent',
        'text': 'Money sent Rs. $amount sent to Corner Grocer.',
      });

  CategoryLesson fileOne(LocalLedger ledger, String key, int amount, int day) {
    post(ledger, key, amount, day);
    final entry = ledger.snapshot().transactions.firstWhere(
      (item) => item.amount.minorUnits == amount * 100,
    );
    ledger.categorizeTransactions([entry.id], 'groceries');
    final lesson = ledger.takeCategoryLesson();
    expect(lesson, isNotNull, reason: 'filing is what teaches; it must report');
    return lesson!;
  }

  test('it counts the corrections and says when the rule stands', () {
    final ledger = walletLedger();
    addTearDown(ledger.close);

    final first = fileOne(ledger, 'a', 101, 1);
    expect(first.merchant, 'Corner Grocer');
    expect(first.seen, 1);
    expect(first.needed, LocalLedger.categoryRuleThreshold);
    expect(first.learned, isFalse);
    expect(
      categoryLessonSentence(first),
      'Corner Grocer, 1 of 3. 2 more and it files itself.',
    );

    fileOne(ledger, 'b', 102, 2);
    final third = fileOne(ledger, 'c', 103, 3);
    expect(third.learned, isTrue);
    expect(
      categoryLessonSentence(third),
      'Corner Grocer now files itself under Groceries.',
    );
  });

  test('a lesson is reported once, not to every screen that asks', () {
    final ledger = walletLedger();
    addTearDown(ledger.close);
    fileOne(ledger, 'a', 101, 1);
    expect(
      ledger.takeCategoryLesson(),
      isNull,
      reason: 'two screens reading the same answer would report it twice',
    );
  });

  test('and says so when the alert names nobody to learn about', () {
    // The shape that caused the original complaint. The app cannot key a
    // rule on an entry with no payee, and saying nothing is indistinguishable
    // from learning — which is exactly how months of corrections went into a
    // drawer unnoticed.
    final ledger = walletLedger();
    addTearDown(ledger.close);
    ledger.ingestNotification({
      'notificationKey': 'nameless',
      'snapshotHash': 'snap:nameless',
      'packageName': 'com.example.wallet',
      'postedAt': DateTime.utc(2026, 6, 9, 10).millisecondsSinceEpoch,
      'title': 'Money sent',
      'text': 'Money sent Rs. 400 has been sent from your wallet. Slip 88',
    });
    final entry = ledger.snapshot().transactions.single;
    ledger.categorizeTransactions([entry.id], 'groceries');

    final lesson = ledger.takeCategoryLesson()!;
    expect(lesson.merchant, isNull);
    expect(lesson.learned, isFalse);
    expect(
      categoryLessonSentence(lesson),
      'Filed. Nothing to learn from: the alert names no payee.',
    );
  });
}
