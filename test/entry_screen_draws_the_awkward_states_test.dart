import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';
import 'package:spendwise/features/transactions/transaction_details_screen.dart';

/// The entry screen has one layout and six or seven states, and a layout is
/// only worth anything if it survives all of them.
///
/// Each of these is a shape the app already produces and the old screen drew
/// as an ordinary entry, saying nothing about what made it different. A
/// withdrawal read as twenty thousand spent when the money is in a pocket. An
/// entry posted below the app's own 80% confidence threshold looked exactly
/// as certain as one at 98%. A charge in a currency the account does not keep
/// moved the balance by a figure that is not what it cost. Two apps reporting
/// one tap looked like two alerts with no word saying it was counted once,
/// which is the fear that opens this screen. And a 75-paisa fee broke the one
/// column on the page whose job is to be checkable by eye.
///
/// Every merchant, account and figure below is invented.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TransactionViewData entry({
    String title = 'Meridian Foodhall',
    TransactionKind kind = TransactionKind.expense,
    MoneyViewData amount = const MoneyViewData(-426500),
    String category = 'Groceries',
    String? toAccountId,
    bool isReviewed = true,
    bool isLocked = false,
    List<EvidenceViewData> evidence = const [],
    int? evidenceCount,
    List<AccountBalanceChange> balances = const [
      AccountBalanceChange(
        accountId: 'acct-current',
        accountName: 'Daily Current',
        beforeMinor: 4619000,
        afterMinor: 4192500,
      ),
    ],
  }) => TransactionViewData(
    id: 'tx-1',
    title: title,
    subtitle: 'Daily Current',
    amount: amount,
    kind: kind,
    occurredAt: DateTime(2026, 9, 9, 18, 42),
    category: category,
    accountName: 'Daily Current',
    accountId: 'acct-current',
    toAccountId: toAccountId,
    isReviewed: isReviewed,
    isLocked: isLocked,
    evidence: evidence,
    evidenceCount: evidenceCount ?? evidence.length,
    balances: balances,
  );

  EvidenceViewData alert({
    required String id,
    required String source,
    required String body,
    EvidenceState state = EvidenceState.accepted,
    double confidence = .96,
  }) => EvidenceViewData(
    id: id,
    sourceLabel: source,
    packageName: 'com.example.$id',
    observedAt: DateTime(2026, 9, 9, 18, 42),
    state: state,
    title: source,
    body: body,
    parserId: 'pk.generic.v1',
    confidence: confidence,
  );

  Future<void> pump(
    WidgetTester tester,
    TransactionViewData transaction,
  ) async {
    // Tall on purpose: these assert what the page says, not what fits on it.
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: TransactionDetailsScreen(
          viewModel: _Fake(),
          transaction: transaction,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a cash withdrawal is money changing pocket, not money spent', (
    tester,
  ) async {
    // A withdrawal is the one transfer the app asserts from a single alert,
    // and the owner's instinct is to read it as spending. Nothing on the old
    // screen said otherwise.
    await pump(
      tester,
      entry(
        title: 'Cash withdrawn',
        kind: TransactionKind.transfer,
        amount: const MoneyViewData(2000000),
        category: 'Between your accounts',
        toAccountId: 'acct-cash',
        balances: const [
          AccountBalanceChange(
            accountId: 'acct-current',
            accountName: 'Daily Current',
            beforeMinor: 4192500,
            afterMinor: 2192500,
          ),
          AccountBalanceChange(
            accountId: 'acct-cash',
            accountName: 'Cash',
            beforeMinor: 310000,
            afterMinor: 2310000,
          ),
        ],
      ),
    );

    expect(find.text('CASH'), findsOneWidget);
    expect(find.text('Not spending. Not yet.'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget, reason: 'the pocket it went to');
    expect(
      find.text('Whose money was this?'),
      findsNothing,
      reason: 'a withdrawal is a transfer, and a transfer is nobody else\'s',
    );
  });

  testWidgets('an entry posted below the confidence threshold says so', (
    tester,
  ) async {
    // 0.8 is the reconciler's own line: below it an entry is posted and
    // marked rather than trusted. The screen drew it at full confidence.
    await pump(
      tester,
      entry(
        title: 'AL-NOOR TRD 8841',
        isReviewed: false,
        evidence: [
          alert(
            id: 'ev-1',
            source: 'Meridian Bank',
            body: 'Debit PKR 1,150 a/c 7104 AL-NOOR TRD 8841 09/09 18:42',
            confidence: .62,
          ),
        ],
      ),
    );

    expect(find.text('Posted, but only 62% sure'), findsOneWidget);
    expect(
      find.textContaining('counted in the month'),
      findsOneWidget,
      reason: 'flagged is not the same as missing: the entry is in the ledger',
    );
  });

  testWidgets('a charge in a currency the account does not keep is named', (
    tester,
  ) async {
    // SpendWise does not convert currencies and will not guess a rate. The
    // balance still moves by the figure as it was read, which is the one sum
    // on this page the owner cannot check — so it is said out loud rather
    // than performed quietly.
    await pump(
      tester,
      entry(
        title: 'Northwind Cloud Storage',
        amount: const MoneyViewData(-4200, currency: 'USD'),
        category: 'Subscriptions',
      ),
    );

    expect(
      find.text('Charged in USD. The account keeps PKR.'),
      findsOneWidget,
    );
    expect(find.textContaining('will not guess a rate'), findsOneWidget);
    expect(
      find.text('−USD 42'),
      findsOneWidget,
      reason: 'the code travels with the figure, never appended to it',
    );
  });

  testWidgets('two alerts for one movement say it is counted once', (
    tester,
  ) async {
    await pump(
      tester,
      entry(
        title: 'Bunyad Coffee House',
        amount: const MoneyViewData(-178000),
        evidence: [
          alert(
            id: 'ev-1',
            source: 'Meridian Bank',
            body: 'Card ending 7104 debited PKR 1,780.00 at BUNYAD COFFEE',
            confidence: .94,
          ),
          alert(
            id: 'ev-2',
            source: 'PocketPay wallet',
            body: 'Tap approved — PKR 1,780 at Bunyad Coffee House.',
            state: EvidenceState.duplicate,
            confidence: .91,
          ),
        ],
      ),
    );

    expect(find.textContaining('2 ALERTS'), findsOneWidget);
    await tester.tap(find.text('Where this came from'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('It is counted once'),
      findsOneWidget,
      reason: 'said before either alert is shown, because that is the fear',
    );
    expect(find.textContaining('COUNTED'), findsWidgets);
    expect(
      find.textContaining('SAME PAYMENT'),
      findsOneWidget,
      reason: '"duplicate" reads like an error the owner should go and fix',
    );
    expect(find.text('Meridian Bank'), findsWidgets);
    expect(find.text('PocketPay wallet'), findsOneWidget);
  });

  testWidgets('an answered entry promises the next sync will not undo it', (
    tester,
  ) async {
    await pump(
      tester,
      entry(
        isLocked: true,
        evidence: [
          alert(
            id: 'ev-1',
            source: 'Meridian Bank',
            body: 'Payment of PKR 4,265 to MERIDIAN FOODHALL was successful.',
            confidence: .71,
          ),
        ],
      ),
    );

    expect(find.text('Your answer stands'), findsOneWidget);
    expect(find.textContaining('ANSWERED BY YOU'), findsOneWidget);
    expect(
      find.textContaining('71%'),
      findsOneWidget,
      reason:
          'the reading is left visible: it is what explains why the '
          'correction was needed, and deleting it would make the audit trail '
          'less complete than the thing it audits',
    );
  });

  testWidgets('paisa are contagious inside a balance block', (tester) async {
    // The moment one figure in the block needs decimals, all three show
    // them, or the column of tabular digits stops lining up and the
    // subtraction stops being checkable by eye — which is its only job.
    await pump(
      tester,
      entry(
        title: 'Meridian Bank',
        amount: const MoneyViewData(-75),
        category: 'Fees',
        balances: const [
          AccountBalanceChange(
            accountId: 'acct-current',
            accountName: 'Daily Current',
            beforeMinor: 2192500,
            afterMinor: 2192425,
          ),
        ],
      ),
    );

    expect(find.text('21,925.00'), findsOneWidget, reason: 'before');
    expect(find.text('− 0.75'), findsOneWidget, reason: 'what moved');
    expect(find.text('21,924.25'), findsOneWidget, reason: 'after');
    expect(
      find.text('21,925'),
      findsNothing,
      reason: 'a whole figure beside a fractional one breaks the column',
    );
  });
}

/// Only what this screen reads. `noSuchMethod` covers the rest so growing the
/// view model does not break this file.
class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  @override
  List<DebtViewData> get debts => const [];

  @override
  List<TransactionViewData> get transactions => const [];

  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'acct-current',
      name: 'Daily Current',
      type: 'bank',
      balance: MoneyViewData(4192500),
    ),
    AccountViewData(
      id: 'acct-cash',
      name: 'Cash',
      type: 'cash',
      balance: MoneyViewData(2310000),
    ),
  ];

  @override
  bool get busy => false;

  @override
  String? get errorMessage => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
