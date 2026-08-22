import 'package:flutter/foundation.dart';

enum TransactionKind { expense, income, transfer }

enum ReviewReason {
  possibleDuplicate,
  possibleTransfer,
  needsCategory,
  lowConfidence,
  parseFailed,
}

enum SourceHealth { healthy, idle, stale, permissionRequired, error }

enum EvidenceState { accepted, duplicate, matched, unparsed, ignored }

enum ExportFormat { csv, json }

final class ExportCancelledException implements Exception {
  const ExportCancelledException();
}

enum ImportField {
  date,
  description,
  amount,
  debit,
  credit,
  direction,
  balance,
  merchant,
  currency,
  reference,
  ignore,
}

@immutable
class MoneyViewData {
  const MoneyViewData(this.minorUnits, {this.currency = 'PKR'});
  final int minorUnits;
  final String currency;
  double get majorUnits => minorUnits / 100;
}

@immutable
class TransactionViewData {
  const TransactionViewData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.kind,
    required this.occurredAt,
    required this.category,
    this.accountName = '',
    this.note = '',
    this.evidenceCount = 1,
    this.isReviewed = true,
    this.accountId,
    this.toAccountId,
    this.evidence = const [],
  });
  final String id;
  final String title;
  final String subtitle;
  final MoneyViewData amount;
  final TransactionKind kind;
  final DateTime occurredAt;
  final String category;
  final String accountName;
  final String note;
  final int evidenceCount;
  final bool isReviewed;
  final String? accountId;
  final String? toAccountId;
  final List<EvidenceViewData> evidence;
}

@immutable
class EvidenceViewData {
  const EvidenceViewData({
    required this.id,
    required this.sourceLabel,
    required this.observedAt,
    required this.state,
    this.packageName = '',
    this.title = '',
    this.body = '',
    this.parserId = 'deterministic',
    this.ruleId = '',
    this.confidence = 1,
    this.reasons = const [],
  });
  final String id;
  final String sourceLabel;
  final String packageName;
  final DateTime observedAt;
  final EvidenceState state;
  final String title;
  final String body;
  final String parserId;
  final String ruleId;
  final double confidence;
  final List<String> reasons;
}

@immutable
class AccountSourceViewData {
  const AccountSourceViewData({
    required this.id,
    required this.label,
    this.packageName = '',
    this.kind = 'app',
  });
  final String id;
  final String label;
  final String packageName;
  final String kind;
}

@immutable
class AccountViewData {
  const AccountViewData({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    this.isIncluded = true,
    this.suffix = '',
    this.currency = 'PKR',
    this.institution = '',
    this.sources = const [],
  });
  final String id;
  final String name;
  final String type;
  final MoneyViewData balance;
  final bool isIncluded;
  final String suffix;
  final String currency;
  final String institution;
  final List<AccountSourceViewData> sources;
}

@immutable
class SourceViewData {
  const SourceViewData({
    required this.packageName,
    required this.label,
    required this.enabled,
    this.lastSeenAt,
    this.health = SourceHealth.idle,
    this.observationCount = 0,
    this.statusDetail = '',
    this.iconPng,
  });
  final String packageName;
  final String label;
  final bool enabled;
  final DateTime? lastSeenAt;
  final SourceHealth health;
  final int observationCount;
  final String statusDetail;
  final Uint8List? iconPng;
}

@immutable
class DeletedAccountViewData {
  const DeletedAccountViewData({required this.id, required this.name});

  final String id;
  final String name;
}

@immutable
class CategorySpendViewData {
  const CategorySpendViewData({
    required this.category,
    required this.amount,
    required this.fraction,
  });
  final String category;
  final MoneyViewData amount;
  final double fraction;
}

@immutable
class ReviewViewData {
  const ReviewViewData({
    required this.id,
    required this.reason,
    required this.title,
    required this.description,
    required this.transactions,
  });
  final String id;
  final ReviewReason reason;
  final String title;
  final String description;
  final List<TransactionViewData> transactions;
}

