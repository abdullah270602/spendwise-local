import 'package:flutter/foundation.dart';

import '../../app/home_period.dart';
export '../../app/home_period.dart';

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
    this.debtId,
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

  /// Set when this is a loan being made or repaid. Such a movement is
  /// neither spending nor income, so it is left out of both.
  final String? debtId;

  bool get isLoanMovement => debtId != null;
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

/// What one tap on a Review rule does. Review used to ask the user to clear
/// alerts one at a time; a decision now names every alert it covers, so the
/// same tap that fixes one fixes ten.
enum ReviewDecisionKind {
  /// Accept the parse as-is and lock it.
  confirm,

  /// Accept, but file everything under one category first.
  categorize,

  /// Accept, but attach everything to one account first.
  route,

  /// The parser read the direction backwards; flip it, then accept.
  redirect,

  /// These were never transactions. Drop the raw alerts.
  dismissSource,

  /// The alert was readable all along; it just had nowhere to go. File the
  /// raw alerts onto an account and read them again.
  routeAlerts,

  /// These alerts are transactions; the parser just could not tell which way
  /// the money went. Take the user's answer and file them.
  fileAlerts,
}

@immutable
class ReviewDecision {
  const ReviewDecision({
    required this.kind,
    this.transactionIds = const [],
    this.category,
    this.accountId,
    this.expense = true,
    this.packageName,
    this.alertIds = const [],
  });

  final ReviewDecisionKind kind;
  final List<String> transactionIds;
  final String? category;
  final String? accountId;
  final bool expense;
  final String? packageName;

  /// Raw observation ids, for decisions that act before parsing.
  final List<String> alertIds;

  int get count => alertIds.isEmpty ? transactionIds.length : alertIds.length;
}

/// Money that left but is still yours, or arrived but is not.
///
/// A bank alert cannot tell a loan from a purchase -- both read "PKR 20,000
/// sent". Only the person knows, so this is marked by hand, and once marked
/// the money stops counting as spending because it is coming back.
@immutable
class DebtViewData {
  const DebtViewData({
    required this.id,
    required this.lent,
    required this.counterparty,
    required this.principal,
    required this.settled,
    required this.outstanding,
    required this.openedAt,
    required this.isSettled,
    this.note,
    this.closedAt,
  });

  final String id;

  /// True when the user lent it out; false when they borrowed it.
  final bool lent;
  final String counterparty;
  final MoneyViewData principal;
  final MoneyViewData settled;
  final MoneyViewData outstanding;
  final DateTime openedAt;
  final bool isSettled;
  final String? note;
  final DateTime? closedAt;

  bool get isPartlyPaid => settled.minorUnits > 0 && outstanding.minorUnits > 0;
}

/// A category the user can file a transaction under. System categories are
/// the ones the classifier knows by name; the rest the user added.
@immutable
class CategoryViewData {
  const CategoryViewData({
    required this.id,
    required this.name,
    required this.kind,
    this.isSystem = true,
  });

  final String id;
  final String name;

  /// 'expense', 'income' or 'both'.
  final String kind;
  final bool isSystem;

  bool suits(TransactionKind transactionKind) => switch (transactionKind) {
    TransactionKind.income => kind == 'income' || kind == 'both',
    TransactionKind.expense => kind == 'expense' || kind == 'both',
    TransactionKind.transfer => true,
  };
}

/// One captured notification as it arrived. Review groups alerts into rules,
/// but the raw text has to stay reachable -- a summary the user cannot check
/// is just an assertion.
@immutable
class AlertViewData {
  const AlertViewData({
    required this.id,
    required this.observedAt,
    required this.title,
    required this.body,
    required this.sourceLabel,
    required this.status,
    this.packageName,
    this.reason,
    this.accountName,
  });

  final String id;
  final DateTime observedAt;
  final String title;
  final String body;
  final String sourceLabel;
  final String? packageName;

  /// 'parsed', 'review', 'error' or 'ignored'.
  final String status;
  final String? reason;
  final String? accountName;

  bool get reachedLedger => status == 'parsed';
  bool get ignored => status == 'ignored';
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
  Future<void> restoreTransaction(String id);
  Future<void> resolveReview(String id, {required bool merge});
  Future<void> exportData();
  Future<void> eraseAllData();
}

abstract class SpendWiseAdvancedViewModel implements SpendWiseViewModel {
  bool get busy;
  String? get errorMessage;
  bool get demoDataEnabled;
  bool get showSavingsOnHome;
  List<String> get ownNames;
  DeletedAccountViewData? get lastDeletedAccount;
  Future<void> correctTransaction(String id, TransactionCorrectionDraft draft);
  Future<void> exportLedger(ExportRequest request);
  Future<void> setDemoDataEnabled(bool enabled);
  Future<void> setShowSavingsOnHome(bool enabled);
  Future<void> setOwnNames(List<String> names);
  Future<void> addDetailedAccount(AccountCreationDraft draft);
  Future<void> updateDetailedAccount(String id, AccountUpdateDraft draft);
  Future<void> setAccountCurrentBalance(String id, MoneyViewData balance);
  Future<void> archiveAccount(String id);
  Future<void> restoreAccount(String id);
  Future<NotificationTrayScanViewData> scanNotificationTray();
  Future<void> applyReviewDecision(ReviewDecision decision);

