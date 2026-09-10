import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/debts/debt_sheets.dart' as debt_sheets;
import 'package:spendwise/features/shell/spendwise_view_model.dart';
import 'package:spendwise/features/transactions/transaction_details_screen.dart';

/// Opening a loan and closing one are opposite answers to the same question,
/// and only one of them was on the entry screen. Somebody whose loan came
/// back had no move except to record a *second* loan for the same money --
/// and the app's own help text told them to do the thing that did not exist.
///
/// These hold the missing half in place: the entry can reach the loan, the
/// entry id is what actually travels (the ledger excludes an entry from the
/// month by its `debtId`, and nothing else), and no suggestion ever settles
/// anything on its own.
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
    debtId: debtId,
  );

  void phoneSized(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpEntry(
    WidgetTester tester,
    _Fake model,
    TransactionViewData transaction,
  ) async {
    phoneSized(tester);
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

  testWidgets('a credit that fits an open loan is asked about', (tester) async {
    final repayment = entry();
    final model = _Fake(debts: [loan()], transactions: [repayment]);
    await pumpEntry(tester, model, repayment);

    expect(find.text('Is this Sana paying you back?'), findsOneWidget);
    // The reason is on screen, because a suggestion nobody can check is just
    // an assertion -- and this one takes money out of the month.
    expect(
      find.textContaining('the name matches and it is exactly what is still'),
      findsOneWidget,
    );
  });

  testWidgets('asking is not settling', (tester) async {
    final repayment = entry();
    final model = _Fake(debts: [loan()], transactions: [repayment]);
    await pumpEntry(tester, model, repayment);

    expect(
      model.settled,
      isEmpty,
      reason: 'a loan the owner believes is closed is money never chased',
    );
  });

  testWidgets('recording it sends the entry, not just an amount', (
    tester,
  ) async {
    // The crux of the whole fix. `settleDebt` always took a transaction id;
    // no screen ever passed one, so settling closed the loan and left the
    // same money counted as income.
    final repayment = entry();
    final model = _Fake(debts: [loan()], transactions: [repayment]);
    await pumpEntry(tester, model, repayment);

    await tester.tap(find.text('Record it against this loan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record it'));
    await tester.pumpAndSettle();

    expect(model.settled, hasLength(1));
    expect(model.settled.single.debtId, 'loan');
    expect(
      model.settled.single.transactionId,
      'back',
      reason: 'without this the month still counts it as income',
    );
    expect(model.settled.single.amountMinor, 5000000);
  });

  testWidgets('the entry screen shows the loan once it is attached', (
    tester,
  ) async {
    // The screen is handed a snapshot when it is pushed. Before it read the
    // entry back, recording a repayment left the offer on screen as though
    // nothing had happened.
    final repayment = entry();
    final model = _Fake(debts: [loan()], transactions: [repayment]);
    await pumpEntry(tester, model, repayment);

    await tester.tap(find.text('Record it against this loan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record it'));
    await tester.pumpAndSettle();

    expect(find.text('Is this Sana paying you back?'), findsNothing);
    expect(find.text('LENT OUT'), findsOneWidget);
  });

  testWidgets('an unrecognised credit can still reach a loan by hand', (
    tester,
  ) async {
    // The matcher was never going to catch this one: a stranger's narration
    // and an odd amount. The picker is the answer, and it has to be offered
    // without a suggestion to hang it on.
    final odd = entry(id: 'odd', title: 'IBFT INWARD 88213', amount: 700000);
    final model = _Fake(debts: [loan()], transactions: [odd]);
    await pumpEntry(tester, model, odd);

    expect(find.text('Is this Sana paying you back?'), findsNothing);
    // Below the fold on a phone, like the three stories above it.
    await tester.ensureVisible(
      find.text('This is money coming back on a loan'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('This is money coming back on a loan'));
    await tester.pumpAndSettle();

    expect(find.text('Money coming back'), findsOneWidget);
    expect(find.text('Sana'), findsOneWidget);
  });

  testWidgets('nothing is offered when no loan could take the money', (
    tester,
  ) async {
    // Money going out cannot be somebody repaying you, so an outgoing entry
    // with only a lent loan open gets the three stories and nothing else.
    final spend = entry(
      id: 'shop',
      title: 'MAIN ROAD STORE',
      amount: 240000,
      kind: TransactionKind.expense,
    );
    final model = _Fake(debts: [loan()], transactions: [spend]);
    await pumpEntry(tester, model, spend);

    expect(find.textContaining('money coming back on a loan'), findsNothing);
    expect(find.textContaining('money going back on a loan'), findsNothing);
    expect(find.text('I lent it out'), findsOneWidget);
  });

  testWidgets('an entry already on a loan is never asked about again', (
    tester,
  ) async {
    final attached = entry(debtId: 'loan');
    final model = _Fake(debts: [loan()], transactions: [attached]);
    await pumpEntry(tester, model, attached);

    expect(find.text('Is this Sana paying you back?'), findsNothing);
    expect(find.text('WHOSE MONEY WAS THIS?'), findsNothing);
    expect(find.text('LENT OUT'), findsOneWidget);
  });

  testWidgets('the loan itself offers the entry that looks like it', (
    tester,
  ) async {
    // The other end of the same question, and the more important one: this
    // is the screen where somebody would otherwise type the figure into the
    // box by hand and leave the money counted twice.
    phoneSized(tester);
    final repayment = entry();
    final model = _Fake(debts: [loan()], transactions: [repayment]);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => debt_sheets.openDebt(
                  context,
                  viewModel: model,
                  debt: loan(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('THIS ENTRY COULD BE IT'), findsOneWidget);
    expect(find.text('From Sana'), findsOneWidget);

    await tester.tap(find.text('From Sana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record it'));
    await tester.pumpAndSettle();

    expect(model.settled.single.transactionId, 'back');
  });

  testWidgets('the amount box is named for the case it is actually for', (
    tester,
  ) async {
    // It used to be the only way to settle anything, and it silently left
    // bank repayments counted as income. It is for cash, and now says so.
    phoneSized(tester);
    final model = _Fake(debts: [loan()], transactions: const []);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => debt_sheets.openDebt(
                  context,
                  viewModel: model,
                  debt: loan(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('RECORD MONEY COMING BACK IN CASH'), findsOneWidget);
    expect(
      find.textContaining('open that entry and record it against this loan'),
      findsOneWidget,
      reason: 'the advice now describes a door that exists',
    );
  });

  testWidgets('a loan settled by hand can still take the entry', (
    tester,
  ) async {
    // The trap. Typing the figure into a loan closes it, and every way of
    // attaching an entry looks for a loan with money still out -- so the
    // loan read settled, the repayment went on counting as income, and
    // nothing on any screen could reach either fact.
    phoneSized(tester);
    final repayment = entry();
    final handSettled = DebtViewData(
      id: 'loan',
      kind: DebtKind.lent,
      counterparty: 'Sana',
      principal: const MoneyViewData(5000000),
      settled: const MoneyViewData(5000000),
      settledByHand: const MoneyViewData(5000000),
      outstanding: const MoneyViewData(0),
      openedAt: opened,
      isSettled: true,
    );
    final model = _Fake(debts: [handSettled], transactions: [repayment]);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => debt_sheets.openDebt(
                  context,
                  viewModel: model,
                  debt: handSettled,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('WAS THIS THE MONEY?'), findsOneWidget);
    expect(
      find.textContaining('still counted as income'),
      findsOneWidget,
      reason: 'it has to say what is wrong, not just offer a button',
    );

    await tester.tap(find.text('From Sana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record it'));
    await tester.pumpAndSettle();

    expect(model.settled.single.transactionId, 'back');
    expect(
      model.settled.single.replacingByHand,
      isTrue,
      reason: 'otherwise the loan counts the same money twice over',
    );
  });

  testWidgets('a loan written off still offers the entry that repaid it', (
    tester,
  ) async {
    // "Call it settled" recorded nothing and touched no entry, so a
    // repayment that arrived in an account went on counting as income while
    // the loan claimed to be done -- and because the loan read settled,
    // nothing offered a way back. It is named for what it does now, and a
    // written-off loan still shows what looks like its money.
    phoneSized(tester);
    final repayment = entry();
    final writtenOff = DebtViewData(
      id: 'loan',
      kind: DebtKind.lent,
      counterparty: 'Sana',
      principal: const MoneyViewData(5000000),
      settled: const MoneyViewData(0),
      outstanding: const MoneyViewData(5000000),
      openedAt: opened,
      isSettled: true,
      closedAt: opened.add(const Duration(days: 20)),
    );
    final model = _Fake(debts: [writtenOff], transactions: [repayment]);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => debt_sheets.openDebt(
                  context,
                  viewModel: model,
                  debt: writtenOff,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Written off'),
      findsOneWidget,
      reason: 'calling it settled was the whole misunderstanding',
    );
    expect(find.text('THIS ENTRY COULD BE IT'), findsOneWidget);

    await tester.tap(find.text('From Sana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record it'));
    await tester.pumpAndSettle();

    expect(model.settled.single.transactionId, 'back');
    expect(
      model.settled.single.replacingByHand,
      isFalse,
      reason: 'nothing was recorded by hand, so there is nothing to replace',
    );
  });

  testWidgets('the write-off says it records nothing coming back', (
    tester,
  ) async {
    phoneSized(tester);
    final model = _Fake(debts: [loan()], transactions: const []);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => debt_sheets.openDebt(
                  context,
                  viewModel: model,
                  debt: loan(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Write it off'), findsOneWidget);
    expect(find.text('Call it settled'), findsNothing);
    expect(
      find.textContaining('without recording any money coming back'),
      findsOneWidget,
    );
  });
}

/// Only what these screens read. `noSuchMethod` covers the rest so growing
/// the view model does not break this file.
class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  _Fake({required List<DebtViewData> debts, required this.transactions})
    // ignore: prefer_initializing_formals
    : _debts = debts;

  final List<DebtViewData> _debts;
  final List<Settled> settled = [];

  @override
  List<TransactionViewData> transactions;

  @override
  List<DebtViewData> get debts => _debts;

  @override
  Future<void> settleDebt({
    required String debtId,
    required MoneyViewData amount,
    String? transactionId,
    bool replacingByHand = false,
  }) async {
    settled.add(
      Settled(
        debtId: debtId,
        transactionId: transactionId,
        amountMinor: amount.minorUnits,
        replacingByHand: replacingByHand,
      ),
    );
    // What the ledger does: the entry is stamped, which is what takes it out
    // of the month, and the loan comes down by that much.
    if (transactionId != null) {
      transactions = [
        for (final item in transactions)
          if (item.id == transactionId)
            TransactionViewData(
              id: item.id,
              title: item.title,
              subtitle: item.subtitle,
              amount: item.amount,
              kind: item.kind,
              occurredAt: item.occurredAt,
              category: 'Lent out',
              accountName: item.accountName,
              debtId: debtId,
            )
          else
            item,
      ];
    }
    notifyListeners();
  }

  @override
  bool get busy => false;

  @override
  String? get errorMessage => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Settled {
  const Settled({
    required this.debtId,
    required this.transactionId,
    required this.amountMinor,
    this.replacingByHand = false,
  });

  final String debtId;
  final String? transactionId;
  final int amountMinor;

  /// Whether this entry was offered as the correction of a figure somebody
  /// had already typed into the loan.
  final bool replacingByHand;
}
