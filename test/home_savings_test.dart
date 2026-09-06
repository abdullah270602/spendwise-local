import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/dashboard/home_savings.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// "What I put away" is a flow, and it has to be read over whatever period
/// Home is set to — a week, a fortnight, a month, a custom range — never a
/// hardcoded month.
void main() {
  final from = DateTime(2026, 9, 1);
  final to = DateTime(2026, 10, 1);
  const savings = {'pot', 'hajj'};

  TransactionViewData move({
    required TransactionKind kind,
    required int minor,
    required int day,
    String? account,
    String? into,
  }) => TransactionViewData(
    id: '$kind-$day-$minor',
    title: 'x',
    subtitle: 'x',
    amount: MoneyViewData(minor),
    kind: kind,
    occurredAt: DateTime(2026, 9, day, 12),
    category: 'Other',
    accountId: account,
    toAccountId: into,
  );

  int saved(List<TransactionViewData> items) => savedInWindow(
    transactions: items,
    savingsAccountIds: savings,
    from: from,
    to: to,
  );

  test('money moved into a savings account is money put away', () {
    expect(
      saved([
        move(
          kind: TransactionKind.transfer,
          minor: 4000000,
          day: 3,
          account: 'current',
          into: 'pot',
        ),
      ]),
      4000000,
    );
  });

  test('and money taken back out is the opposite of putting it away', () {
    // Reporting only the inflow would tell someone who emptied their savings
    // that they had saved.
    expect(
      saved([
        move(
          kind: TransactionKind.transfer,
          minor: 4000000,
          day: 3,
          account: 'current',
          into: 'pot',
        ),
        move(
          kind: TransactionKind.transfer,
          minor: 1500000,
          day: 20,
          account: 'pot',
          into: 'current',
        ),
      ]),
      2500000,
    );
  });

  test('shuffling between two savings accounts puts nothing away', () {
    expect(
      saved([
        move(
          kind: TransactionKind.transfer,
          minor: 900000,
          day: 8,
          account: 'pot',
          into: 'hajj',
        ),
      ]),
      0,
    );
  });

  test('salary paid straight into savings counts', () {
    expect(
      saved([
        move(
          kind: TransactionKind.income,
          minor: 2000000,
          day: 2,
          account: 'hajj',
        ),
      ]),
      2000000,
    );
  });

  test('spending out of savings counts against it', () {
    expect(
      saved([
        move(
          kind: TransactionKind.transfer,
          minor: 3000000,
          day: 2,
          account: 'current',
          into: 'pot',
        ),
        move(
          kind: TransactionKind.expense,
          minor: 500000,
          day: 9,
          account: 'pot',
        ),
      ]),
      2500000,
    );
  });

  test('everyday spending is not savings movement', () {
    expect(
      saved([
        move(
          kind: TransactionKind.expense,
          minor: 750000,
          day: 4,
          account: 'current',
        ),
        move(
          kind: TransactionKind.transfer,
          minor: 100000,
          day: 5,
          account: 'current',
          into: 'wallet',
        ),
      ]),
      0,
    );
  });

  test('anything outside the window is another period’s business', () {
    final items = [
      move(
        kind: TransactionKind.transfer,
        minor: 4000000,
        day: 3,
        account: 'current',
        into: 'pot',
      ),
    ];
    expect(
      savedInWindow(
        transactions: items,
        savingsAccountIds: savings,
        from: DateTime(2026, 9, 10),
        to: DateTime(2026, 9, 17),
      ),
      0,
      reason: 'a fortnight that does not contain the transfer',
    );
  });

  test('with no savings accounts there is nothing to put away', () {
    expect(
      savedInWindow(
        transactions: [
          move(
            kind: TransactionKind.transfer,
            minor: 4000000,
            day: 3,
            account: 'current',
            into: 'pot',
          ),
        ],
        savingsAccountIds: const {},
        from: from,
        to: to,
      ),
      0,
    );
  });

  group('choosing how it shows', () {
    test('an unset choice keeps whatever the old switch did', () {
      expect(
        HomeSavingsStyle.fromId(null, legacyOn: true),
        HomeSavingsStyle.balance,
        reason: 'the switch drew a balance, so that is what they keep seeing',
      );
      expect(
        HomeSavingsStyle.fromId(null, legacyOn: false),
        HomeSavingsStyle.off,
      );
    });

    test('a stored choice wins over the old switch', () {
      expect(
        HomeSavingsStyle.fromId('divided', legacyOn: false),
        HomeSavingsStyle.divided,
      );
    });

    test('only three of them touch the shape itself', () {
      expect(HomeSavingsStyle.values.where((s) => s.changesTheShape), [
        HomeSavingsStyle.siblings,
        HomeSavingsStyle.divided,
        HomeSavingsStyle.seam,
      ]);
    });

    test('every option is named after a question, not a drawing', () {
      // The trap this is guarding: naming them "bar", "seam", "three-way".
      for (final style in HomeSavingsStyle.values) {
        expect(style.title, isNotEmpty);
        expect(style.detail, isNotEmpty, reason: style.id);
      }
    });
  });
}
