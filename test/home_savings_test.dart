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

  group('the figure', () {
    test('an unset choice shows only what you can spend', () {
      // Home's one job is to say what is left, and money deliberately put
      // away is not left. Chosen deliberately as the default, not inherited.
      expect(HomeSavingsStyle.fromId(null), HomeSavingsStyle.available);
    });

    test('a stored choice wins', () {
      expect(HomeSavingsStyle.fromId('divided'), HomeSavingsStyle.divided);
    });

    test('the two that never touched the figure no longer sit here', () {
      // They were values in this enum before the split. Anything stored under
      // those names must not resolve to a figure treatment.
      expect(HomeSavingsStyle.fromId('balance'), HomeSavingsStyle.off);
      expect(HomeSavingsStyle.fromId('moved'), HomeSavingsStyle.off);
      expect(
        HomeSavingsStyle.values.map((s) => s.id),
        isNot(anyElement(anyOf('balance', 'moved'))),
      );
    });

    test('three of them draw the saved slice', () {
      // "Only what I can spend" is not among them: it removes saving from the
      // ribbon as well as from the figure.
      expect(HomeSavingsStyle.values.where((s) => s.changesTheShape), [
        HomeSavingsStyle.siblings,
        HomeSavingsStyle.divided,
        HomeSavingsStyle.seam,
      ]);
    });

    test('two take saving out of the headline, only one names it', () {
      expect(HomeSavingsStyle.values.where((s) => s.setsSavingAside), [
        HomeSavingsStyle.available,
        HomeSavingsStyle.siblings,
      ]);
      expect(HomeSavingsStyle.values.where((s) => s.namesTheSaving), [
        HomeSavingsStyle.siblings,
      ]);
    });

    test('anything that sets saving aside must relabel the headline', () {
      // Guards the mistake this whole design turned on: a figure that
      // excludes savings cannot be called "still yours", because savings is
      // still yours.
      for (final style in HomeSavingsStyle.values) {
        if (!style.setsSavingAside) continue;
        expect(
          style.title.toLowerCase(),
          isNot(contains('still yours')),
          reason: style.id,
        );
      }
    });
  });

  group('the line underneath', () {
    test('nothing, unless asked for', () {
      expect(
        HomeSavingsExtra.resolve('none', 'available', legacyOn: false),
        HomeSavingsExtra.none,
      );
    });

    test('it inherits from the setting it was split out of', () {
      // Someone who had picked "what I put away" keeps seeing it, even though
      // that value now lives in a different enum entirely.
      expect(
        HomeSavingsExtra.resolve(null, 'moved', legacyOn: false),
        HomeSavingsExtra.moved,
      );
      expect(
        HomeSavingsExtra.resolve(null, 'balance', legacyOn: false),
        HomeSavingsExtra.balance,
      );
    });

    test('and from the switch before that', () {
      expect(
        HomeSavingsExtra.resolve(null, null, legacyOn: true),
        HomeSavingsExtra.balance,
        reason: 'the old switch drew a balance',
      );
      expect(
        HomeSavingsExtra.resolve(null, null, legacyOn: false),
        HomeSavingsExtra.none,
      );
    });

    test('an explicit choice is never overridden by inheritance', () {
      // The bug this guards: picking "nothing" while an old value is still
      // stored, and having the old value quietly win.
      expect(
        HomeSavingsExtra.resolve('none', 'moved', legacyOn: true),
        HomeSavingsExtra.none,
      );
    });

    test('they compose with any figure treatment', () {
      // The point of the split. Every combination has to be reachable --
      // previously choosing one silently gave up the other.
      for (final style in HomeSavingsStyle.values) {
        for (final extra in HomeSavingsExtra.values) {
          expect(HomeSavingsStyle.fromId(style.id), style);
          expect(
            HomeSavingsExtra.resolve(extra.id, style.id, legacyOn: false),
            extra,
            reason: '${style.id} + ${extra.id}',
          );
        }
      }
    });
  });

  group('naming', () {
    test('every option is named after a question, not a drawing', () {
      for (final style in HomeSavingsStyle.values) {
        expect(style.title, isNotEmpty);
        expect(style.detail, isNotEmpty, reason: style.id);
      }
      for (final extra in HomeSavingsExtra.values) {
        expect(extra.title, isNotEmpty);
        expect(extra.detail, isNotEmpty, reason: extra.id);
      }
    });

    test('a detail line stays a line', () {
      // The clutter this screen was rebuilt to remove: rows whose explanation
      // ran longer than the preview that explains it better.
      for (final style in HomeSavingsStyle.values) {
        expect(style.detail.length, lessThan(80), reason: style.id);
      }
      for (final extra in HomeSavingsExtra.values) {
        expect(extra.detail.length, lessThan(80), reason: extra.id);
      }
    });
  });
}
