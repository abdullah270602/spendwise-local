import 'package:flutter/material.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// One ledger's worth of invented money, shared by the light-mode tests.
///
/// Not a convenience. Two of those tests have to pump the same five screens —
/// one to check nothing overflows on paper, one to check the pickers write
/// what they say they write — and a fake copied into both is a fake that will
/// answer two different questions about the same month the first time somebody
/// edits one copy. The preferences are kept in a real in-memory ledger rather
/// than a map, so "this survives a restart" is a claim about the storage the
/// app actually uses.
///
/// Every name, balance and merchant below is invented.
class LightModeFixture extends ChangeNotifier
    implements SpendWiseAdvancedViewModel {
  LightModeFixture({LocalLedger? ledger})
    : ledger = ledger ?? LocalLedger.openInMemoryForTests();

  final LocalLedger ledger;

  @override
  bool get onboardingComplete => true;

  @override
  bool get notificationAccessGranted => true;

  @override
  bool get showSavingsOnHome => true;

  @override
  HomePeriod get homePeriod => HomePeriod.calendarMonth;

  @override
  DashboardViewData get dashboard => const DashboardViewData(
    netWorth: MoneyViewData(41250000),
    incomeThisMonth: MoneyViewData(41250000),
    spendingThisMonth: MoneyViewData(14356000),
    monthlyChangePercent: 18,
    categorySpending: [
      CategorySpendViewData(
        category: 'Groceries',
        amount: MoneyViewData(3842000),
        fraction: 0.27,
      ),
      CategorySpendViewData(
        category: 'Eating out',
        amount: MoneyViewData(2498000),
        fraction: 0.17,
      ),
      CategorySpendViewData(
        category: 'Transport',
        amount: MoneyViewData(2131000),
        fraction: 0.15,
      ),
    ],
  );

  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'bank',
      name: 'Daily Current',
      type: 'Bank',
      balance: MoneyViewData(26894000),
      suffix: '4417',
    ),
    AccountViewData(
      id: 'cash',
      name: 'Cash in hand',
      type: 'Cash',
      balance: MoneyViewData(1180000),
    ),
    AccountViewData(
      id: 'fund',
      name: 'Emergency Fund',
      type: 'Savings',
      balance: MoneyViewData(9500000),
      isIncluded: false,
    ),
  ];

  static final _day = DateTime(2026, 9, 10, 18, 42);

  @override
  List<TransactionViewData> get transactions => [
    TransactionViewData(
      id: 'salary',
      title: 'Invoice settled',
      subtitle: 'Daily Current',
      amount: const MoneyViewData(41250000),
      kind: TransactionKind.income,
      occurredAt: _day.subtract(const Duration(days: 1)),
      category: 'Salary',
      accountId: 'bank',
    ),
    TransactionViewData(
      id: 'groceries',
      title: 'Chenab Grocers',
      subtitle: 'Daily Current',
      amount: const MoneyViewData(-3842000),
      kind: TransactionKind.expense,
      occurredAt: _day,
      category: 'Groceries',
      accountId: 'bank',
    ),
    TransactionViewData(
      id: 'eating-out',
      title: 'Orchard Cafe',
      subtitle: 'Cash in hand',
      amount: const MoneyViewData(-2498000),
      kind: TransactionKind.expense,
      occurredAt: _day,
      category: 'Eating out',
      accountId: 'cash',
    ),
    TransactionViewData(
      id: 'transport',
      title: 'Riverline Fuel',
      subtitle: 'Daily Current',
      amount: const MoneyViewData(-2131000),
      kind: TransactionKind.expense,
      occurredAt: _day,
      category: 'Transport',
      accountId: 'bank',
    ),
    TransactionViewData(
      id: 'put-away',
      title: 'Moved into savings',
      subtitle: 'Own accounts',
      amount: const MoneyViewData(2500000),
      kind: TransactionKind.transfer,
      occurredAt: _day.subtract(const Duration(days: 1)),
      category: 'Savings',
      accountId: 'bank',
      toAccountId: 'fund',
    ),
  ];

  /// The entry a detail screen is opened on.
  TransactionViewData get anEntry => transactions[1];

  @override
  List<CategoryViewData> get categories => const [
    CategoryViewData(id: 'c1', name: 'Groceries', kind: 'expense'),
    CategoryViewData(id: 'c2', name: 'Eating out', kind: 'expense'),
    CategoryViewData(id: 'c3', name: 'Transport', kind: 'expense'),
    CategoryViewData(id: 'c4', name: 'Salary', kind: 'income'),
  ];

  @override
  List<DebtViewData> get debts => const [];

  @override
  List<ReviewViewData> get reviews => const [];

  @override
  List<AlertViewData> get unroutedAlerts => const [];

  @override
  List<AlertViewData> alerts({
    String? packageName,
    bool onlyUnresolved = true,
  }) => const [];

  @override
  List<AlertViewData> skippedAlerts({String? packageName}) => const [];

  @override
  List<SourceViewData> get sources => const [
    SourceViewData(
      packageName: 'com.example.dailycurrent',
      label: 'Daily Current app',
      enabled: true,
    ),
  ];

  @override
  bool isSharedSource(String packageName) => false;

  @override
  List<CategorySpendViewData> categorySpendingIn({
    required DateTime from,
    required DateTime to,
  }) => dashboard.categorySpending;

  @override
  bool get busy => false;

  @override
  bool get demoDataEnabled => false;

  @override
  String? get errorMessage => null;

  @override
  List<String> get ownNames => const ['Sample Owner'];

  @override
  DeletedAccountViewData? get lastDeletedAccount => null;

  @override
  Map<String, String> unresolvedAlertStatuses(String? packageName) => const {};

  @override
  String? viewPreference(String key) => ledger.viewPreference(key);

  @override
  void setViewPreference(String key, String value) {
    ledger.setViewPreference(key, value);
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
