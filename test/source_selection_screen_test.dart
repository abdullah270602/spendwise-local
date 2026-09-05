import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/settings/source_selection_screen.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

void main() {
  testWidgets('searches apps and persists a toggle with immediate feedback', (
    tester,
  ) async {
    final model = _SourceModel();
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: SourceSelectionScreen(viewModel: model),
      ),
    );

    expect(find.text('Meezan Mobile'), findsOneWidget);
    expect(find.text('Google Messages'), findsOneWidget);
    await tester.enterText(find.byType(SearchBar), 'meezan');
    await tester.pump();
    expect(find.text('Meezan Mobile'), findsOneWidget);
    expect(find.text('Google Messages'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(model.lastPackage, 'pk.com.meezanbank');
    expect(model.sources.first.enabled, isTrue);
  });
}

class _SourceModel extends ChangeNotifier implements SpendWiseViewModel {
  String? lastPackage;
  final _sources = <SourceViewData>[
    const SourceViewData(
      packageName: 'pk.com.meezanbank',
      label: 'Meezan Mobile',
      enabled: false,
    ),
    const SourceViewData(
      packageName: 'com.google.android.apps.messaging',
      label: 'Google Messages',
      enabled: false,
    ),
  ];

  @override
  List<SourceViewData> get sources => List.unmodifiable(_sources);

  @override
  Future<void> setSourceEnabled(String packageName, bool enabled) async {
    lastPackage = packageName;
    final index = _sources.indexWhere(
      (source) => source.packageName == packageName,
    );
    final source = _sources[index];
    _sources[index] = SourceViewData(
      packageName: source.packageName,
      label: source.label,
      enabled: enabled,
    );
    notifyListeners();
  }

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
  List<AccountViewData> get accounts => const [];
  @override
  List<TransactionViewData> get transactions => const [];
  @override
  List<ReviewViewData> get reviews => const [];
  @override
  Future<void> addAccount(
    String name,
    String type,
    MoneyViewData openingBalance,
  ) async {}
  @override
  Future<void> completeOnboarding() async {}
  @override
  Future<void> deleteTransaction(String id) async {}
  @override
  Future<void> restoreTransaction(String id) async {}
  @override
  Future<void> eraseAllData() async {}
  @override
  Future<void> exportData() async {}
  @override
  Future<void> requestNotificationAccess() async {}
  @override
  Future<void> resolveReview(String id, {required bool merge}) async {}
  @override
  Future<void> saveManualTransaction(ManualTransactionDraft draft) async {}
}
