import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/csv_importer.dart';
import '../data/csv_import_wizard.dart';
import '../data/ledger_exporter.dart';
import '../data/local_ledger.dart';
import '../domain/domain.dart' as domain;
import '../features/shell/spendwise_view_model.dart';
import '../platform/notification_bridge.dart';

final class SpendWiseController extends ChangeNotifier
    with WidgetsBindingObserver
    implements SpendWiseAdvancedViewModel {
  SpendWiseController._(this._ledger, this._bridge, this._snapshot);

  LocalLedger _ledger;
  final NotificationBridge _bridge;
  LedgerSnapshot _snapshot;
  bool _notificationAccess = false;
  List<NotificationSource> _nativeSources = const [];
  NotificationIngestionHealth? _ingestionHealth;
  bool _busy = false;
  String? _errorMessage;

  static Future<SpendWiseController> create() async {
    final ledger = await LocalLedger.open();
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
      final queued = await _bridge.peek();
      final acknowledged = <int>[];
      for (final event in queued) {
        if (_ledger.ingestNotification(event)) {
          final id = (event['id'] as num?)?.toInt();
          if (id != null) acknowledged.add(id);
        }
      }
      if (acknowledged.isNotEmpty) await _bridge.acknowledge(acknowledged);
      _reload();
    } on MissingPluginException {
      // Tests and non-Android hosts intentionally have no native listener.
    } on PlatformException {
      // Android can briefly reject package queries while settings changes.
    }
  }

  void _reload() {
    _snapshot = _ledger.snapshot();
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
  DeletedAccountViewData? get lastDeletedAccount {
    final account = _ledger.latestArchivedAccount();
    return account == null
        ? null
        : DeletedAccountViewData(id: account.id, name: account.name);
  }

  @override
  List<AccountViewData> get accounts {
    final rows = {
      for (final row in _ledger.exportAccounts()) row['id'] as String: row,
    };
    final sources = {for (final source in _ledger.sources()) source.id: source};
    return _snapshot.accounts
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
    final categories = _ledger.transactionCategories();
    return _snapshot.transactions
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
                : item.kind.name,
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
    return DashboardViewData(
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
  List<ReviewViewData> get reviews => [
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
    if (_snapshot.unparsedCount > 0)
      ReviewViewData(
        id: 'unparsed',
        reason: ReviewReason.parseFailed,
        title:
            '${_snapshot.unparsedCount} observation${_snapshot.unparsedCount == 1 ? '' : 's'} need setup',
        description:
            'Map its source to an account, or dismiss unsupported events.',
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
        final all = _ledger.sources();
        for (final source in attached) {
          if (source.packageName != null &&
              !draft.sourcePackages.contains(source.packageName)) {
            _ledger.detachSource(accountId: id, sourceId: source.id);
          }
        }
        for (final source in all) {
          if (source.packageName != null &&
              draft.sourcePackages.contains(source.packageName)) {
            _ledger.attachSource(accountId: id, sourceId: source.id);
          }
        }
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
  Future<void> resolveReview(String id, {required bool merge}) async {
    id == 'unparsed'
        ? _ledger.dismissUnparsed()
        : _ledger.confirmTransaction(id);
    _reload();
  }

  @override
  Future<String?> pickCsvFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return null;
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  @override
  Future<void> importCsv(String csvText) async {
    if (_snapshot.accounts.isEmpty) {
      throw StateError('Add an account before importing a statement.');
    }
    CsvImporter(_ledger)
        .import(csvText, accountId: _snapshot.accounts.first.id);
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

  ({
    CsvImportWizard wizard,
    CsvImportPreview preview,
    CsvMappingDefinition mapping,
  })
  _prepareCsvImport(CsvImportDraft draft) {
    final wizard = CsvImportWizard(_ledger);
    final inspection = wizard.inspect(
      fileName: draft.sourceLabel.endsWith('.csv')
          ? draft.sourceLabel
          : '${draft.sourceLabel}.csv',
      text: draft.csvText,
      accountId: draft.accountId,
    );
    final roles = <int, CsvColumnRole>{};
    for (final entry in draft.mapping.entries) {
      final index = inspection.headers.indexOf(entry.value);
      if (index < 0) continue;
      roles[index] = switch (entry.key) {
        ImportField.date => CsvColumnRole.date,
        ImportField.description => CsvColumnRole.description,
        ImportField.amount => CsvColumnRole.amount,
        ImportField.debit => CsvColumnRole.debit,
        ImportField.credit => CsvColumnRole.credit,
        ImportField.direction => CsvColumnRole.direction,
        ImportField.balance => CsvColumnRole.balance,
        ImportField.merchant => CsvColumnRole.merchant,
        ImportField.currency => CsvColumnRole.currency,
        ImportField.reference => CsvColumnRole.reference,
        ImportField.ignore => CsvColumnRole.ignore,
      };
    }
    final mapping = CsvMappingDefinition(
      roles: roles,
      dateFormat: _detectDateFormat(inspection, roles),
      defaultCurrency:
          accounts
              .where((account) => account.id == draft.accountId)
              .map((account) => account.currency)
              .firstOrNull ??
          'PKR',
    );
    final preview = wizard.preview(
      inspection: inspection,
      text: draft.csvText,
      accountId: draft.accountId,
      mapping: mapping,
    );
    return (wizard: wizard, preview: preview, mapping: mapping);
  }

  @override
  Future<CsvImportPreviewViewData> previewCsvImport(
    CsvImportDraft draft,
  ) async {
    final prepared = _prepareCsvImport(draft);
    final preview = prepared.preview;
    return CsvImportPreviewViewData(
      validCount: preview.validCount,
      errorCount: preview.errorCount,
      duplicateCount: preview.duplicateCount,
      sameFileAlreadyImported: preview.sameFileAlreadyImported,
      rows: preview.rows
          .map(
            (row) => CsvPreviewRowViewData(
              rowNumber: row.rowNumber,
              date:
                  row.occurredAt
                      ?.toLocal()
                      .toIso8601String()
                      .split('T')
                      .first ??
                  (row.raw.values.firstOrNull ?? ''),
              description: row.description ?? row.merchant ?? '',
              amount: row.amount == null
                  ? ''
                  : '${row.direction?.name == 'debit' ? '-' : '+'}${row.amount!.currency} ${(row.amount!.minorUnits / 100).toStringAsFixed(2)}',
              valid: row.valid,
              duplicate: row.probableDuplicate,
              error: row.error,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<void> commitCsvImport(CsvImportDraft draft) => _runBusy(() async {
    final prepared = _prepareCsvImport(draft);
    final wizard = prepared.wizard;
    final preview = prepared.preview;
    wizard.commit(
      preview: preview,
      accountId: draft.accountId,
      mappingName: draft.sourceLabel,
    );
  });

  @override
  void dismissError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  CsvDateFormat _detectDateFormat(
    CsvInspection inspection,
    Map<int, CsvColumnRole> roles,
  ) {
    final dateColumn = roles.entries
        .where((entry) => entry.value == CsvColumnRole.date)
        .map((entry) => entry.key)
        .firstOrNull;
    if (dateColumn == null || inspection.sampleRows.isEmpty) {
      return CsvDateFormat.isoYearMonthDay;
    }
    final sample = inspection.sampleRows.first.length > dateColumn
        ? inspection.sampleRows.first[dateColumn].trim()
        : '';
    if (RegExp(r'^\d{4}-').hasMatch(sample)) {
      return CsvDateFormat.isoYearMonthDay;
    }
    if (sample.contains('-')) return CsvDateFormat.dayMonthYearDash;
    return CsvDateFormat.dayMonthYearSlash;
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
