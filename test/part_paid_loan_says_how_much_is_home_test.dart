import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';
import 'package:spendwise/features/transactions/transaction_details_screen.dart';

/// A loan that is half home has worked since loans arrived, and nothing drew
/// it.
///
/// `debt_settlements` takes a row per repayment and `outstanding = principal −
/// Σ settled`, so recording five thousand against a ten thousand loan has
/// always done the right thing to the arithmetic. What the entry screen said
/// afterwards was "5,000 still out" and nothing else — no principal, no total
/// returned, no instalments — so a loan barely started and a loan nearly
/// finished read identically, and the owner had no way to tell them apart
/// without opening the loan itself.
///
/// The block that fixes it must never be mistakable for an account: it
/// carries a 2px tone rule down its left edge that the balance trail never
/// has. And the proportion it draws is bound by two refusals — a share too
/// small to fill a pixel draws nothing rather than a sliver reading "money
/// came back", and a share under 100% never fills the last pixel, so "nearly
/// settled" cannot be mistaken for "settled".
///
/// Every name and figure below is invented.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final opened = DateTime(2026, 8, 4);

  DebtViewData loan({
    int principal = 1000000,
    int settled = 500000,
    int settledByHand = 0,
    DebtKind kind = DebtKind.lent,
    bool isSettled = false,
    DateTime? closedAt,
  }) => DebtViewData(
    id: 'debt-1',
    kind: kind,
    counterparty: 'Rameez Alvi',
    principal: MoneyViewData(principal),
    settled: MoneyViewData(settled),
    settledByHand: MoneyViewData(settledByHand),
    outstanding: MoneyViewData(principal - settled),
    openedAt: opened,
    isSettled: isSettled,
    closedAt: closedAt,
  );

  /// The entry that opened the loan: money leaving, for a loan that was lent.
  TransactionViewData lending({int minor = 1000000}) => TransactionViewData(
    id: 'tx-open',
    title: 'Sent to Rameez Alvi',
    subtitle: 'Daily Current',
    amount: MoneyViewData(-minor),
    kind: TransactionKind.expense,
    occurredAt: opened,
    category: 'Lent out',
    accountName: 'Daily Current',
    accountId: 'acct-current',
    debtId: 'debt-1',
    evidenceCount: 0,
  );

  /// One payment into it: money arriving, on a loan that was lent.
  TransactionViewData repayment({
    required String id,
    required int minor,
    required DateTime at,
  }) => TransactionViewData(
    id: id,
    title: 'From Rameez Alvi',
    subtitle: 'Daily Current',
    amount: MoneyViewData(minor),
    kind: TransactionKind.income,
    occurredAt: at,
    category: 'Lent out',
    accountName: 'Daily Current',
    accountId: 'acct-current',
    debtId: 'debt-1',
    evidenceCount: 0,
    balances: const [
      AccountBalanceChange(
        accountId: 'acct-current',
        accountName: 'Daily Current',
        beforeMinor: 4112000,
        afterMinor: 4612000,
      ),
    ],
  );

  Future<void> pump(
    WidgetTester tester,
    _Fake model,
    TransactionViewData transaction,
  ) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: TransactionDetailsScreen(
          viewModel: model,
          transaction: transaction,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The figure printed beside [label].
  ///
  /// Every row on this screen is an eyebrow and then its figure, in that
  /// order, so the text immediately after the label in the tree is the number
  /// it belongs to.
  int figureBeside(WidgetTester tester, String label) {
    final printed = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '')
        .toList();
    final at = printed.indexOf(label);
    expect(at, isNot(-1), reason: 'no row on screen is labelled $label');
    final figure = printed[at + 1].replaceAll(RegExp('[^0-9]'), '');
    expect(figure, isNotEmpty, reason: '$label was followed by no figure');
    return int.parse(figure);
  }

  group('a loan that is half home says so', () {
    testWidgets('it states the principal, what came back and what is out', (
      tester,
    ) async {
      final back = repayment(
        id: 'tx-back',
        minor: 500000,
        at: DateTime(2026, 8, 24),
      );
      final model = _Fake(debts: [loan()], transactions: [lending(), back]);
      await pump(tester, model, back);

      expect(find.text('PRINCIPAL'), findsOneWidget);
      expect(find.text('BACK'), findsOneWidget);
      expect(find.text('STILL OUT'), findsOneWidget);

      final principal = figureBeside(tester, 'PRINCIPAL');
      final returned = figureBeside(tester, 'BACK');
      final out = figureBeside(tester, 'STILL OUT');
      expect(principal, 10000);
      expect(returned, 5000);
      expect(out, 5000);
      expect(
        returned + out,
        principal,
        reason:
            'the three figures are the whole point of the block; if they do '
            'not add up it is worse than not drawing them',
      );
    });

    testWidgets('and names the instalment that brought it', (tester) async {
      final back = repayment(
        id: 'tx-back',
        minor: 500000,
        at: DateTime(2026, 8, 24),
      );
      final model = _Fake(debts: [loan()], transactions: [lending(), back]);
      await pump(tester, model, back);

      expect(
        find.textContaining('THIS ENTRY'),
        findsOneWidget,
        reason:
            'the history row says "this entry" rather than repeating the date '
            'and amount already at the top of the screen',
      );
      expect(find.textContaining('5,000 OF 10,000 BACK'), findsOneWidget);
    });

    testWidgets('a loan block is never mistakable for an account block', (
      tester,
    ) async {
      // The balance trail is bordered on all four sides in the same hairline.
      // A loan carries a 2px rule in its own tone down its left edge and
      // nothing else does, because a loan is not an account and reading one
      // as the other is the mistake this block could cause.
      final back = repayment(
        id: 'tx-back',
        minor: 500000,
        at: DateTime(2026, 8, 24),
      );
      final model = _Fake(debts: [loan()], transactions: [lending(), back]);
      await pump(tester, model, back);

      final rules = tester
          .widgetList<Container>(find.byType(Container))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .map((decoration) => decoration.border)
          .whereType<Border>()
          .where((border) => border.left.width == 2)
          .toList();
      expect(
        rules.map((border) => border.left.color),
        contains(SpendWiseColors.keep),
        reason: 'a loan that was lent out carries the keep tone on its edge',
      );
    });
  });

  testWidgets('a loan repaid in two instalments reads as settled, and lists '
      'both', (tester) async {
    final closed = DateTime(2026, 9, 12);
    final first = repayment(
      id: 'tx-first',
      minor: 500000,
      at: DateTime(2026, 8, 24),
    );
    final second = repayment(id: 'tx-second', minor: 500000, at: closed);
    final model = _Fake(
      debts: [loan(settled: 1000000, isSettled: true, closedAt: closed)],
      transactions: [lending(), first, second],
    );
    await pump(tester, model, second);

    expect(find.text('SETTLED 12 SEP'), findsOneWidget);
    expect(
      find.textContaining('ALL 10,000 BACK'),
      findsOneWidget,
      reason: 'a finished loan is history, and one line carries the outcome',
    );
    expect(find.textContaining('2 PAYMENTS'), findsOneWidget);
    expect(
      find.text('STILL OUT'),
      findsNothing,
      reason:
          'three figures where one is 0 and another equals the principal is '
          'arithmetic nobody needs performed',
    );

    // The two payments are one tap away, if the owner ever has to prove it.
    await tester.tap(find.text('How it came back'));
    await tester.pumpAndSettle();
    expect(find.textContaining('24 AUG'), findsOneWidget);
    expect(find.textContaining('12 SEP  ·  THIS ENTRY'), findsOneWidget);
    expect(find.text('5,000'), findsNWidgets(2));
  });

  group('the proportion rule refuses two lies', () {
    test('a share too small to fill a pixel draws nothing', () {
      // Inside the 22px gutter the rule is about 316dp on a 360dp phone, so
      // one pixel is roughly a third of a per cent. A sliver on a loan where
      // nothing has come back reads as "something arrived", which is worse
      // than an empty rule.
      expect(LoanShareRule.fillWidth(width: 316, fraction: 0), 0);
      expect(LoanShareRule.fillWidth(width: 316, fraction: 0.001), 0);
      expect(
        LoanShareRule.fillWidth(width: 316, fraction: 0.01),
        greaterThan(0),
        reason: 'one per cent of 316 is over a pixel, and it did happen',
      );
    });

    test('and a share under 100% never fills the last pixel', () {
      expect(
        LoanShareRule.fillWidth(width: 316, fraction: 0.999),
        lessThan(316),
        reason: '"nearly settled" must never be drawn as "settled"',
      );
      expect(LoanShareRule.fillWidth(width: 316, fraction: 1), 316);
      expect(
        LoanShareRule.fillWidth(width: 316, fraction: 1.4),
        316,
        reason: 'nothing is ever drawn past full, whatever the figures say',
      );
    });

    testWidgets('a loan with nothing back draws an empty rule', (tester) async {
      final model = _Fake(debts: [loan(settled: 0)], transactions: [lending()]);
      await pump(tester, model, lending());

      expect(find.text('NOTHING BACK YET'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('loan-share-fill'))).width,
        0,
        reason: 'nothing came back, so nothing is drawn',
      );
    });

    testWidgets('and one nearly home stops short of the end', (tester) async {
      final back = repayment(
        id: 'tx-back',
        minor: 100000,
        at: DateTime(2026, 8, 24),
      );
      final model = _Fake(
        debts: [loan(principal: 100000000, settled: 99900000)],
        transactions: [lending(), back],
      );
      await pump(tester, model, back);

      final track = tester
          .getSize(find.byKey(const Key('loan-share-track')))
          .width;
      final fill = tester
          .getSize(find.byKey(const Key('loan-share-fill')))
          .width;
      expect(fill, greaterThan(0));
      expect(
        fill,
        lessThan(track),
        reason: 'a thousandth still out is still out',
      );
    });
  });
}

/// Only what this screen reads. `noSuchMethod` covers the rest so growing the
/// view model does not break this file.
class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  _Fake({required this.debts, required this.transactions});

  @override
  final List<DebtViewData> debts;

  @override
  final List<TransactionViewData> transactions;

  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'acct-current',
      name: 'Daily Current',
      type: 'bank',
      balance: MoneyViewData(4612000),
    ),
  ];

  @override
  bool get busy => false;

  @override
  String? get errorMessage => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