@immutable
class DashboardViewData {
  const DashboardViewData({
    required this.netWorth,
    required this.incomeThisMonth,
    required this.spendingThisMonth,
    required this.monthlyChangePercent,
    this.spendableBalance,
    this.savingsBalance,
    this.netCashFlow,
    this.categorySpending = const [],
    this.recentTransfers = const [],
  });
  final MoneyViewData netWorth;
  final MoneyViewData? spendableBalance;
  final MoneyViewData? savingsBalance;
  final MoneyViewData incomeThisMonth;
  final MoneyViewData spendingThisMonth;
  final double monthlyChangePercent;
  final MoneyViewData? netCashFlow;
  final List<CategorySpendViewData> categorySpending;
  final List<TransactionViewData> recentTransfers;
}

@immutable
class TransactionCorrectionDraft {
  const TransactionCorrectionDraft({
    required this.kind,
    required this.category,
    this.accountId,
    this.toAccountId,
  });
  final TransactionKind kind;
  final String category;
  final String? accountId;
  final String? toAccountId;
}

@immutable
class CsvImportDraft {
  const CsvImportDraft({
    required this.csvText,
    required this.accountId,
    required this.mapping,
    this.sourceLabel = 'Statement import',
    this.fileName = 'statement.csv',
    this.sheets = const [],
  });
  final String csvText;
  final String accountId;
  final String sourceLabel;
  final String fileName;
  final Map<ImportField, String> mapping;
  final List<StatementSheetImportDraft> sheets;

  List<StatementSheetImportDraft> get effectiveSheets => sheets.isNotEmpty
      ? sheets
      : [
          StatementSheetImportDraft(
            sheetName: 'Statement',
            csvText: csvText,
            accountId: accountId,
            mapping: mapping,
          ),
        ];
}

@immutable
class StatementSheetImportDraft {
  const StatementSheetImportDraft({
    required this.sheetName,
    required this.csvText,
    required this.accountId,
    required this.mapping,
  });

  final String sheetName;
  final String csvText;
  final String accountId;
  final Map<ImportField, String> mapping;
}

@immutable
class StatementSheetViewData {
  const StatementSheetViewData({
    required this.name,
    required this.csvText,
    this.suggestedAccountId,
    this.accountInferenceReason = '',
    this.accountInferenceConfidence = 0,
    this.detectedInstitution = '',
    this.detectedSuffix = '',
    this.importable = true,
    this.detectionError = '',
  });

  final String name;
  final String csvText;
  final String? suggestedAccountId;
  final String accountInferenceReason;
  final double accountInferenceConfidence;
  final String detectedInstitution;
  final String detectedSuffix;
  final bool importable;
  final String detectionError;
}

@immutable
class StatementFileViewData {
  const StatementFileViewData({required this.fileName, required this.sheets});

  final String fileName;
  final List<StatementSheetViewData> sheets;
}

@immutable
class CsvPreviewRowViewData {
  const CsvPreviewRowViewData({
    required this.rowNumber,
    required this.date,
    required this.description,
    required this.amount,
    required this.valid,
    required this.duplicate,
    this.sheetName = 'Statement',
    this.accountName = '',
    this.category = 'Other',
    this.duplicateReason = '',
    this.error,
  });
  final int rowNumber;
  final String date;
  final String description;
  final String amount;
  final bool valid;
  final bool duplicate;
  final String sheetName;
  final String accountName;
  final String category;
  final String duplicateReason;
  final String? error;
}

@immutable
class CsvImportPreviewViewData {
  const CsvImportPreviewViewData({
    required this.rows,
    required this.validCount,
    required this.errorCount,
    required this.duplicateCount,
    required this.sameFileAlreadyImported,
    this.sheetCount = 1,
    this.reimportedSheetCount = 0,
  });
  final List<CsvPreviewRowViewData> rows;
  final int validCount;
  final int errorCount;
  final int duplicateCount;
  final bool sameFileAlreadyImported;
  final int sheetCount;
  final int reimportedSheetCount;
}

