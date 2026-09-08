import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/debts/debt_sheets.dart' as debt_sheets;
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// "Not a loan" used to go straight to `uiRemoveDebt` on a single tap: no
/// question first, even though it throws away the counterparty, the note and
/// every repayment recorded against the debt, and moves a figure on Home
/// with nothing to undo it. This holds it to asking before it does that.
void main() {
  DebtViewData debt({DebtKind kind = DebtKind.lent, bool isSettled = false}) =>
      DebtViewData(
        id: 'debt-1',
        kind: kind,
        counterparty: 'Bilal',
        principal: const MoneyViewData(500000),
        settled: const MoneyViewData(0),
        outstanding: const MoneyViewData(500000),
        openedAt: DateTime.utc(2026, 8, 1),
        isSettled: isSettled,
      );

  Widget host(_FakeViewModel model, DebtViewData initial) => MaterialApp(
    theme: SpendWiseTheme.dark,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () =>
                debt_sheets.openDebt(context, viewModel: model, debt: initial),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  // A modal sheet sized to its content can run taller than the 800x600 test
  // default holds, cutting "Not a loan" off below the fake window rather
  // than leaving it reachable by scrolling within the sheet -- a real phone
  // is short too, so every test here runs at that size rather than one the
  // sheet is never actually shown at.
  void phoneSized(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('tapping Not a loan asks before it forgets anything', (
    tester,
  ) async {
    phoneSized(tester);
    final model = _FakeViewModel(debts: [debt()]);
    await tester.pumpWidget(host(model, debt()));
    await openSheet(tester);

    await tester.ensureVisible(find.text('Not a loan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not a loan'));
    await tester.pumpAndSettle();

    expect(model.removed, isEmpty, reason: 'a question is not yet a decision');
    expect(find.text('This was never a loan?'), findsOneWidget);
  });

  testWidgets('cancelling the question leaves the debt exactly as it was', (
    tester,
  ) async {
    phoneSized(tester);
    final model = _FakeViewModel(debts: [debt()]);
    await tester.pumpWidget(host(model, debt()));
    await openSheet(tester);

    await tester.ensureVisible(find.text('Not a loan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not a loan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(model.removed, isEmpty);
    // The sheet is still open on the same debt, not dismissed by the way
    // out of the question.
    expect(find.text('Bilal'), findsOneWidget);
  });

  testWidgets('confirming forgets the debt', (tester) async {
    phoneSized(tester);
    final model = _FakeViewModel(debts: [debt()]);
    await tester.pumpWidget(host(model, debt()));
    await openSheet(tester);

    await tester.ensureVisible(find.text('Not a loan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not a loan'));
    await tester.pumpAndSettle();
    // Two widgets now read "Not a loan": the button that asked the question
    // and the dialog's own destructive confirm action.
    await tester.tap(find.text('Not a loan').last);
    await tester.pumpAndSettle();

    expect(model.removed, contains('debt-1'));
  });

  testWidgets('the sheet lays out at 360px', (tester) async {
    phoneSized(tester);

    final model = _FakeViewModel(debts: [debt(kind: DebtKind.holding)]);
    await tester.pumpWidget(host(model, debt(kind: DebtKind.holding)));
    await openSheet(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Not a loan'), findsOneWidget);
  });
}

/// Only the members the debt sheets actually read are implemented;
/// `noSuchMethod` covers the rest so growing the view model does not break
/// this test.
class _FakeViewModel extends ChangeNotifier
    implements SpendWiseAdvancedViewModel {
  // ignore: prefer_initializing_formals
  _FakeViewModel({required List<DebtViewData> debts}) : _debts = debts;

  final List<DebtViewData> _debts;
  final Set<String> removed = {};

  @override
  List<DebtViewData> get debts => _debts;

  @override
  Future<void> removeDebt(String id) async {
    removed.add(id);
    _debts.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  @override
  Future<void> closeDebt(String id) async {
    notifyListeners();
  }

  @override
  Future<void> changeDebtKind({
    required String debtId,
    required DebtKind kind,
  }) async {
    notifyListeners();
  }

  @override
  Future<void> settleDebt({
    required String debtId,
    required MoneyViewData amount,
    String? transactionId,
  }) async {
    notifyListeners();
  }

  @override
  bool get busy => false;

  @override
  String? get errorMessage => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
