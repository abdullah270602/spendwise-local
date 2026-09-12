import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/palette.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/transactions/transaction_details_screen.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// Three of the defects fixed on this screen: the entry it was made from
/// mislabelled a held debt as a borrowing, the third story was reachable
/// only by picking one of the other two first, and deleting here dropped a
/// transaction with no way back even though the same delete offers an Undo
/// everywhere else in the app.
void main() {
  TransactionViewData transaction({
    String id = 'tx-1',
    TransactionKind kind = TransactionKind.income,
    String? debtId,
  }) => TransactionViewData(
    id: id,
    title: 'From Hamza',
    subtitle: 'NayaPay',
    amount: const MoneyViewData(1680000),
    kind: kind,
    occurredAt: DateTime.utc(2026, 9, 2, 12),
    category: 'Held for someone',
    accountName: 'NayaPay',
    debtId: debtId,
  );

  DebtViewData debt(DebtKind kind) => DebtViewData(
    id: 'debt-1',
    kind: kind,
    counterparty: 'Hamza',
    principal: const MoneyViewData(1680000),
    settled: const MoneyViewData(0),
    outstanding: const MoneyViewData(1680000),
    openedAt: DateTime.utc(2026, 9, 2),
    isSettled: false,
  );

  Widget host(_FakeViewModel model, TransactionViewData tx) => MaterialApp(
    theme: SpendWiseTheme.dark,
    home: TransactionDetailsScreen(viewModel: model, transaction: tx),
  );

  // The delete flow pops this screen back to whatever pushed it, so the test
  // needs a real screen underneath rather than the bare `home` the other
  // tests use -- pop-ing the only route in a Navigator stack is a no-op that
  // used to leave the confirmation dialog quietly refusing to complete.
  Future<void> pushDetails(
    WidgetTester tester,
    _FakeViewModel model,
    TransactionViewData tx,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: const Scaffold(body: Center(child: Text('Register'))),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TransactionDetailsScreen(viewModel: model, transaction: tx),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a held debt is labelled by what it is, not by Borrowed', (
    tester,
  ) async {
    final model = _FakeViewModel(debts: [debt(DebtKind.holding)]);
    await tester.pumpWidget(
      host(model, transaction(debtId: 'debt-1', kind: TransactionKind.income)),
    );
    await tester.pumpAndSettle();

    expect(find.text('HELD FOR SOMEONE'), findsOneWidget);
    expect(
      find.text('BORROWED'),
      findsNothing,
      reason: 'holding is not a species of borrowing on this screen either',
    );
  });

  testWidgets('a real borrowing still reads Borrowed', (tester) async {
    final model = _FakeViewModel(debts: [debt(DebtKind.borrowed)]);
    await tester.pumpWidget(
      host(model, transaction(debtId: 'debt-1', kind: TransactionKind.income)),
    );
    await tester.pumpAndSettle();

    expect(find.text('BORROWED'), findsOneWidget);
  });

  testWidgets(
    'the third story is offered up front, not only after a wrong guess',
    (tester) async {
      final model = _FakeViewModel(debts: const []);
      await tester.pumpWidget(host(model, transaction()));
      await tester.pumpAndSettle();

      // All three, visible without tapping anything first.
      expect(find.text('I lent it out'), findsOneWidget);
      expect(find.text('I borrowed it'), findsOneWidget);
      expect(find.text("I'm holding it for someone"), findsOneWidget);
    },
  );

  testWidgets('picking the third option opens the holding story directly', (
    tester,
  ) async {
    final model = _FakeViewModel(debts: const []);
    await tester.pumpWidget(host(model, transaction()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text("I'm holding it for someone"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I'm holding it for someone"));
    await tester.pumpAndSettle();

    // The sheet's own holding-specific copy, reached without first landing
    // on "I borrowed it" and correcting it from inside the sheet.
    expect(
      find.text('It is not yours, so it stays out of what you can spend.'),
      findsOneWidget,
    );
  });

  testWidgets('a transfer is the same colour here as it is in the register', (
    tester,
  ) async {
    // This screen reached for `SpendWiseColors.warning`, a hardcoded amber
    // that `SpendWiseColors.apply` never touches. The Ledger paints a
    // transfer `mine` -- the palette's own answer to "this only moved between
    // accounts you already own" -- so one entry was two colours depending on
    // whether you had tapped it, and stayed amber through every palette the
    // owner chose.
    SpendWiseColors.apply(SpendWisePalette.byId('brass'));
    addTearDown(() => SpendWiseColors.apply(SpendWisePalette.sage));

    final model = _FakeViewModel(debts: const []);
    await tester.pumpWidget(
      host(model, transaction(kind: TransactionKind.transfer)),
    );
    await tester.pumpAndSettle();

    final amount = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) => widget is Text && (widget.data ?? '').contains('16,800'),
      ),
    );
    expect(amount.style?.color, SpendWiseColors.mine);
    expect(amount.style?.color, isNot(SpendWiseColors.warning));
  });

  testWidgets('deleting offers a working Undo', (tester) async {
    final model = _FakeViewModel(debts: const []);
    await pushDetails(tester, model, transaction(id: 'tx-9'));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    // Selecting the menu item opens a confirmation dialog first -- the
    // dialog's own "Delete transaction" button is a second, later widget
    // with the same label, not the menu item itself.
    await tester.tap(find.text('Delete transaction'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete transaction'));
    await tester.pumpAndSettle();

    expect(model.deleted, contains('tx-9'));
    expect(find.text('Transaction deleted'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(
      model.deleted,
      isNot(contains('tx-9')),
      reason: 'Undo calls the same restoreTransaction the rest of the app uses',
    );
  });

  testWidgets('the screen lays out at 360px with evidence expanded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final model = _FakeViewModel(debts: const []);
    final tx = TransactionViewData(
      id: 'tx-2',
      title: 'A fairly long merchant name that could wrap awkwardly',
      subtitle: 'Meezan Bank · Debit card',
      amount: const MoneyViewData(455000),
      kind: TransactionKind.expense,
      occurredAt: DateTime.utc(2026, 9, 2, 12),
      category: 'Groceries',
      accountName: 'Meezan Bank',
      note: 'Weekly shop',
      evidence: [
        EvidenceViewData(
          id: 'ev-1',
          sourceLabel: 'Meezan Bank notification',
          observedAt: DateTime.utc(2026, 9, 2, 12),
          state: EvidenceState.accepted,
          title: 'Debit alert',
          body: 'Rs 4,550.00 debited from your account.',
          reasons: const ['amount_matched', 'account_matched'],
        ),
      ],
    );
    await tester.pumpWidget(host(model, tx));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Opening the one piece of evidence is the widest this screen gets.
    // Scrolled to rather than found outright: a plain ListView still only
    // mounts the sliver children near the viewport, so the evidence card
    // below the fold does not exist in the tree until something scrolls it
    // into range.
    await tester.dragUntilVisible(
      find.text('Meezan Bank notification'),
      find.byType(Scrollable),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meezan Bank notification'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Title and body of the raw evidence share one Text node, so this
    // opened the tile rather than merely finding a header still collapsed.
    expect(find.textContaining('Debit alert'), findsOneWidget);
  });
}

/// Only the members this screen and the debt sheets it opens actually read
/// are implemented; `noSuchMethod` covers the rest so growing the view model
/// does not break this test.
class _FakeViewModel extends ChangeNotifier
    implements SpendWiseAdvancedViewModel {
  // ignore: prefer_initializing_formals
  _FakeViewModel({required List<DebtViewData> debts}) : _debts = debts;

  final List<DebtViewData> _debts;
  final Set<String> deleted = {};

  @override
  List<DebtViewData> get debts => _debts;

  @override
  Future<void> deleteTransaction(String id) async {
    deleted.add(id);
    notifyListeners();
  }

  @override
  Future<void> restoreTransaction(String id) async {
    deleted.remove(id);
    notifyListeners();
  }

  @override
  Future<void> openDebt({
    required String transactionId,
    required DebtKind kind,
    required String counterparty,
    String? note,
  }) async {
    _debts.add(
      DebtViewData(
        id: 'new-${_debts.length}',
        kind: kind,
        counterparty: counterparty,
        principal: const MoneyViewData(0),
        settled: const MoneyViewData(0),
        outstanding: const MoneyViewData(0),
        openedAt: DateTime.utc(2026, 9, 2),
        isSettled: false,
        note: note,
      ),
    );
    notifyListeners();
  }

  @override
  List<AccountViewData> get accounts => const [];

  @override
  List<CategoryViewData> get categories => const [];

  @override
  bool get busy => false;

  @override
  String? get errorMessage => null;

  /// The loan section reads the entry back from here rather than trusting
  /// the snapshot it was handed, so that recording a repayment updates the
  /// screen. Empty is enough: it falls back to the entry under test.
  @override
  List<TransactionViewData> get transactions => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