@immutable
class AccountCreationDraft {
  const AccountCreationDraft({
    required this.name,
    required this.type,
    required this.openingBalance,
    this.currency = 'PKR',
    this.institution = '',
    this.suffix = '',
    this.sourcePackages = const {},
    this.smsSenderPattern = '',
  });
  final String name;
  final String type;
  final MoneyViewData openingBalance;
  final String currency;
  final String institution;
  final String suffix;
  final Set<String> sourcePackages;
  final String smsSenderPattern;
}

@immutable
class AccountUpdateDraft {
  const AccountUpdateDraft({
    required this.name,
    required this.type,
    required this.institution,
    required this.suffix,
    required this.sourcePackages,
  });
  final String name;
  final String type;
  final String institution;
  final String suffix;
  final Set<String> sourcePackages;
}

@immutable
class ExportRequest {
  const ExportRequest({
    required this.format,
    this.from,
    this.to,
    this.accountIds = const {},
    this.kinds = const {},
    this.categories = const {},
    this.includeEvidence = false,
  });
  final ExportFormat format;
  final DateTime? from;
  final DateTime? to;
  final Set<String> accountIds;
  final Set<TransactionKind> kinds;
  final Set<String> categories;
  final bool includeEvidence;
}

@immutable
class ManualTransactionDraft {
  const ManualTransactionDraft({
    required this.title,
    required this.amount,
    required this.kind,
    required this.accountId,
    required this.category,
    required this.occurredAt,
    this.toAccountId,
    this.note = '',
  });
  final String title;
  final MoneyViewData amount;
  final TransactionKind kind;
  final String accountId;
  final String? toAccountId;
  final String category;
  final DateTime occurredAt;
  final String note;
}

abstract class SpendWiseViewModel implements Listenable {
  bool get onboardingComplete;
  bool get notificationAccessGranted;
  DashboardViewData get dashboard;
  List<TransactionViewData> get transactions;
  List<AccountViewData> get accounts;
  List<ReviewViewData> get reviews;
  List<SourceViewData> get sources;

  Future<void> completeOnboarding();
  Future<void> requestNotificationAccess();
  Future<void> setSourceEnabled(String packageName, bool enabled);
  Future<void> addAccount(
    String name,
    String type,
    MoneyViewData openingBalance,
  );
  Future<void> saveManualTransaction(ManualTransactionDraft draft);
  Future<void> deleteTransaction(String id);
  Future<void> resolveReview(String id, {required bool merge});
  Future<void> importCsv(String csvText);
  Future<String?> pickCsvFile();
  Future<void> exportData();
  Future<void> eraseAllData();
}

abstract class SpendWiseAdvancedViewModel implements SpendWiseViewModel {
  bool get busy;
  String? get errorMessage;
  bool get demoDataEnabled;
  bool get showSavingsOnHome;
  DeletedAccountViewData? get lastDeletedAccount;
  Future<void> correctTransaction(String id, TransactionCorrectionDraft draft);
  Future<StatementFileViewData?> pickStatementFile();
  Future<CsvImportPreviewViewData> previewCsvImport(CsvImportDraft draft);
  Future<void> commitCsvImport(CsvImportDraft draft);
  Future<void> exportLedger(ExportRequest request);
  Future<void> setDemoDataEnabled(bool enabled);
  Future<void> setShowSavingsOnHome(bool enabled);
  Future<void> addDetailedAccount(AccountCreationDraft draft);
  Future<void> updateDetailedAccount(String id, AccountUpdateDraft draft);
  Future<void> setAccountCurrentBalance(String id, MoneyViewData balance);
  Future<void> archiveAccount(String id);
  Future<void> restoreAccount(String id);
  Future<NotificationTrayScanViewData> scanNotificationTray();
  void dismissError();
}

