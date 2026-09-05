import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/perf.dart';
import '../data/ledger_exporter.dart';
import '../data/local_ledger.dart';
import '../domain/domain.dart' as domain;
import '../features/shell/spendwise_view_model.dart';
import '../platform/notification_bridge.dart';

final class SpendWiseController extends ChangeNotifier
    with WidgetsBindingObserver
    implements SpendWiseAdvancedViewModel {
  SpendWiseController._(this._ledger, this._bridge, this._snapshot);

  @visibleForTesting
  factory SpendWiseController.forTests(LocalLedger ledger) =>
      SpendWiseController._(
        ledger,
        const NotificationBridge(),
        ledger.snapshot(),
      );

  LocalLedger _ledger;
  final NotificationBridge _bridge;
  LedgerSnapshot _snapshot;
  bool _notificationAccess = false;
  List<NotificationSource> _nativeSources = const [];
  NotificationIngestionHealth? _ingestionHealth;
  bool _busy = false;
  String? _errorMessage;
  List<AccountViewData>? _accountsCache;
  List<TransactionViewData>? _transactionsCache;
  DashboardViewData? _dashboardCache;
  List<ReviewViewData>? _reviewsCache;
  // Read on every shell rebuild for the Review badge, so it is cached
  // alongside the rest and invalidated by the same reload.
  List<AlertViewData>? _unroutedAlertsCache;

  static Future<SpendWiseController> create() async {
    final ledger = await timedAsync('ledgerOpen', LocalLedger.open);
    final controller = SpendWiseController._(
      ledger,
      const NotificationBridge(),
      ledger.snapshot(),
    );
    WidgetsBinding.instance.addObserver(controller);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(controller._refreshPlatform()),
    );
    return controller;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ledger.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPlatform();
  }

  Future<void> _refreshPlatform() async {
    try {
      _notificationAccess = await _bridge.hasAccess();
      _nativeSources = await _bridge.listSources();
      _ingestionHealth = await _bridge.health();
      _ledger.rememberAndroidSources(
        _nativeSources.map(
          (source) => <String, Object?>{
            'packageName': source.packageName,
            'label': source.label,
            'configured': source.configured,
            'lastObservedAt': source.lastObservedAt?.millisecondsSinceEpoch,
            'iconPng': source.iconPng,
          },
        ),
      );
      await _drainNotificationQueue();
      _reload();
    } on MissingPluginException {
      // Tests and non-Android hosts intentionally have no native listener.
    } on PlatformException {
      // Android can briefly reject package queries while settings changes.
    }
  }

  static const _drainYieldBatchSize = 25;

  Future<void> _drainNotificationQueue() async {
    final queued = await _bridge.peek();
    debugPrint('SpendWiseNotif: drain peeked ${queued.length} queued event(s)');
    final acknowledged = <int>[];
    var ingestedAny = false;
    // Store every notification first and reconcile once at the end.
    // Reconciliation rebuilds the whole ledger, so folding it into each
    // notification made a backlog quadratic and froze the app. Inserts still
    // yield periodically so even the storing pass can't hold the UI isolate
    // for one unbroken stretch.
    for (var start = 0; start < queued.length; start += _drainYieldBatchSize) {
      final chunk = queued.sublist(
        start,
        (start + _drainYieldBatchSize).clamp(0, queued.length),
      );
      final results = _ledger.ingestNotifications(chunk, reconcile: false);
      for (var index = 0; index < chunk.length; index++) {
        if (!results[index]) continue;
        ingestedAny = true;
        final id = (chunk[index]['id'] as num?)?.toInt();
        if (id != null) acknowledged.add(id);
      }
      if (start + _drainYieldBatchSize < queued.length) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (ingestedAny) _ledger.reconcilePendingEvidence();
    if (acknowledged.isNotEmpty) await _bridge.acknowledge(acknowledged);
    debugPrint(
      'SpendWiseNotif: drain acknowledged ${acknowledged.length} event(s)',
    );
  }

  void _reload() {
    _snapshot = _ledger.snapshot();
    _accountsCache = null;
    _transactionsCache = null;
    _dashboardCache = null;
    _reviewsCache = null;
    _unroutedAlertsCache = null;
    notifyListeners();
  }

  @override
  bool get onboardingComplete => _snapshot.onboardingComplete;

  @override
  bool get notificationAccessGranted => _notificationAccess;

  @override
  bool get busy => _busy;

  @override
  String? get errorMessage => _errorMessage;

  @override
  bool get demoDataEnabled => _ledger.demoDataEnabled;

  @override
  bool get showSavingsOnHome => _ledger.showSavingsOnHome;

  @override
  List<String> get ownNames => _ledger.ownNames;

  @override
  DeletedAccountViewData? get lastDeletedAccount {
    final account = _ledger.latestArchivedAccount();
    return account == null
        ? null
        : DeletedAccountViewData(id: account.id, name: account.name);
  }

  @override
  List<AccountViewData> get accounts {
    final cached = _accountsCache;
    if (cached != null) return cached;
    final rows = {
      for (final row in _ledger.exportAccounts()) row['id'] as String: row,
    };
    final sources = {for (final source in _ledger.sources()) source.id: source};
    return _accountsCache = _snapshot.accounts
        .map((account) {
          final row = rows[account.id] ?? const <String, Object?>{};
          final sourceIds =
              (row['sourceIds'] as List?)?.cast<String>() ?? const [];
          return AccountViewData(
            id: account.id,
            name: account.name,
            type: account.type.name,
            isIncluded: account.type != domain.AccountType.savings,
            balance: MoneyViewData(
              _snapshot.accountBalanceMinor(account.id),
              currency: row['currency'] as String? ?? 'PKR',
            ),
            currency: row['currency'] as String? ?? 'PKR',
            institution: row['institution'] as String? ?? '',
            suffix: row['suffix'] as String? ?? '',
            sources: sourceIds
                .map((id) => sources[id])
                .whereType<StoredSource>()
                .map(
                  (source) => AccountSourceViewData(
                    id: source.id,
                    label: source.displayName,
                    packageName: source.packageName ?? '',
                    kind: source.kind,
                  ),
                )
                .toList(growable: false),
          );
        })
        .toList(growable: false);
  }

  String _accountName(String? id) =>
      _snapshot.accounts
          .where((item) => item.id == id)
          .map((item) => item.name)
          .firstOrNull ??
      'Unassigned';

  @override
  List<TransactionViewData> get transactions {
    final cached = _transactionsCache;
    if (cached != null) return cached;
    final categories = _ledger.transactionCategories();
    return _transactionsCache = _snapshot.transactions
        .map((item) {
          final kind = switch (item.kind) {
            domain.TransactionKind.expense => TransactionKind.expense,
            domain.TransactionKind.income => TransactionKind.income,
            domain.TransactionKind.transfer => TransactionKind.transfer,
          };
          final accountLabel = item.kind == domain.TransactionKind.transfer
              ? '${_accountName(item.fromAccountId)} → ${_accountName(item.toAccountId)}'
              : _accountName(item.accountId);
          final evidence = _ledger.evidenceForTransaction(item.id);
          final transactionKind = item.kind;
          return TransactionViewData(
            id: item.id,
            title: item.description?.trim().isNotEmpty == true
                ? item.description!.trim()
                : switch (item.kind) {
                    domain.TransactionKind.expense => 'Payment',
                    domain.TransactionKind.income => 'Money received',
                    domain.TransactionKind.transfer => 'Account transfer',
                  },
            subtitle: accountLabel,
            amount: MoneyViewData(
              item.kind == domain.TransactionKind.expense
                  ? -item.amount.minorUnits.abs()
                  : item.amount.minorUnits.abs(),
              currency: item.amount.currency,
            ),
            kind: kind,
            occurredAt: item.occurredAt.toLocal(),
            category:
                categories[item.id] ??
                (item.kind == domain.TransactionKind.transfer
                    ? 'Transfer'
                    : 'Other'),
            accountName: accountLabel,
            note: item.note ?? '',
            accountId: item.kind == domain.TransactionKind.transfer
                ? item.fromAccountId
                : item.accountId,
            toAccountId: item.toAccountId,
            evidenceCount: evidence.isEmpty
                ? item.evidenceIds.length
                : evidence.length,
            evidence: evidence.indexed
                .map((entry) {
                  final index = entry.$1;
                  final item = entry.$2;
                  return EvidenceViewData(
                    id: item.id,
                    sourceLabel: item.sourceName,
                    packageName: item.sourceKind,
                    observedAt: item.observedAt.toLocal(),
                    state: item.parserId.isEmpty
                        ? EvidenceState.unparsed
                        : transactionKind == domain.TransactionKind.transfer
                        ? EvidenceState.matched
                        : index == 0
                        ? EvidenceState.accepted
                        : EvidenceState.duplicate,
                    title: item.rawTitle ?? '',
                    body: item.rawBody,
                    parserId: item.parserId,
                    confidence: item.confidence / 100,
                    reasons: item.reasonCodes,
                  );
                })
                .toList(growable: false),
            isReviewed: !item.needsReview,
          );
        })
        .toList(growable: false);
  }

  @override
  DashboardViewData get dashboard {
    final cached = _dashboardCache;
    if (cached != null) return cached;
    final now = DateTime.now();
    var income = 0, spending = 0;
    for (final item in _snapshot.transactions) {
      final local = item.occurredAt.toLocal();
      if (local.year != now.year || local.month != now.month) continue;
      if (item.kind == domain.TransactionKind.income) {
        income += item.amount.minorUnits;
      }
      if (item.kind == domain.TransactionKind.expense) {
        spending += item.amount.minorUnits;
      }
    }
    final change = income == 0
        ? (spending == 0 ? 0.0 : -100.0)
        : ((income - spending) / income) * 100;
    final categoryTotals = _ledger.spendingByCategory(month: now);
    final maxCategory = categoryTotals.values.fold<int>(
      0,
      (a, b) => a > b ? a : b,
    );
    return _dashboardCache = DashboardViewData(
      netWorth: MoneyViewData(_snapshot.netWorthMinor),
      spendableBalance: MoneyViewData(_snapshot.spendableBalanceMinor),
      savingsBalance: MoneyViewData(_snapshot.savingsBalanceMinor),
      incomeThisMonth: MoneyViewData(income),
      spendingThisMonth: MoneyViewData(spending),
      monthlyChangePercent: change,
      netCashFlow: MoneyViewData(income - spending),
      categorySpending: categoryTotals.entries
          .map(
            (entry) => CategorySpendViewData(
              category: entry.key,
              amount: MoneyViewData(entry.value),
              fraction: maxCategory == 0 ? 0 : entry.value / maxCategory,
            ),
          )
          .toList(growable: false),
      recentTransfers: transactions
          .where((item) => item.kind == TransactionKind.transfer)
          .take(5)
          .toList(growable: false),
    );
  }

  @override
  List<ReviewViewData> get reviews => _reviewsCache ??= [
    ...transactions
        .where((item) => !item.isReviewed)
        .map(
          (item) => ReviewViewData(
            id: item.id,
            reason: item.kind == TransactionKind.transfer
                ? ReviewReason.possibleTransfer
                : ReviewReason.lowConfidence,
            title: 'Review this transaction',
            description: 'The evidence was parsed, but SpendWise needs your confirmation before locking this result.',
            transactions: [item],
          ),
        ),
    // Grouped per app: a single "N observations need setup" total gave no
    // clue which app to fix, so the whole pile stayed untouched.
    for (final source in _ledger.unparsedBySource())
      ReviewViewData(
        id: '$_unparsedPrefix${source.packageName ?? ''}',
        reason: ReviewReason.parseFailed,
        title:
            '${source.count} unread alert${source.count == 1 ? '' : 's'} from ${source.displayName}',
        description: source.needsAccount
            ? 'These are not linked to an account yet, so nothing from ${source.displayName} reaches your ledger. Attach it to an account to capture them.'
            : '${source.reason ?? 'SpendWise could not read these as transactions.'} If ${source.displayName} does not send payment alerts, dismiss them.',
        transactions: const [],
      ),
  ];

  @override
  List<SourceViewData> get sources => _nativeSources
      .map(
        (item) => SourceViewData(
          packageName: item.packageName,
          label: item.label,
          enabled: item.configured,
          lastSeenAt: item.lastObservedAt?.toLocal(),
          observationCount: item.observationCount,
          iconPng: item.iconPng,
          health: !item.configured
              ? SourceHealth.idle
              : !_notificationAccess
              ? SourceHealth.permissionRequired
              : !item.installed || !item.enabled
              ? SourceHealth.error
              : item.listenerConnected
              ? SourceHealth.healthy
              : SourceHealth.idle,
          statusDetail: !item.configured
              ? 'Disabled — no notifications captured'
              : !_notificationAccess
              ? 'Notification access required'
              : !item.installed
              ? 'App is no longer installed'
              : '${item.observationCount} captured · ${_ingestionHealth?.pendingCount ?? 0} pending${(_ingestionHealth?.evictedCount ?? 0) > 0 ? ' · ${_ingestionHealth!.evictedCount} queue evicted' : ''}',
        ),
      )
      .toList(growable: false);

  @override
  Future<void> completeOnboarding() async {
    _ledger.completeOnboarding();
    _reload();
  }

  @override
  Future<void> requestNotificationAccess() => _bridge.openAccessSettings();

  @override
  Future<void> setSourceEnabled(String packageName, bool enabled) async {
    await _bridge.setSourceEnabled(packageName, enabled);
    await _refreshPlatform();
  }

  @override
  Future<NotificationTrayScanViewData> scanNotificationTray() async {
    _busy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await _bridge.scanCurrentTray();
      if (result.status == NotificationTrayScanStatus.completed) {
        await _drainNotificationQueue();
        _ingestionHealth = await _bridge.health();
        _nativeSources = await _bridge.listSources();
      }
      _notificationAccess = await _bridge.hasAccess();
      return NotificationTrayScanViewData(
        status: switch (result.status) {
          NotificationTrayScanStatus.completed =>
            NotificationTrayScanViewStatus.completed,
          NotificationTrayScanStatus.accessRequired =>
            NotificationTrayScanViewStatus.accessRequired,
          NotificationTrayScanStatus.listenerUnavailable =>
            NotificationTrayScanViewStatus.listenerUnavailable,
        },
        activeCount: result.activeCount,
        eligibleCount: result.eligibleCount,
        queuedCount: result.queuedCount,
        duplicateCount: result.duplicateCount,
        failedCount: result.failedCount,
      );
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('PlatformException: ', '');
      rethrow;
    } finally {
      _busy = false;
      _reload();
    }
  }

  @override
  Future<void> addAccount(
    String name,
    String type,
    MoneyViewData openingBalance,
  ) async {
    final accountType = switch (type.toLowerCase()) {
      String value when value.contains('saving') => domain.AccountType.savings,
      String value when value.contains('wallet') => domain.AccountType.wallet,
      String value when value.contains('cash') => domain.AccountType.cash,
      String value when value.contains('card') => domain.AccountType.card,
      _ => domain.AccountType.bank,
    };
    _ledger.addAccount(
      name: name,
      type: accountType,
      openingBalanceMinor: openingBalance.minorUnits,
    );
    _reload();
  }

  @override
  Future<void> addDetailedAccount(
    AccountCreationDraft draft,
  ) => _runBusy(() async {
    if (draft.currency.toUpperCase() != 'PKR') {
      throw const FormatException(
        'This release supports PKR accounts only. Mixed-currency totals require explicit exchange rates.',
      );
    }
    final accountType = switch (draft.type.toLowerCase()) {
      String value when value.contains('saving') => domain.AccountType.savings,
      String value when value.contains('wallet') => domain.AccountType.wallet,
      String value when value.contains('cash') => domain.AccountType.cash,
      String value when value.contains('card') => domain.AccountType.card,
      _ => domain.AccountType.bank,
    };
    final storedSources = _ledger.sources();
    final sourceIds = storedSources
        .where(
          (source) =>
              source.packageName != null &&
              draft.sourcePackages.contains(source.packageName),
        )
        .map((source) => source.id)
        .toList();
    final sender = draft.smsSenderPattern.trim();
    if (sender.isNotEmpty) {
      final messages = storedSources.where(
        (source) =>
            source.packageName != null &&
            draft.sourcePackages.contains(source.packageName) &&
            (source.packageName!.contains('messaging') ||
                source.packageName!.contains('messages')),
      );
      for (final source in messages) {
        sourceIds.add(
          _ledger.addSmsSenderSource(
            packageName: source.packageName!,
            senderPattern: sender,
            displayName:
                '${draft.institution.trim().isEmpty ? draft.name : draft.institution.trim()} SMS',
            institutionName: draft.institution.trim().isEmpty
                ? null
                : draft.institution.trim(),
          ),
        );
        sourceIds.remove(source.id);
      }
    }
    _ledger.addAccount(
      name: draft.name,
      type: accountType,
      currency: draft.currency,
      institutionName: draft.institution.trim().isEmpty
          ? null
          : draft.institution.trim(),
      accountSuffix: draft.suffix.trim().isEmpty ? null : draft.suffix.trim(),
      openingBalanceMinor: draft.openingBalance.minorUnits,
      sourceIds: sourceIds,
    );
  });

  @override
  Future<void> updateDetailedAccount(String id, AccountUpdateDraft draft) =>
      _runBusy(() async {
        if (draft.name.trim().isEmpty) {
          throw const FormatException('Enter an account name.');
        }
        _ledger.updateAccount(
          id: id,
          name: draft.name,
          type: switch (draft.type.toLowerCase()) {
            String value when value.contains('saving') =>
              domain.AccountType.savings,
            String value when value.contains('wallet') =>
              domain.AccountType.wallet,
            String value when value.contains('cash') => domain.AccountType.cash,
            String value when value.contains('card') => domain.AccountType.card,
            _ => domain.AccountType.bank,
          },
          institutionName: draft.institution.trim().isEmpty
              ? null
              : draft.institution,
          accountSuffix: draft.suffix.trim().isEmpty ? null : draft.suffix,
        );
        final attached = _ledger.sources(accountId: id);
        final attachedPackages = attached
            .map((source) => source.packageName)
            .whereType<String>()
            .toSet();
        final all = _ledger.sources();
        for (final source in attached) {
          if (source.packageName != null &&
              !draft.sourcePackages.contains(source.packageName)) {
            _ledger.detachSource(accountId: id, sourceId: source.id);
          }
        }
        // Only newly-checked sources need attaching (which reparses that
        // source's history and rebuilds the ledger) -- re-attaching sources
        // that were already selected is a costly no-op that made every save
        // feel slow, even when nothing about the sources actually changed.
        for (final source in all) {
          if (source.packageName != null &&
              draft.sourcePackages.contains(source.packageName) &&
              !attachedPackages.contains(source.packageName)) {
            _ledger.attachSource(accountId: id, sourceId: source.id);
          }
        }
      });

  @override
  Future<void> setAccountCurrentBalance(String id, MoneyViewData balance) =>
      _runBusy(() async {
        final account = accounts.where((item) => item.id == id).firstOrNull;
        if (account == null) throw StateError('Account was not found.');
        if (balance.currency != account.currency) {
          throw const FormatException(
            'Balance currency must match the account.',
          );
        }
        _ledger.setAccountCurrentBalance(
          id: id,
          currentBalanceMinor: account.balance.minorUnits,
          targetBalanceMinor: balance.minorUnits,
        );
      });

  @override
  Future<void> archiveAccount(String id) => _runBusy(() async {
    _ledger.archiveAccount(id);
  });

  @override
  Future<void> restoreAccount(String id) => _runBusy(() async {
    _ledger.restoreAccount(id);
  });

  @override
  Future<void> saveManualTransaction(ManualTransactionDraft draft) async {
    final kind = switch (draft.kind) {
      TransactionKind.expense => domain.TransactionKind.expense,
      TransactionKind.income => domain.TransactionKind.income,
      TransactionKind.transfer => domain.TransactionKind.transfer,
    };
    _ledger.addManualTransaction(
      kind: kind,
      amountMinor: draft.amount.minorUnits.abs(),
      occurredAt: draft.occurredAt,
      accountId: kind == domain.TransactionKind.transfer
          ? null
          : draft.accountId,
      fromAccountId: kind == domain.TransactionKind.transfer
          ? draft.accountId
          : null,
      toAccountId: kind == domain.TransactionKind.transfer
          ? draft.toAccountId
          : null,
      description: draft.title,
      note: draft.note,
      categoryId: _categoryId(draft.category),
    );
    _reload();
  }

  @override
  Future<void> deleteTransaction(String id) async {
    _ledger.deleteTransaction(id);
    _reload();
  }

  @override
  Future<void> restoreTransaction(String id) async {
    _ledger.restoreTransaction(id);
    _reload();
  }

  static const _unparsedPrefix = 'unparsed:';

  @override
  Future<void> resolveReview(String id, {required bool merge}) async {
    if (id == 'unparsed') {
      _ledger.dismissUnparsed();
    } else if (id.startsWith(_unparsedPrefix)) {
      final package = id.substring(_unparsedPrefix.length);
      _ledger.dismissUnparsed(packageName: package.isEmpty ? null : package);
    } else {
      _ledger.confirmTransaction(id);
    }
    _reload();
  }

  String? _categoryId(String name) => _ledger
      .categories()
      .where((item) => item.name.toLowerCase() == name.toLowerCase())
      .map((item) => item.id)
      .firstOrNull;

  Future<void> _runBusy(Future<void> Function() operation) async {
    _busy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await operation();
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('FormatException: ', '');
      rethrow;
    } finally {
      _busy = false;
      _reload();
    }
  }

  @override
  Future<void> correctTransaction(
    String id,
    TransactionCorrectionDraft draft,
  ) => _runBusy(() async {
    final current = _snapshot.transactions.where((item) => item.id == id).first;
    final kind = switch (draft.kind) {
      TransactionKind.expense => domain.TransactionKind.expense,
      TransactionKind.income => domain.TransactionKind.income,
      TransactionKind.transfer => domain.TransactionKind.transfer,
    };
    _ledger.updateTransaction(
      id: id,
      kind: kind,
      description: current.description ?? current.kind.name,
      occurredAt: current.occurredAt,
      amountMinor: current.amount.minorUnits,
      currency: current.amount.currency,
      accountId: kind == domain.TransactionKind.transfer
          ? null
          : draft.accountId,
      fromAccountId: kind == domain.TransactionKind.transfer
          ? draft.accountId
          : null,
      toAccountId: kind == domain.TransactionKind.transfer
          ? draft.toAccountId
          : null,
      categoryId: _categoryId(draft.category),
    );
  });
  @override
  void dismissError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  Future<void> exportLedger(ExportRequest request) => _runBusy(() async {
    final kinds = request.kinds
        .map(
          (kind) => switch (kind) {
            TransactionKind.expense => domain.TransactionKind.expense,
            TransactionKind.income => domain.TransactionKind.income,
            TransactionKind.transfer => domain.TransactionKind.transfer,
          },
        )
        .toSet();
    final categoryIds = _ledger
        .categories()
        .where((item) => request.categories.contains(item.name))
        .map((item) => item.id)
        .toSet();
    final filter = LedgerExportFilter(
      from: request.from,
      to: request.to?.add(const Duration(days: 1)),
      accountIds: request.accountIds,
      kinds: kinds,
      categoryIds: categoryIds,
      includeEvidence: request.includeEvidence,
    );
    final exporter = LedgerExporter(_ledger);
    final isJson = request.format == ExportFormat.json;
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export plaintext SpendWise data',
      fileName: isJson ? 'spendwise-backup.json' : 'spendwise-ledger.csv',
      type: FileType.custom,
      allowedExtensions: [isJson ? 'json' : 'csv'],
      bytes: isJson ? exporter.jsonBackup(filter) : exporter.csv(filter),
    );
    if (result == null) throw const ExportCancelledException();
  });

  @override
  Future<void> setDemoDataEnabled(bool enabled) => _runBusy(() async {
    enabled ? _ledger.seedDemoData() : _ledger.removeDemoData();
  });

  @override
  Future<void> setShowSavingsOnHome(bool enabled) => _runBusy(() async {
    _ledger.setShowSavingsOnHome(enabled);
  });

  @override
  Future<void> setOwnNames(List<String> names) => _runBusy(() async {
    _ledger.setOwnNames(names);
  });

  /// One Review rule, applied to every alert it covers, with a single
  /// reconciliation pass at the end. The old screen ran one round-trip per
  /// item, which is why clearing an inbox of six felt like work.
  @override
  Future<void> applyReviewDecision(ReviewDecision decision) => _runBusy(() async {
    switch (decision.kind) {
      case ReviewDecisionKind.confirm:
        _ledger.confirmTransactions(decision.transactionIds);
      case ReviewDecisionKind.categorize:
        _ledger.categorizeTransactions(
          decision.transactionIds,
          _categoryId(decision.category ?? ''),
        );
      case ReviewDecisionKind.route:
        final accountId = decision.accountId;
        if (accountId == null) {
          throw ArgumentError('Routing needs an account');
        }
        _ledger.routeTransactions(decision.transactionIds, accountId);
      case ReviewDecisionKind.redirect:
        _ledger.redirectTransactions(
          decision.transactionIds,
          expense: decision.expense,
        );
      case ReviewDecisionKind.routeAlerts:
        final target = decision.accountId;
        if (target == null) {
          throw ArgumentError('Routing needs an account');
        }
        _ledger.routeAlerts(decision.alertIds, target);
      case ReviewDecisionKind.dismissSource:
        final package = decision.packageName;
        _ledger.dismissUnparsed(
          packageName: package == null || package.isEmpty ? null : package,
        );
    }
  });

  @override
  List<AlertViewData> alerts({
    String? packageName,
    bool onlyUnresolved = true,
  }) => _ledger
      .alerts(packageName: packageName, onlyUnresolved: onlyUnresolved)
      .map(_alertView)
      .toList(growable: false);

  @override
  List<AlertViewData> get unroutedAlerts => _unroutedAlertsCache ??= _ledger
      .unroutedAlerts()
      .map(_alertView)
      .toList(growable: false);

  @override
  bool isSharedSource(String packageName) =>
      _ledger.isSharedSource(packageName);

  static AlertViewData _alertView(StoredAlert alert) => AlertViewData(
    id: alert.id,
    observedAt: alert.observedAt.toLocal(),
    title: alert.title,
    body: alert.body,
    sourceLabel: alert.sourceLabel,
    packageName: alert.packageName,
    status: alert.status,
    reason: alert.reason,
    accountName: alert.accountName,
  );

  @override
  String? viewPreference(String key) => _ledger.viewPreference(key);

  @override
  void setViewPreference(String key, String value) =>
      _ledger.setViewPreference(key, value);

  @override
  Future<void> exportData() async {
    final buffer = StringBuffer(
      'date,type,description,amount_minor,currency,account\r\n',
    );
    for (final item in transactions) {
      String escaped(String value) => '"${value.replaceAll('"', '""')}"';
      buffer.writeln(
        [
          item.occurredAt.toIso8601String(),
          item.kind.name,
          escaped(item.title),
          item.amount.minorUnits,
          item.amount.currency,
          escaped(item.accountName),
        ].join(','),
      );
    }
    await FilePicker.platform.saveFile(
      dialogTitle: 'Export SpendWise ledger',
      fileName: 'spendwise-ledger.csv',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      bytes: Uint8List.fromList(utf8.encode(buffer.toString())),
    );
  }

  @override
  Future<void> eraseAllData() async {
    await _bridge.clear();
    await _ledger.wipe();
    _ledger = await LocalLedger.open();
    _snapshot = _ledger.snapshot();
    _nativeSources = const [];
    notifyListeners();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
