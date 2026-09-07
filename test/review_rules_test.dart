import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/review/review_rules.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

void main() {
  TransactionViewData pending({
    required String id,
    TransactionKind kind = TransactionKind.expense,
    String category = 'Groceries',
    String accountName = 'Meezan',
    String? accountId = 'meezan',
    String title = 'Sample Supermarket',
    String body = '',
  }) => TransactionViewData(
    id: id,
    title: title,
    subtitle: accountName,
    amount: const MoneyViewData(106000),
    kind: kind,
    occurredAt: DateTime.utc(2026, 9, 4),
    category: category,
    accountName: accountName,
    accountId: accountId,
    isReviewed: false,
    evidence: [
      if (body.isNotEmpty)
        EvidenceViewData(
          id: 'ev-$id',
          sourceLabel: accountName,
          observedAt: DateTime.utc(2026, 9, 4),
          state: EvidenceState.accepted,
          body: body,
        ),
    ],
  );

  List<ReviewRule> rules(
    List<TransactionViewData> transactions, {
    List<ReviewViewData> reviews = const [],
    List<AccountViewData> accounts = const [],
  }) => buildReviewRules(
    transactions: transactions,
    reviews: reviews,
    accounts: accounts,
  );

  test('ten alerts of the same shape become one decision', () {
    final result = rules([for (var i = 0; i < 10; i++) pending(id: 'tx-$i')]);

    expect(result, hasLength(1));
    expect(result.single.count, 10);
    expect(result.single.primary.label, 'Confirm all 10');
    expect(result.single.primary.decision.transactionIds, hasLength(10));
  });

  test('a reviewed transaction is not a decision', () {
    final result = rules([
      TransactionViewData(
        id: 'settled',
        title: 'Careem',
        subtitle: 'NayaPay',
        amount: const MoneyViewData(64000),
        kind: TransactionKind.expense,
        occurredAt: DateTime.utc(2026, 9, 1),
        category: 'Transport',
        accountName: 'NayaPay',
        accountId: 'nayapay',
      ),
    ]);

    expect(result, isEmpty);
  });

  test('"credited to X from your account" is money out, not income', () {
    final result = rules([
      pending(
        id: 'misread',
        kind: TransactionKind.income,
        body: 'PKR 5,000 credited to SAMPLE PERSON from your account 1234',
      ),
    ]);

    expect(result.first.id, 'redirect');
    expect(result.first.primary.decision.kind, ReviewDecisionKind.redirect);
    expect(result.first.primary.decision.expense, isTrue);
    expect(result.first.evidence, contains('credited to SAMPLE PERSON'));
    expect(result.first.highlights, contains('credited to'));
  });

  test('money credited to your own account stays income', () {
    final result = rules([
      pending(
        id: 'real-income',
        kind: TransactionKind.income,
        body: 'PKR 150,000 has been credited to your account 1234',
      ),
    ]);

    expect(result.map((rule) => rule.id), isNot(contains('redirect')));
  });

  test('routing is only offered when nothing identifies the account', () {
    final labelled = rules([
      pending(id: 'labelled', accountId: null, accountName: 'Meezan'),
    ]);
    expect(labelled.single.primary.needsAccount, isFalse);

    final orphan = rules(
      [pending(id: 'orphan', accountId: null, accountName: '')],
      accounts: const [
        AccountViewData(
          id: 'ubl',
          name: 'UBL Current',
          type: 'bank',
          balance: MoneyViewData(0),
        ),
      ],
    );
    expect(orphan.single.id, 'route');
    expect(orphan.single.primary.needsAccount, isTrue);
  });

  test('own-account moves get their own decision, ahead of the catch-all', () {
    final result = rules([
      pending(id: 'move-1', kind: TransactionKind.transfer, accountId: null),
      pending(id: 'move-2', kind: TransactionKind.transfer, accountId: null),
      pending(id: 'spend-1'),
    ]);

    expect(result.first.id, 'transfer');
    expect(result.first.count, 2);
    expect(result.first.claim, contains('Not spending'));
    expect(result.map((rule) => rule.id), contains('confirm:Meezan'));
  });

  test('uncategorised spending asks for a category before confirming', () {
    final result = rules([
      pending(id: 'u-1', category: 'Other'),
      pending(id: 'u-2', category: 'Uncategorized'),
    ]);

    expect(result.single.id, 'categorize');
    expect(result.single.primary.needsCategory, isTrue);
    expect(result.single.count, 2);
  });

  test('every pending alert lands in exactly one decision', () {
    final transactions = [
      pending(
        id: 'a',
        kind: TransactionKind.income,
        body: 'PKR 900 credited to SOMEONE from your account',
      ),
      pending(id: 'b', accountId: null, accountName: ''),
      pending(id: 'c', kind: TransactionKind.transfer),
      pending(id: 'd', category: 'Other'),
      pending(id: 'e'),
      pending(id: 'f', accountName: 'UBL', accountId: 'ubl'),
    ];

    final result = rules(transactions);
    final covered = [
      for (final rule in result) ...rule.primary.decision.transactionIds,
    ];

    expect(covered, hasLength(transactions.length));
    expect(covered.toSet(), hasLength(transactions.length));
  });

  test('alerts that reached no account outrank every other decision', () {
    final result = buildReviewRules(
      transactions: [pending(id: 'ordinary')],
      reviews: const [],
      accounts: const [
        AccountViewData(
          id: 'meezan',
          name: 'Meezan Debit',
          type: 'bank',
          balance: MoneyViewData(0),
        ),
      ],
      unroutedAlerts: [
        for (var i = 0; i < 4; i++)
          AlertViewData(
            id: 'alert-$i',
            observedAt: DateTime.utc(2026, 9, 6),
            title: 'Unknown',
            body: 'PKR 4,500.00 debited at EXAMPLE CLINIC',
            sourceLabel: 'Messages',
            packageName: 'com.google.android.apps.messaging',
            status: 'review',
          ),
      ],
    );

    // Alerts that reached no account no longer make a question of their own.
    // They are a subset of the alerts an app failed to deliver -- the same
    // parse_status, plus `account_id IS NULL` -- so asking separately put one
    // alert on screen twice, under two claims, with two different answers.
    expect(
      result.map((rule) => rule.id),
      isNot(contains(startsWith('route-alerts:'))),
      reason: 'the per-app rule owns these now',
    );
    expect(
      result,
      hasLength(1),
      reason: 'only the ordinary confirm rule, since no app reported a pile',
    );
  });

  test('one app, one question, three answers', () {
    final result = buildReviewRules(
      transactions: const [],
      reviews: const [
        ReviewViewData(
          id: 'unparsed:com.google.android.apps.messaging',
          reason: ReviewReason.parseFailed,
          title: '4 unread alerts from Messages',
          description: 'SpendWise could not read these as transactions.',
          transactions: [],
        ),
      ],
      accounts: const [],
      unroutedAlerts: [
        AlertViewData(
          id: 'alert-0',
          observedAt: DateTime.utc(2026, 9, 6),
          title: 'Unknown',
          body: 'PKR 4,500.00 debited at EXAMPLE CLINIC',
          sourceLabel: 'Messages',
          packageName: 'com.google.android.apps.messaging',
          status: 'review',
        ),
      ],
    );

    final rule = result.single;
    expect(rule.count, 4, reason: 'the app total, counted once');
    expect(rule.unit, 'alerts from Messages');
    expect(rule.claim, contains('never reached your ledger'));
    expect(
      rule.evidence,
      contains('EXAMPLE CLINIC'),
      reason: 'a real body beats a description of why there is no body',
    );

    expect(rule.actions, hasLength(3));
    final [attach, file, drop] = rule.actions;

    expect(attach.decision.kind, ReviewDecisionKind.routeAlerts);
    expect(attach.needsAccount, isTrue);
    expect(attach.label, contains('account'));

    expect(file.decision.kind, ReviewDecisionKind.fileAlerts);
    expect(file.needsDirection, isTrue, reason: 'it asks before it files');

    expect(drop.decision.kind, ReviewDecisionKind.dismissSource);
    expect(drop.destructive, isTrue, reason: 'drawn last and quietest');

    // Every answer settles the same alerts, so the count above the buttons is
    // true whichever one is tapped.
    for (final action in rule.actions) {
      expect(
        action.decision.packageName,
        'com.google.android.apps.messaging',
        reason: action.label,
      );
    }
  });

  test('promotional SMS can be dropped, not only filed', () {
    // The reported dead end: a marketing message that parsed as nothing had
    // exactly one button, and that button filed it into an account.
    final result = buildReviewRules(
      transactions: const [],
      reviews: const [
        ReviewViewData(
          id: 'unparsed:com.google.android.apps.messaging',
          reason: ReviewReason.parseFailed,
          title: '1 unread alert from Messages',
          description: 'SpendWise could not read this as a transaction.',
          transactions: [],
        ),
      ],
      accounts: const [],
      unroutedAlerts: [
        AlertViewData(
          id: 'promo',
          observedAt: DateTime.utc(2026, 9, 6),
          title: 'Unknown',
          body: 'APP UPDATE pe unlock karien! FREE GBs, Mins aur Bohat Kuch!',
          sourceLabel: 'Messages',
          packageName: 'com.google.android.apps.messaging',
          status: 'review',
        ),
      ],
    );

    final rule = result.single;
    expect(
      rule.actions.any(
        (a) => a.decision.kind == ReviewDecisionKind.dismissSource,
      ),
      isTrue,
      reason: 'there has to be a way to say this was never money',
    );
    expect(rule.actions.last.label, 'Drop it');
    // Both follow-ups share a row, so neither may be long enough to force the
    // other into an ellipsis on a 360dp phone.
    for (final action in rule.actions.skip(1)) {
      expect(action.label.length, lessThan(18), reason: action.label);
    }
  });

  test('unreadable alerts stay a per-app decision', () {
    final result = rules(
      const [],
      reviews: const [
        ReviewViewData(
          id: 'unparsed:com.whatsapp',
          reason: ReviewReason.parseFailed,
          title: '7 unread alerts from WhatsApp',
          description: 'SpendWise could not read these as transactions.',
          transactions: [],
        ),
      ],
    );

    expect(result.single.count, 7);
    for (final action in result.single.actions) {
      expect(action.decision.packageName, 'com.whatsapp', reason: action.label);
    }
  });

  test('an unreadable alert offers a way to keep it, not only to bin it', () {
    // The reported dead end: the only button on the card destroyed the
    // alerts, and the only other affordance was to read them. If they were
    // real transactions -- which they usually are -- there was nowhere to go.
    final result = rules(
      const [],
      reviews: const [
        ReviewViewData(
          id: 'unparsed:pk.wallet',
          reason: ReviewReason.parseFailed,
          title: '2 unread alerts from Wallet',
          description: 'Nothing here says which way the money went.',
          transactions: [],
        ),
      ],
    );

    final rule = result.single;
    expect(
      rule.primary.decision.kind,
      ReviewDecisionKind.routeAlerts,
      reason: 'attaching an account leads: it also fixes the next alert',
    );
    expect(
      rule.actions.map((a) => a.decision.kind),
      containsAll([
        ReviewDecisionKind.routeAlerts,
        ReviewDecisionKind.fileAlerts,
        ReviewDecisionKind.dismissSource,
      ]),
    );

    // Dropping them is still offered -- it is just never the only answer.
    expect(rule.actions.last.decision.kind, ReviewDecisionKind.dismissSource);
    expect(rule.actions.last.label, 'Drop all 2');

    // And the evidence is still one tap away, so neither answer is blind.
    expect(rule.alternative, contains('Read'));
    expect(rule.opensAlertReader, isTrue);
  });
}
