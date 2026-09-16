import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';
import 'package:spendwise/features/transactions/transaction_details_screen.dart';

/// The entry screen used to say the same thing up to three times.
///
/// It stated the transaction's *type* twice — a header eyebrow reading
/// "expense", then a "Type: Expense" row four lines below it. It stated the
/// *category* twice, in the header subtitle and again in a "Category:" row.
/// It stated the *account* three times: subtitle, "Account:" row, and the
/// heading of the balance block. A reader checking a figure against a bank
/// statement had to read past five rows of facts they had already read.
///
/// It also asked the wrong question. "Whose money was this?" was three
/// permanent full-width buttons on every ordinary entry, so money *arriving*
/// in an account was offered "I lent it out" — an answer that cannot be true
/// of money that arrived. And a transfer between the owner's own accounts,
/// which the matcher and the hand picker both refuse outright, said nothing
/// about the refusal at all: a correct decision nobody can see is
/// indistinguishable from a bug.
///
/// Every name, account and figure below is invented.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TransactionViewData entry({
    String id = 'tx-1',
    String title = 'Gulberg Grocers',
    TransactionKind kind = TransactionKind.expense,
    int minor = 348000,
    String category = 'Groceries',
    String accountName = 'Daily Current',
    List<AccountBalanceChange> balances = const [
      AccountBalanceChange(
        accountId: 'acct-current',
        accountName: 'Daily Current',
        beforeMinor: 4120500,
        afterMinor: 3772500,
      ),
    ],
  }) => TransactionViewData(
    id: id,
    title: title,
    subtitle: 'Daily Current · card',
    // Signed the way the controller signs it: an expense is stored negative
    // and everything else positive, and the screen prints what it is given.
    amount: MoneyViewData(
      kind == TransactionKind.expense ? -minor.abs() : minor.abs(),
    ),
    kind: kind,
    occurredAt: DateTime(2026, 9, 9, 18, 42),
    category: category,
    accountName: accountName,
    accountId: 'acct-current',
    evidenceCount: 0,
    balances: balances,
  );

  /// Both legs of one movement between the owner's own accounts.
  const transferBalances = [
    AccountBalanceChange(
      accountId: 'acct-current',
      accountName: 'Daily Current',
      beforeMinor: 6272500,
      afterMinor: 3772500,
    ),
    AccountBalanceChange(
      accountId: 'acct-fund',
      accountName: 'Emergency Fund',
      beforeMinor: 18640000,
      afterMinor: 21140000,
    ),
  ];

  DebtViewData loan({
    String id = 'debt-1',
    String who = 'Rameez Alvi',
    DebtKind kind = DebtKind.lent,
    int outstanding = 500000,
  }) => DebtViewData(
    id: id,
    kind: kind,
    counterparty: who,
    principal: const MoneyViewData(1000000),
    settled: MoneyViewData(1000000 - outstanding),
    outstanding: MoneyViewData(outstanding),
    openedAt: DateTime(2026, 8, 4),
    isSettled: outstanding == 0,
  );

  /// A phone with room for the whole page at once.
  ///
  /// A `ListView` only mounts what is near the viewport, and counting how
  /// many times a fact is printed is a question about the whole page rather
  /// than about what fits on it. The layout tests below use a real 360×800
  /// phone; this one deliberately does not.
  void tallPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> pump(
    WidgetTester tester,
    _Fake model,
    TransactionViewData transaction,
  ) async {
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

  /// How many rendered pieces of text on the page contain [needle].
  ///
  /// Case-insensitive and by substring, because the duplication this screen
  /// had was never letter-for-letter: the eyebrow said "expense" and the row
  /// below it said "Expense".
  int mentions(WidgetTester tester, String needle) {
    final lower = needle.toLowerCase();
    var count = 0;
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final data = text.data ?? text.textSpan?.toPlainText() ?? '';
      if (data.toLowerCase().contains(lower)) count++;
    }
    return count;
  }

  /// The three stories live behind one disclosure now. Nothing under it is
  /// in the tree until it is opened.
  Future<void> openWhoseMoney(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Whose money was this?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Whose money was this?'));
    await tester.pumpAndSettle();
  }

  group('nothing is said twice', () {
    testWidgets('the account is named once, where it is being checked', (
      tester,
    ) async {
      tallPhone(tester);
      await pump(tester, _Fake(), entry());

      expect(
        mentions(tester, 'Daily Current'),
        1,
        reason:
            'it was in the header subtitle, in an "Account:" row and as the '
            'heading of the balance block; only the last of those is where '
            'anybody reads it against a statement',
      );
    });

    testWidgets('the category is named once, on the fact line', (tester) async {
      tallPhone(tester);
      await pump(tester, _Fake(), entry());

      expect(
        mentions(tester, 'groceries'),
        1,
        reason: 'the header subtitle and the "Category:" row said the same '
            'word within four lines of each other',
      );
      expect(find.textContaining('GROCERIES'), findsOneWidget);
    });

    testWidgets('the kind is named once, on the eyebrow', (tester) async {
      tallPhone(tester);
      await pump(tester, _Fake(), entry());

      expect(
        mentions(tester, 'expense'),
        1,
        reason: 'an eyebrow reading EXPENSE over a row reading "Expense"',
      );
      expect(find.text('EXPENSE'), findsOneWidget);
    });

    testWidgets('and the Details list is gone entirely', (tester) async {
      tallPhone(tester);
      await pump(tester, _Fake(), entry());

      expect(find.text('DETAILS'), findsNothing);
      expect(find.text('Type'), findsNothing);
      expect(find.text('Category'), findsNothing);
      expect(find.text('Account'), findsNothing);
    });
  });

  group('whose money it was is asked in the direction the money went', () {
    testWidgets('money that left may have been lent, or held', (tester) async {
      phone(tester);
      await pump(tester, _Fake(), entry());
      await openWhoseMoney(tester);

      expect(find.text('I lent it out'), findsOneWidget);
      expect(find.text("I'm holding it for someone"), findsOneWidget);
      expect(
        find.text('I borrowed it'),
        findsNothing,
        reason: 'money leaving the account cannot be money somebody lent you',
      );
    });

    testWidgets('money that arrived may have been borrowed, or held', (
      tester,
    ) async {
      phone(tester);
      await pump(
        tester,
        _Fake(),
        entry(kind: TransactionKind.income, category: 'Income'),
      );
      await openWhoseMoney(tester);

      expect(find.text('I borrowed it'), findsOneWidget);
      expect(find.text("I'm holding it for someone"), findsOneWidget);
      expect(
        find.text('I lent it out'),
        findsNothing,
        reason:
            'this is the defect the disclosure exists to fix — three '
            'permanent buttons offered lending to money that arrived',
      );
    });

    testWidgets('and money moving between your own accounts is none of them', (
      tester,
    ) async {
      phone(tester);
      await pump(
        tester,
        _Fake(),
        entry(
          kind: TransactionKind.transfer,
          category: 'Between your accounts',
          balances: transferBalances,
        ),
      );

      expect(
        find.text('Whose money was this?'),
        findsNothing,
        reason: 'the question is not asked at all where no answer can be true',
      );
    });
  });

  testWidgets('a transfer between your own accounts is never a repayment', (
    tester,
  ) async {
    // Already the behaviour of the code, twice over: `debtMatchesFor`
    // returns nothing for a transfer, and `debtsOpenTo` — the hand picker,
    // which is otherwise deliberately permissive — returns nothing either.
    // There was no route to the mistake. The only thing missing was anybody
    // saying so, and an owner cannot tell a refusal from an oversight.
    phone(tester);
    final model = _Fake(debts: [loan()]);
    await pump(
      tester,
      model,
      entry(
        kind: TransactionKind.transfer,
        category: 'Between your accounts',
        balances: transferBalances,
      ),
    );

    expect(find.text('NO LOAN IS OFFERED HERE'), findsOneWidget);
    expect(
      find.textContaining('not somebody paying you back'),
      findsOneWidget,
    );
    expect(find.text('Record it against this loan'), findsNothing);
    expect(find.textContaining('money coming back on a loan'), findsNothing);
    expect(
      find.textContaining('Rameez Alvi is still open'),
      findsOneWidget,
      reason:
          'without naming the loan it did not touch, the owner has to take '
          'on faith that their own transfer did not quietly eat it',
    );
  });

  testWidgets('and it is silent about the refusal to somebody with no loans', (
    tester,
  ) async {
    // A refusal is the answer to a question, and an owner who has never
    // recorded a loan is not asking it. Saying "SpendWise will not suggest a
    // loan against this" to somebody who has none is the app explaining a
    // feature on a screen that is not about it.
    phone(tester);
    await pump(
      tester,
      _Fake(),
      entry(
        kind: TransactionKind.transfer,
        category: 'Between your accounts',
        balances: transferBalances,
      ),
    );

    expect(find.text('NO LOAN IS OFFERED HERE'), findsNothing);
  });

  group('it lays out on a 360dp phone', () {
    /// Scrolls the whole page past the viewport, because an overflow only
    /// happens where something is actually laid out.
    Future<void> readAll(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    testWidgets('with an eight-digit amount', (tester) async {
      phone(tester);
      await pump(
        tester,
        _Fake(),
        entry(
          minor: 1245000000,
          balances: const [
            AccountBalanceChange(
              accountId: 'acct-current',
              accountName: 'Corporate Current',
              beforeMinor: 3890214000,
              afterMinor: 2645214000,
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      // The figure steps down one size rather than wrapping: a wrapped
      // amount reads as two amounts.
      expect(find.text('−PKR 12,450,000'), findsOneWidget);
      await readAll(tester);
    });

    testWidgets('with a merchant name three lines long', (tester) async {
      phone(tester);
      await pump(
        tester,
        _Fake(),
        entry(
          title: 'Shahrah-e-Faisal Motorway Service Plaza and Filling '
              'Station (North Bound)',
        ),
      );
      expect(tester.takeException(), isNull);
      await readAll(tester);
    });

    testWidgets('with a transfer carrying two balance blocks', (tester) async {
      phone(tester);
      await pump(
        tester,
        _Fake(),
        entry(
          kind: TransactionKind.transfer,
          minor: 2500000,
          category: 'Between your accounts',
          balances: transferBalances,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Daily Current'), findsOneWidget);
      expect(find.text('Emergency Fund'), findsOneWidget);
      await readAll(tester);
    });
  });
}

/// Only what this screen reads. `noSuchMethod` covers the rest so growing the
/// view model does not break this file.
class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  _Fake({this.debts = const []});

  @override
  final List<DebtViewData> debts;

  /// The screen reads the entry back from here rather than trusting the
  /// snapshot it was handed. Empty is enough: it falls back to the entry
  /// under test, and nothing in this file settles anything.
  @override
  List<TransactionViewData> get transactions => const [];

  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'acct-current',
      name: 'Daily Current',
      type: 'bank',
      balance: MoneyViewData(3772500),
    ),
    AccountViewData(
      id: 'acct-fund',
      name: 'Emergency Fund',
      type: 'savings',
      balance: MoneyViewData(21140000),
    ),
  ];

  @override
  bool get busy => false;

  @override
  String? get errorMessage => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
