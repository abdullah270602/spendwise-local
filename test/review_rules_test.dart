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
    expect(result.single.actionLabel, 'Confirm all 10');
    expect(result.single.decision.transactionIds, hasLength(10));
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
    expect(result.first.decision.kind, ReviewDecisionKind.redirect);
    expect(result.first.decision.expense, isTrue);
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
    expect(labelled.single.needsAccount, isFalse);

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
    expect(orphan.single.needsAccount, isTrue);
  });

  test('own-account moves get their own decision, ahead of the catch-all', () {
    final result = rules([
      pending(id: 'move-1', kind: TransactionKind.transfer, accountId: null),
      pending(id: 'move-2', kind: TransactionKind.transfer, accountId: null),
      pending(id: 'spend-1'),
    ]);

    expect(result.first.id, 'transfer');
    expect(result.first.count, 2);
    expect(result.first.claim, contains('not spending'));
    expect(result.map((rule) => rule.id), contains('confirm:Meezan'));
  });

  test('uncategorised spending asks for a category before confirming', () {
    final result = rules([
      pending(id: 'u-1', category: 'Other'),
      pending(id: 'u-2', category: 'Uncategorized'),
    ]);

    expect(result.single.id, 'categorize');
    expect(result.single.needsCategory, isTrue);
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
      for (final rule in result) ...rule.decision.transactionIds,
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

    final first = result.first;
    expect(first.count, 4);
    expect(first.unit, 'alerts from Messages');
    expect(first.needsAccount, isTrue);
    expect(first.decision.kind, ReviewDecisionKind.routeAlerts);
    expect(first.decision.alertIds, hasLength(4));
    expect(
      first.opensAlertReader,
      isTrue,
      reason: 'a claim about raw alerts must be checkable against them',
    );
    // The ordinary confirm rule is still there, just behind it.
    expect(result, hasLength(2));
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
    expect(result.single.decision.kind, ReviewDecisionKind.dismissSource);
    expect(result.single.decision.packageName, 'com.whatsapp');
  });
}
