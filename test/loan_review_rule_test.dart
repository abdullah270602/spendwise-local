import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/review/review_rules.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// Review asks about entries the parser was not sure of. A repayment that
/// lands there is the worst place to be wrong: the obvious answer is
/// "confirm", and confirming it files a loan coming home as money earned —
/// permanently, and in the month's figures.
///
/// So the loan question is asked before the ordinary ones, and it is asked
/// per loan, because the answer names one.
void main() {
  final opened = DateTime(2026, 9, 2);

  DebtViewData loan({
    String id = 'loan',
    String who = 'Sana',
    DebtKind kind = DebtKind.lent,
    int outstanding = 5000000,
  }) => DebtViewData(
    id: id,
    kind: kind,
    counterparty: who,
    principal: const MoneyViewData(5000000),
    settled: MoneyViewData(5000000 - outstanding),
    outstanding: MoneyViewData(outstanding),
    openedAt: opened,
    isSettled: outstanding == 0,
  );

  TransactionViewData entry({
    String id = 'back',
    String title = 'From Sana',
    int amount = 5000000,
    TransactionKind kind = TransactionKind.income,
    bool reviewed = false,
    String? debtId,
  }) => TransactionViewData(
    id: id,
    title: title,
    subtitle: 'Everyday',
    amount: MoneyViewData(amount),
    kind: kind,
    occurredAt: opened.add(const Duration(days: 18)),
    category: 'Uncategorised',
    accountName: 'Everyday',
    accountId: 'acc',
    isReviewed: reviewed,
    debtId: debtId,
  );

  List<ReviewRule> rules({
    required List<TransactionViewData> transactions,
    List<DebtViewData> debts = const [],
  }) => buildReviewRules(
    transactions: transactions,
    reviews: const [],
    accounts: const [
      AccountViewData(
        id: 'acc',
        name: 'Everyday',
        type: 'bank',
        balance: MoneyViewData(0),
      ),
    ],
    debts: debts,
  );

  test('a repayment awaiting review is asked about as a loan', () {
    final found = rules(transactions: [entry()], debts: [loan()]);
    expect(found.first.id, 'loan-loan');
    expect(
      found.first.claim,
      contains('Sana has money out with you'),
      reason: 'it names the loan, so the answer can be checked',
    );
  });

  test('the answer carries the loan and the entry', () {
    // Both halves matter. Without the loan there is nothing to settle;
    // without the entry the month goes on counting it as income.
    final decision = rules(
      transactions: [entry()],
      debts: [loan()],
    ).first.primary.decision;
    expect(decision.kind, ReviewDecisionKind.settleLoan);
    expect(decision.debtId, 'loan');
    expect(decision.transactionIds, ['back']);
  });

  test('saying no is an answer too', () {
    // A question with only one answer is a demand, and this one would
    // outlive the truth: an entry that really is income would sit in Review
    // for ever with nothing to say about it.
    final rule = rules(transactions: [entry()], debts: [loan()]).first;
    expect(rule.actions, hasLength(2));
    final refusal = rule.actions.last;
    expect(refusal.label, 'No, it is ordinary money in');
    expect(refusal.decision.kind, ReviewDecisionKind.confirm);
    expect(refusal.decision.transactionIds, ['back']);
  });

  test('it is asked before the ordinary filing questions', () {
    // Confirming one of these as ordinary money is not a filing mistake, it
    // is a wrong month. It has to be asked first or the obvious answer to
    // the catch-all takes it.
    final found = rules(
      transactions: [
        entry(),
        entry(
          id: 'shop',
          title: 'MAIN ROAD STORE',
          amount: 240000,
          kind: TransactionKind.expense,
        ),
      ],
      debts: [loan()],
    );
    expect(found.first.id, 'loan-loan');
    expect(found.length, greaterThan(1), reason: 'the rest still get asked');
  });

  test('an entry is only ever claimed by one question', () {
    final found = rules(transactions: [entry()], debts: [loan()]);
    final claims = <String>[];
    for (final rule in found) {
      for (final action in rule.actions) {
        claims.addAll(action.decision.transactionIds);
      }
    }
    expect(
      claims.where((id) => id == 'back').toSet(),
      hasLength(1),
      reason: 'two questions about one entry means two answers to give',
    );
    expect(found.where((rule) => rule.id != 'loan-loan'), isEmpty);
  });

  test('one rule per loan, not one per entry', () {
    final found = rules(
      transactions: [
        entry(id: 'one', title: 'From Sana', amount: 2000000),
        entry(id: 'two', title: 'From Sana', amount: 1000000),
      ],
      debts: [loan()],
    );
    expect(found.first.count, 2);
    expect(found.first.primary.label, 'Record all 2 against the loan');
    expect(found.first.primary.decision.transactionIds, ['one', 'two']);
  });

  test('two loans are two questions', () {
    final found = rules(
      transactions: [
        entry(id: 'a', title: 'From Sana', amount: 5000000),
        entry(id: 'b', title: 'From Omar', amount: 5000000),
      ],
      debts: [
        loan(),
        loan(id: 'other', who: 'Omar', outstanding: 5000000),
      ],
    );
    final ids = found.map((rule) => rule.id).toList();
    expect(ids, containsAll(['loan-loan', 'loan-other']));
  });

  test('nothing is asked when nothing matches', () {
    final found = rules(
      transactions: [entry(id: 'pay', title: 'Salary', amount: 9000000)],
      debts: [loan()],
    );
    expect(found.where((rule) => rule.id.startsWith('loan-')), isEmpty);
  });

  test('an entry already confirmed is left alone', () {
    // Review is what is still awaiting a decision. Reaching back into
    // confirmed history would make it a list that never empties.
    final found = rules(transactions: [entry(reviewed: true)], debts: [loan()]);
    expect(found.where((rule) => rule.id.startsWith('loan-')), isEmpty);
  });

  test('an entry already on a loan is not asked about again', () {
    final found = rules(
      transactions: [entry(debtId: 'loan')],
      debts: [loan()],
    );
    expect(found.where((rule) => rule.id.startsWith('loan-')), isEmpty);
  });

  test('with no loans open the rules are exactly what they were', () {
    final before = rules(transactions: [entry()]);
    expect(before.where((rule) => rule.id.startsWith('loan-')), isEmpty);
    expect(before, isNotEmpty, reason: 'the entry still needs filing');
  });

  test('the best loan takes it, not whichever was asked first', () {
    // Two loans of the same size both match a payment of that size on the
    // amount alone. Without a best-of pass, the first loan in the list
    // swallows a payment carrying the other one's name.
    final found = rules(
      transactions: [entry(id: 'b', title: 'From Omar', amount: 5000000)],
      debts: [
        loan(),
        loan(id: 'other', who: 'Omar'),
      ],
    );
    expect(found.first.id, 'loan-other');
    expect(found.first.primary.decision.transactionIds, ['b']);
  });
}