enum NotificationTrayScanViewStatus {
  completed,
  accessRequired,
  listenerUnavailable,
}

final class NotificationTrayScanViewData {
  const NotificationTrayScanViewData({
    required this.status,
    this.activeCount = 0,
    this.eligibleCount = 0,
    this.queuedCount = 0,
    this.duplicateCount = 0,
    this.failedCount = 0,
  });

  final NotificationTrayScanViewStatus status;
  final int activeCount;
  final int eligibleCount;
  final int queuedCount;
  final int duplicateCount;
  final int failedCount;
}

extension SpendWiseAdvancedAccess on SpendWiseViewModel {
  SpendWiseAdvancedViewModel? get _advanced =>
      this is SpendWiseAdvancedViewModel
      ? this as SpendWiseAdvancedViewModel
      : null;
  bool get uiBusy => _advanced?.busy ?? false;
  String? get uiErrorMessage => _advanced?.errorMessage;
  bool get uiDemoDataEnabled => _advanced?.demoDataEnabled ?? false;
  bool get uiShowSavingsOnHome => _advanced?.showSavingsOnHome ?? false;
  DeletedAccountViewData? get uiLastDeletedAccount =>
      _advanced?.lastDeletedAccount;
  Future<void> uiCorrectTransaction(
    String id,
    TransactionCorrectionDraft draft,
  ) =>
      _advanced?.correctTransaction(id, draft) ??
      Future.error(UnsupportedError('Transaction correction is not available'));
  Future<StatementFileViewData?> uiPickStatementFile() async {
    final advanced = _advanced;
    if (advanced != null) return advanced.pickStatementFile();
    final csv = await pickCsvFile();
    if (csv == null) return null;
    return StatementFileViewData(
      fileName: 'statement.csv',
      sheets: [StatementSheetViewData(name: 'Statement', csvText: csv)],
    );
  }

  Future<void> uiCommitCsvImport(CsvImportDraft draft) =>
      _advanced?.commitCsvImport(draft) ?? importCsv(draft.csvText);
  Future<CsvImportPreviewViewData> uiPreviewCsvImport(CsvImportDraft draft) =>
      _advanced?.previewCsvImport(draft) ??
      Future.error(UnsupportedError('CSV preview is not available'));
  Future<void> uiExportLedger(ExportRequest request) =>
      _advanced?.exportLedger(request) ?? exportData();
  Future<void> uiSetDemoDataEnabled(bool enabled) =>
      _advanced?.setDemoDataEnabled(enabled) ?? Future.value();
  Future<void> uiSetShowSavingsOnHome(bool enabled) =>
      _advanced?.setShowSavingsOnHome(enabled) ?? Future.value();
  Future<void> uiAddDetailedAccount(AccountCreationDraft draft) =>
      _advanced?.addDetailedAccount(draft) ??
      addAccount(draft.name, draft.type, draft.openingBalance);
  Future<void> uiUpdateDetailedAccount(String id, AccountUpdateDraft draft) =>
      _advanced?.updateDetailedAccount(id, draft) ??
      Future.error(UnsupportedError('Account editing is not available'));
  Future<void> uiSetAccountCurrentBalance(String id, MoneyViewData balance) =>
      _advanced?.setAccountCurrentBalance(id, balance) ??
      Future.error(UnsupportedError('Balance adjustment is not available'));
  Future<void> uiArchiveAccount(String id) =>
      _advanced?.archiveAccount(id) ??
      Future.error(UnsupportedError('Account removal is not available'));
  Future<void> uiRestoreAccount(String id) =>
      _advanced?.restoreAccount(id) ??
      Future.error(UnsupportedError('Account restore is not available'));
  Future<NotificationTrayScanViewData> uiScanNotificationTray() =>
      _advanced?.scanNotificationTray() ??
      Future.error(
        UnsupportedError('Notification tray recovery is not available'),
      );
  void uiDismissError() => _advanced?.dismissError();
}