  /// What stretch of time Home is a picture of.
  HomePeriod get homePeriod;
  void setHomePeriod(HomePeriod period);

  /// Loans made and taken, newest first.
  List<DebtViewData> get debts;

  /// Marks an existing entry as a loan and opens the debt behind it.
  Future<void> openDebt({
    required String transactionId,
    required bool lent,
    required String counterparty,
    String? note,
  });

  /// Records money coming back. Pass [transactionId] when a real entry in the
  /// ledger is the repayment; omit it for cash that never touched an account.
  Future<void> settleDebt({
    required String debtId,
    required MoneyViewData amount,
    String? transactionId,
  });

  Future<void> closeDebt(String id);
  Future<void> removeDebt(String id);

  /// Every category available to file under, system and user-added.
  List<CategoryViewData> get categories;

  /// Adds one of the user's own. Returns the name actually stored, which may
  /// be an existing category if the name was already taken.
  Future<String> addCategory(String name, {String kind});

  Future<void> removeCategory(String id);

  /// Captured alerts, newest first. Defaults to the ones still unresolved.
  List<AlertViewData> alerts({String? packageName, bool onlyUnresolved = true});

  /// Alerts that read like money but reached no account.
  List<AlertViewData> get unroutedAlerts;

  /// Apps that carry more than one institution, so they are never bound to a
  /// single account.
  bool isSharedSource(String packageName);

  /// Every permission this build declares, read back from the installed
  /// package. Shown in the guide so the privacy claim can be checked
  /// rather than believed.
  Future<List<String>> declaredPermissions();

  String? viewPreference(String key);
  void setViewPreference(String key, String value);
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
  List<String> get uiOwnNames => _advanced?.ownNames ?? const [];
  DeletedAccountViewData? get uiLastDeletedAccount =>
      _advanced?.lastDeletedAccount;
  Future<void> uiCorrectTransaction(
    String id,
    TransactionCorrectionDraft draft,
  ) =>
      _advanced?.correctTransaction(id, draft) ??
      Future.error(UnsupportedError('Transaction correction is not available'));
  Future<void> uiExportLedger(ExportRequest request) =>
      _advanced?.exportLedger(request) ?? exportData();
  Future<void> uiSetDemoDataEnabled(bool enabled) =>
      _advanced?.setDemoDataEnabled(enabled) ?? Future.value();
  Future<void> uiSetShowSavingsOnHome(bool enabled) =>
      _advanced?.setShowSavingsOnHome(enabled) ?? Future.value();
  Future<void> uiSetOwnNames(List<String> names) =>
      _advanced?.setOwnNames(names) ?? Future.value();
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
  List<AlertViewData> uiAlerts({
    String? packageName,
    bool onlyUnresolved = true,
  }) =>
      _advanced?.alerts(
        packageName: packageName,
        onlyUnresolved: onlyUnresolved,
      ) ??
      const [];
  List<AlertViewData> get uiUnroutedAlerts =>
      _advanced?.unroutedAlerts ?? const [];
  bool uiIsSharedSource(String packageName) =>
      _advanced?.isSharedSource(packageName) ?? false;
  Future<List<String>> uiDeclaredPermissions() =>
      _advanced?.declaredPermissions() ?? Future.value(const []);
  HomePeriod get uiHomePeriod =>
      _advanced?.homePeriod ?? HomePeriod.calendarMonth;
  void uiSetHomePeriod(HomePeriod period) => _advanced?.setHomePeriod(period);
  List<DebtViewData> get uiDebts => _advanced?.debts ?? const [];
  Future<void> uiOpenDebt({
    required String transactionId,
    required bool lent,
    required String counterparty,
    String? note,
  }) =>
      _advanced?.openDebt(
        transactionId: transactionId,
        lent: lent,
        counterparty: counterparty,
        note: note,
      ) ??
      Future.error(UnsupportedError('Loans are not available'));
  Future<void> uiSettleDebt({
    required String debtId,
    required MoneyViewData amount,
    String? transactionId,
  }) =>
      _advanced?.settleDebt(
        debtId: debtId,
        amount: amount,
        transactionId: transactionId,
      ) ??
      Future.error(UnsupportedError('Loans are not available'));
  Future<void> uiCloseDebt(String id) =>
      _advanced?.closeDebt(id) ?? Future.value();
  Future<void> uiRemoveDebt(String id) =>
      _advanced?.removeDebt(id) ?? Future.value();
  List<CategoryViewData> get uiCategories => _advanced?.categories ?? const [];
  Future<String> uiAddCategory(String name, {String kind = 'expense'}) =>
      _advanced?.addCategory(name, kind: kind) ??
      Future.error(UnsupportedError('Categories cannot be added'));
  Future<void> uiRemoveCategory(String id) =>
      _advanced?.removeCategory(id) ?? Future.value();
  Future<void> uiApplyReviewDecision(ReviewDecision decision) =>
      _advanced?.applyReviewDecision(decision) ??
      Future.error(UnsupportedError('Review rules are not available'));

  /// Sticky view choices (Ledger chart/plain, Accounts map/plain). Reads are
  /// synchronous and writes are fire-and-forget so a toggle never waits on
  /// storage -- these are preferences, not data.
  String? uiViewPreference(String key) => _advanced?.viewPreference(key);
  void uiSetViewPreference(String key, String value) =>
      _advanced?.setViewPreference(key, value);
  void uiDismissError() => _advanced?.dismissError();
}
