import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/debts/debt_matching.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// A repayment arrives looking exactly like any other credit: money, from a
/// name. The app cannot settle a loan on that evidence, but it can ask -- and
/// the whole value of asking rests on it being right often enough to be worth
/// reading, and cautious enough that a wrong guess is never acted on alone.
///
/// The expensive failure is a false positive that gets confirmed: a loan the
/// owner believes is settled is money they will never ask for again.
void main() {
  final base = DateTime(2026, 9, 1);

  DebtViewData loan({
    String id = 'loan',
    String who = 'Sana',
    DebtKind kind = DebtKind.lent,
    int principal = 5000000,
    int settled = 0,
    DateTime? opened,
    bool closed = false,
    String currency = 'PKR',
  }) => DebtViewData(
    id: id,
    kind: kind,
    counterparty: who,
    principal: MoneyViewData(principal, currency: currency),
    settled: MoneyViewData(settled, currency: currency),
    outstanding: MoneyViewData(principal - settled, currency: currency),
    openedAt: opened ?? base,
    isSettled: closed,
  );

  TransactionViewData entry({
    String id = 'entry',
    String title = 'Transfer received',
    int amount = 5000000,
    TransactionKind kind = TransactionKind.income,
    DateTime? at,
    String? debtId,
    String currency = 'PKR',
  }) => TransactionViewData(
    id: id,
    title: title,
    subtitle: '',
    amount: MoneyViewData(amount, currency: currency),
    kind: kind,
    occurredAt: at ?? base.add(const Duration(days: 10)),
    category: 'Uncategorised',
    debtId: debtId,
  );

  List<DebtMatch> match(
    TransactionViewData transaction,
    List<DebtViewData> debts,
  ) => debtMatchesFor(transaction: transaction, debts: debts);

  group('what it suggests', () {
    test('the amount alone is enough when it is exactly what is out', () {
      final found = match(entry(), [loan()]);
      expect(found, hasLength(1));
      expect(found.single.strength, DebtMatchStrength.likely);
      expect(found.single.reason, 'it is exactly what is still out');
    });

    test('the name alone is enough for a part payment', () {
      final found = match(entry(title: 'From SANA KHAN', amount: 1500000), [
        loan(),
      ]);
      expect(found, hasLength(1));
      expect(found.single.reason, 'the name matches');
    });

    test('both together is the strongest thing it can say', () {
      final found = match(entry(title: 'Received from Sana'), [loan()]);
      expect(found.single.strength, DebtMatchStrength.exact);
    });

    test('a part payment by a stranger name says nothing at all', () {
      // The dangerous middle: an amount smaller than the loan, from a name
      // nobody recognises, is just a credit. Suggesting every one of those
      // teaches the owner to dismiss the prompt without reading it.
      expect(match(entry(title: 'Salary', amount: 1500000), [loan()]), isEmpty);
    });

    test('it never suggests more money than is still out', () {
      // More than the loan is a repayment plus something else, and nothing
      // here can say how much was which. Attaching it whole would take the
      // remainder out of the month's income too.
      expect(
        match(entry(title: 'From Sana', amount: 5000001), [loan()]),
        isEmpty,
      );
    });

    test('what is still out is what counts, not what was lent', () {
      // Half already came back in cash. The rest is now the figure to match.
      final half = loan(principal: 5000000, settled: 2500000);
      expect(match(entry(amount: 2500000), [half]), hasLength(1));
      expect(match(entry(amount: 5000000), [half]), isEmpty);
    });
  });

  group('what it refuses to suggest', () {
    test('a loan that is already settled', () {
      expect(match(entry(), [loan(settled: 5000000, closed: true)]), isEmpty);
    });

    test('an entry that already belongs to a loan', () {
      expect(match(entry(debtId: 'other'), [loan()]), isEmpty);
    });

    test('money moving the wrong way', () {
      // Money going out cannot be somebody repaying you.
      expect(match(entry(kind: TransactionKind.expense), [loan()]), isEmpty);
      // And money coming in cannot be you repaying somebody.
      expect(match(entry(), [loan(kind: DebtKind.borrowed)]), isEmpty);
    });

    test('a transfer between the owner own accounts', () {
      expect(match(entry(kind: TransactionKind.transfer), [loan()]), isEmpty);
    });

    test('an entry from before the loan existed', () {
      final old = entry(at: base.subtract(const Duration(days: 3)));
      expect(match(old, [loan()]), isEmpty);
    });

    test('but the same day counts, because a day is what people see', () {
      final sameDay = entry(at: DateTime(2026, 9, 1, 9));
      expect(
        match(sameDay, [loan(opened: DateTime(2026, 9, 1, 17))]),
        isNotEmpty,
      );
    });

    test('a loan in another currency', () {
      expect(match(entry(), [loan(currency: 'USD')]), isEmpty);
    });

    test('an entry of nothing', () {
      expect(match(entry(amount: 0), [loan(principal: 0)]), isEmpty);
    });
  });

  group('names', () {
    test('a name inside a longer word is not a name match', () {
      // "Ali" sits inside "Alia" and inside "Quality". A substring match here
      // would attach a stranger's payment to a real loan.
      expect(
        match(entry(title: 'From Alia', amount: 100000), [loan(who: 'Ali')]),
        isEmpty,
      );
      expect(
        match(entry(title: 'QUALITY MART', amount: 100000), [loan(who: 'Ali')]),
        isEmpty,
      );
    });

    test('case and punctuation do not matter', () {
      expect(
        match(entry(title: 'IBFT/SANA-KHAN/REF99', amount: 100000), [
          loan(who: 'Sana Khan'),
        ]),
        isNotEmpty,
      );
    });

    test('one word out of a full name is enough', () {
      expect(
        match(entry(title: 'Received from Khan', amount: 100000), [
          loan(who: 'Sana Khan'),
        ]),
        isNotEmpty,
      );
    });

    test('two-letter names are not matched on the name', () {
      // Short tokens are everywhere in bank narrations. Matching them would
      // be worse than not matching at all.
      expect(
        match(entry(title: 'IBFT to jo', amount: 100000), [loan(who: 'Jo')]),
        isEmpty,
      );
    });
  });

  group('ordering', () {
    test('the strongest reason comes first', () {
      final found = match(entry(title: 'From Sana'), [
        loan(id: 'amount-only', who: 'Bilal'),
        loan(id: 'both', who: 'Sana'),
      ]);
      expect(found.first.debt.id, 'both');
      expect(found.first.strength, DebtMatchStrength.exact);
    });

    test('among equals, the most recent loan', () {
      final found = match(entry(), [
        loan(id: 'older', who: 'Bilal', opened: DateTime(2026, 7, 1)),
        loan(id: 'newer', who: 'Omar', opened: DateTime(2026, 8, 20)),
      ]);
      expect(found.map((item) => item.debt.id), ['newer', 'older']);
    });

    test('it stops at three, however many fit', () {
      final many = [
        for (var i = 0; i < 9; i++)
          loan(id: 'loan$i', who: 'Person$i', opened: base),
      ];
      expect(match(entry(), many), hasLength(3));
    });
  });

  group('the picker is wider than the matcher', () {
    test('it offers every open loan the money could move against', () {
      // Deliberately not filtered by amount or name: the picker exists for
      // the payment the matcher was never going to recognise.
      final open = debtsOpenTo(
        transaction: entry(title: 'Unrecognisable', amount: 700),
        debts: [
          loan(id: 'a', who: 'Sana'),
          loan(id: 'b', who: 'Omar', opened: DateTime(2026, 8, 1)),
          loan(id: 'closed', settled: 5000000, closed: true),
          loan(id: 'wrong-way', kind: DebtKind.borrowed),
        ],
      );
      expect(open.map((item) => item.id), ['a', 'b']);
    });

    test('money going out offers what is owed and what is held', () {
      final open = debtsOpenTo(
        transaction: entry(kind: TransactionKind.expense),
        debts: [
          loan(id: 'lent'),
          loan(id: 'borrowed', kind: DebtKind.borrowed),
          loan(id: 'holding', kind: DebtKind.holding),
        ],
      );
      expect(open.map((item) => item.id), containsAll(['borrowed', 'holding']));
      expect(open.map((item) => item.id), isNot(contains('lent')));
    });
  });

  group('the two directions agree', () {
    test('an entry the loan lists is an entry that lists the loan', () {
      final theLoan = loan();
      final repayment = entry(title: 'From Sana');
      final noise = entry(id: 'noise', title: 'Salary', amount: 1200000);

      final fromLoan = entriesMatching(
        debt: theLoan,
        transactions: [repayment, noise],
      );
      expect(fromLoan.map((item) => item.id), ['entry']);
      expect(match(repayment, [theLoan]), isNotEmpty);
      expect(match(noise, [theLoan]), isEmpty);
    });

    test('the newest candidate is listed first', () {
      final theLoan = loan();
      final older = entry(
        id: 'older',
        title: 'From Sana',
        amount: 100000,
        at: base.add(const Duration(days: 2)),
      );
      final newer = entry(
        id: 'newer',
        title: 'From Sana',
        amount: 100000,
        at: base.add(const Duration(days: 20)),
      );
      final found = entriesMatching(
        debt: theLoan,
        transactions: [older, newer],
      );
      expect(found.map((item) => item.id), ['newer', 'older']);
    });

    test('a settled loan lists nothing', () {
      expect(
        entriesMatching(
          debt: loan(settled: 5000000, closed: true),
          transactions: [entry()],
        ),
        isEmpty,
      );
    });
  });
}
