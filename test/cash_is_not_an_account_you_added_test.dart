import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/accounts/accounts_screen.dart';
import 'package:spendwise/features/review/review_rules.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// The cash pocket is made by the app the moment setup finishes, and it is a
/// real row in the accounts table. So every question of the shape "has this
/// person added an account yet" answers yes from that moment on, forever --
/// and the two screens that ask it are the two that tell a newcomer what to
/// do next.
///
/// Worse, cash is the one account no bank alert can belong to: routing
/// excludes it on purpose, because banknotes send no notifications. Offering
/// it as somewhere to file stuck alerts files a bank's money into a pocket.
void main() {
  const cash = AccountViewData(
    id: 'cash',
    name: 'Cash',
    type: 'cash',
    balance: MoneyViewData(0),
  );
  const bank = AccountViewData(
    id: 'bank',
    name: 'Everyday',
    type: 'bank',
    balance: MoneyViewData(2500000),
    suffix: '1234',
  );

  test('cash knows it is not an account anybody added', () {
    expect(cash.isCash, isTrue);
    expect(bank.isCash, isFalse);
  });

  testWidgets('Accounts still asks for a first account when only cash exists', (
    tester,
  ) async {
    // Someone finished setup without adding a bank. Before this, the cash
    // pocket answered "you have accounts" and the one screen that would have
    // told them what to do showed a balance list of one empty pocket.
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Scaffold(body: AccountsScreen(viewModel: _Fake([cash]))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No accounts yet.'), findsOneWidget);
    expect(find.text('Add your first account'), findsOneWidget);
  });

  testWidgets('and stops asking once a real account is there', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Scaffold(body: AccountsScreen(viewModel: _Fake([cash, bank]))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No accounts yet.'), findsNothing);
    expect(find.text('Everyday'), findsWidgets);
  });

  test('Review does not claim an account is set up when only cash is', () {
    // The rule that asks where unrouted alerts belong. With only cash
    // present it used to say "No account matched" as though the owner had a
    // bank to choose, and offer them one row: their own pocket.
    final rules = buildReviewRules(
      transactions: [
        TransactionViewData(
          id: 'stuck',
          title: 'PKR 2,400 debited',
          subtitle: '',
          amount: const MoneyViewData(240000),
          kind: TransactionKind.expense,
          occurredAt: DateTime(2026, 9, 20),
          category: 'Uncategorised',
          isReviewed: false,
        ),
      ],
      reviews: const [],
      accounts: const [cash],
    );

    final rule = rules.firstWhere((item) => item.id == 'route');
    expect(
      rule.claim,
      contains('You have not set one up yet'),
      reason: 'a pocket the app made is not an account they chose',
    );
    expect(
      rule.alternative,
      isNull,
      reason: 'there is nothing to handle them one by one into',
    );
  });

  test('and does claim one once a real account exists', () {
    final rules = buildReviewRules(
      transactions: [
        TransactionViewData(
          id: 'stuck',
          title: 'PKR 2,400 debited',
          subtitle: '',
          amount: const MoneyViewData(240000),
          kind: TransactionKind.expense,
          occurredAt: DateTime(2026, 9, 20),
          category: 'Uncategorised',
          isReviewed: false,
        ),
      ],
      reviews: const [],
      accounts: const [cash, bank],
    );

    final rule = rules.firstWhere((item) => item.id == 'route');
    expect(rule.claim, contains('Nothing here has reached a balance'));
    expect(rule.alternative, 'Handle them one by one');
  });
}

class _Fake extends ChangeNotifier implements SpendWiseViewModel {
  _Fake(this.accounts);

  @override
  final List<AccountViewData> accounts;

  @override
  List<TransactionViewData> get transactions => const [];

  @override
  List<ReviewViewData> get reviews => const [];

  @override
  List<SourceViewData> get sources => const [];

  @override
  bool get onboardingComplete => true;

  @override
  bool get notificationAccessGranted => true;

  @override
  DashboardViewData get dashboard => const DashboardViewData(
    netWorth: MoneyViewData(0),
    incomeThisMonth: MoneyViewData(0),
    spendingThisMonth: MoneyViewData(0),
    monthlyChangePercent: 0,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
