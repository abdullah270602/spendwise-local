import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../domain/domain.dart';

final class StoredSource {
  const StoredSource({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.enabled,
    this.packageName,
    this.senderPattern,
    this.institutionName,
    this.iconPng,
    this.lastEventAt,
  });

  final String id;
  final String kind;
  final String displayName;
  final bool enabled;
  final String? packageName;
  final String? senderPattern;
  final String? institutionName;
  final Uint8List? iconPng;
  final DateTime? lastEventAt;
}

final class StoredCategory {
  const StoredCategory({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.colorValue,
    required this.kind,
  });

  final String id;
  final String name;
  final String iconKey;
  final int colorValue;
  final String kind;
}

final class StoredEvidence {
  const StoredEvidence({
    required this.id,
    required this.observedAt,
    required this.sourceName,
    required this.sourceKind,
    required this.rawTitle,
    required this.rawBody,
    required this.parserId,
    required this.parserVersion,
    required this.confidence,
    required this.reasonCodes,
    required this.payloadJson,
    this.reference,
  });

  final String id;
  final DateTime observedAt;
  final String sourceName;
  final String sourceKind;
  final String? rawTitle;
  final String rawBody;
  final String parserId;
  final int parserVersion;
  final int confidence;
  final List<String> reasonCodes;
  final String payloadJson;
  final String? reference;
}

final class LedgerSnapshot {
  const LedgerSnapshot({
    required this.accounts,
    required this.transactions,
    required this.openingBalances,
    required this.unparsedCount,
    required this.onboardingComplete,
  });

  final List<Account> accounts;
  final List<CanonicalTransaction> transactions;
  final Map<String, int> openingBalances;
  final int unparsedCount;
  final bool onboardingComplete;

  int get reviewCount =>
      unparsedCount + transactions.where((item) => item.needsReview).length;

  int get netWorthMinor {
    var total = 0;
    for (final account in accounts) {
      total += accountBalanceMinor(account.id);
    }
    return total;
  }

  int get spendableBalanceMinor {
    var total = 0;
    for (final account in accounts.where(
      (account) => account.type != AccountType.savings,
    )) {
      total += accountBalanceMinor(account.id);
    }
    return total;
  }

  int get savingsBalanceMinor {
    var total = 0;
    for (final account in accounts.where(
      (account) => account.type == AccountType.savings,
    )) {
      total += accountBalanceMinor(account.id);
    }
    return total;
  }

  int accountBalanceMinor(String accountId) {
    var value = openingBalances[accountId] ?? 0;
    for (final item in transactions) {
      if (item.kind == TransactionKind.expense && item.accountId == accountId) {
        value -= item.amount.minorUnits;
      } else if (item.kind == TransactionKind.income &&
          item.accountId == accountId) {
        value += item.amount.minorUnits;
      } else if (item.kind == TransactionKind.transfer) {
        if (item.fromAccountId == accountId) value -= item.amount.minorUnits;
        if (item.toAccountId == accountId) value += item.amount.minorUnits;
      }
    }
    return value;
  }
}

/// The single encrypted, on-device source of truth for SpendWise.
final class LocalLedger {
  LocalLedger._(this._db, this._path);

  static const _keyName = 'spendwise_sqlcipher_key_v1';
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _ids = Uuid();

  final Database _db;
  final String _path;

  static Future<LocalLedger> open() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final path = p.join(directory.path, 'spendwise.db');
    final key = await _loadOrCreateKey();
    final db = sqlite3.open(path);
    try {
      // SQLCipher requires keying before any read, including schema inspection.
      db.execute("PRAGMA key = \"x'$key'\"");
      final cipher = db.select('PRAGMA cipher_version');
      if (cipher.isEmpty || cipher.first.values.firstOrNull == null) {
        throw StateError(
          'SQLCipher is unavailable; refusing an unencrypted ledger.',
        );
      }
      db.execute('PRAGMA cipher_memory_security = ON');
      db.execute('PRAGMA foreign_keys = ON');
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA busy_timeout = 5000');
      db.execute('PRAGMA secure_delete = ON');
      final ledger = LocalLedger._(db, path);
      ledger._migrate();
      return ledger;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  /// Test-only in-memory store. Production always uses [open] and verifies
  /// SQLCipher before creating any schema.
  static LocalLedger openInMemoryForTests() {
    final ledger = LocalLedger._(sqlite3.openInMemory(), ':memory:');
    ledger._db.execute('PRAGMA foreign_keys = ON');
    ledger._migrate();
    return ledger;
  }

  @visibleForTesting
  void rerunMigrationsForTests() => _migrate();

  @visibleForTesting
  void resetDedupMigrationForTests() => _db.execute(
    "DELETE FROM app_settings WHERE key = 'dedup_ranking_volatile_v1'",
  );

  T runAtomic<T>(T Function() operation) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final result = operation();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  static Future<String> _loadOrCreateKey() async {
    final existing = await _secureStorage.read(key: _keyName);
    if (existing != null && existing.length == 64) return existing;
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    final key = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    await _secureStorage.write(key: _keyName, value: key);
    return key;
  }

  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        currency TEXT NOT NULL,
        source_package TEXT UNIQUE,
        archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS raw_observations (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        external_id TEXT NOT NULL,
        source_package TEXT,
        account_id TEXT REFERENCES accounts(id),
        observed_at INTEGER NOT NULL,
        title TEXT,
        body TEXT NOT NULL,
        parse_status TEXT NOT NULL,
        parse_error TEXT,
        UNIQUE(kind, external_id)
      );
      CREATE TABLE IF NOT EXISTS event_candidates (
        id TEXT PRIMARY KEY,
        observation_id TEXT NOT NULL UNIQUE REFERENCES raw_observations(id) ON DELETE CASCADE,
        account_id TEXT NOT NULL REFERENCES accounts(id),
        direction TEXT NOT NULL,
        amount_minor INTEGER NOT NULL CHECK(amount_minor > 0),
        currency TEXT NOT NULL,
        occurred_at INTEGER NOT NULL,
        counterparty TEXT,
        reference TEXT,
        description TEXT,
        confidence REAL NOT NULL
      );
      CREATE TABLE IF NOT EXISTS transactions (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        amount_minor INTEGER NOT NULL CHECK(amount_minor > 0),
        currency TEXT NOT NULL,
        occurred_at INTEGER NOT NULL,
        account_id TEXT REFERENCES accounts(id),
        from_account_id TEXT REFERENCES accounts(id),
        to_account_id TEXT REFERENCES accounts(id),
        description TEXT,
        needs_review INTEGER NOT NULL,
        locked INTEGER NOT NULL,
        origin TEXT NOT NULL,
        category TEXT,
        deleted_at INTEGER
      );
      CREATE TABLE IF NOT EXISTS transaction_evidence (
        transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
        observation_id TEXT NOT NULL UNIQUE REFERENCES raw_observations(id),
        PRIMARY KEY(transaction_id, observation_id)
      );
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS raw_status_idx ON raw_observations(parse_status, observed_at);
      CREATE INDEX IF NOT EXISTS candidate_match_idx ON event_candidates(currency, amount_minor, occurred_at);
      CREATE INDEX IF NOT EXISTS transaction_date_idx ON transactions(occurred_at DESC);
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS sources (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL CHECK(kind IN ('androidApp','smsSender','csv','manual')),
        display_name TEXT NOT NULL,
        package_name TEXT,
        sender_pattern TEXT,
        institution_name TEXT,
        icon_png BLOB,
        enabled INTEGER NOT NULL DEFAULT 1,
        last_event_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        UNIQUE(package_name, sender_pattern)
      );
      CREATE TABLE IF NOT EXISTS account_sources (
        account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
        parser_definition_id TEXT,
        priority INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        PRIMARY KEY(account_id, source_id)
      );
      CREATE TABLE IF NOT EXISTS raw_notification_snapshots (
        id TEXT PRIMARY KEY,
        raw_observation_id TEXT NOT NULL UNIQUE REFERENCES raw_observations(id) ON DELETE CASCADE,
        notification_key TEXT NOT NULL,
        snapshot_sequence INTEGER NOT NULL,
        content_hash TEXT NOT NULL,
        posted_at INTEGER NOT NULL,
        captured_at INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        UNIQUE(notification_key, content_hash)
      );
      CREATE TABLE IF NOT EXISTS financial_evidence (
        id TEXT PRIMARY KEY,
        raw_observation_id TEXT NOT NULL REFERENCES raw_observations(id) ON DELETE CASCADE,
        source_id TEXT REFERENCES sources(id),
        account_id TEXT REFERENCES accounts(id),
        amount_minor INTEGER NOT NULL CHECK(amount_minor > 0),
        currency TEXT NOT NULL,
        direction TEXT NOT NULL CHECK(direction IN ('debit','credit')),
        transaction_type TEXT NOT NULL,
        occurred_at INTEGER NOT NULL,
        counterparty TEXT,
        reference_id TEXT,
        description TEXT,
        parser_id TEXT NOT NULL,
        parser_version INTEGER NOT NULL,
        confidence INTEGER NOT NULL CHECK(confidence BETWEEN 0 AND 100),
        reason_codes_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        UNIQUE(raw_observation_id, parser_id, parser_version)
      );
      CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        icon_key TEXT NOT NULL,
        color_value INTEGER NOT NULL,
        kind TEXT NOT NULL CHECK(kind IN ('expense','income','both')),
        is_system INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE IF NOT EXISTS category_rules (
        id TEXT PRIMARY KEY,
        normalized_match TEXT NOT NULL UNIQUE,
        category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
        source TEXT NOT NULL CHECK(source IN ('user','system')),
        priority INTEGER NOT NULL DEFAULT 100,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS parser_definitions (
        id TEXT PRIMARY KEY,
        version INTEGER NOT NULL,
        name TEXT NOT NULL,
        country TEXT,
        institution TEXT,
        source_match_json TEXT NOT NULL,
        rules_json TEXT NOT NULL,
        is_builtin INTEGER NOT NULL DEFAULT 0,
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        UNIQUE(id, version)
      );
      CREATE TABLE IF NOT EXISTS import_batches (
        id TEXT PRIMARY KEY,
        file_name TEXT NOT NULL,
        file_sha256 TEXT NOT NULL,
        account_id TEXT NOT NULL REFERENCES accounts(id),
        source_id TEXT REFERENCES sources(id),
        mapping_id TEXT,
        mapping_json TEXT NOT NULL,
        status TEXT NOT NULL,
        row_count INTEGER NOT NULL,
        imported_count INTEGER NOT NULL DEFAULT 0,
        error_count INTEGER NOT NULL DEFAULT 0,
        duplicate_count INTEGER NOT NULL DEFAULT 0,
        started_at INTEGER NOT NULL,
        completed_at INTEGER,
        UNIQUE(file_sha256, account_id)
      );
      CREATE TABLE IF NOT EXISTS import_rows (
        id TEXT PRIMARY KEY,
        batch_id TEXT NOT NULL REFERENCES import_batches(id) ON DELETE CASCADE,
        row_number INTEGER NOT NULL,
        raw_json TEXT NOT NULL,
        normalized_json TEXT,
        status TEXT NOT NULL,
        error_message TEXT,
        raw_observation_id TEXT REFERENCES raw_observations(id),
        UNIQUE(batch_id, row_number)
      );
      CREATE TABLE IF NOT EXISTS csv_mappings (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        account_id TEXT REFERENCES accounts(id) ON DELETE CASCADE,
        header_fingerprint TEXT NOT NULL,
        delimiter TEXT NOT NULL,
        mapping_json TEXT NOT NULL,
        date_format TEXT NOT NULL,
        amount_sign_convention TEXT,
        last_used_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        UNIQUE(account_id, header_fingerprint)
      );
      CREATE TABLE IF NOT EXISTS reconciliation_decisions (
        id TEXT PRIMARY KEY,
        decision_type TEXT NOT NULL,
        evidence_ids_json TEXT NOT NULL,
        transaction_id TEXT REFERENCES transactions(id),
        reason TEXT,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS demo_entities (
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        PRIMARY KEY(entity_type, entity_id)
      );
      CREATE INDEX IF NOT EXISTS source_package_idx ON sources(package_name, enabled);
      CREATE INDEX IF NOT EXISTS account_source_idx ON account_sources(source_id, account_id);
      CREATE INDEX IF NOT EXISTS raw_snapshot_key_idx ON raw_notification_snapshots(notification_key, posted_at);
      CREATE INDEX IF NOT EXISTS evidence_match_idx ON financial_evidence(currency, amount_minor, direction, occurred_at);
      CREATE INDEX IF NOT EXISTS import_hash_idx ON import_batches(file_sha256, account_id);
      CREATE INDEX IF NOT EXISTS category_rule_match_idx ON category_rules(priority DESC, normalized_match);
    ''');

    _addColumn('accounts', 'institution_name', 'TEXT');
    _addColumn('accounts', 'account_suffix', 'TEXT');
    _addColumn(
      'accounts',
      'opening_balance_minor',
      'INTEGER NOT NULL DEFAULT 0',
    );
    _addColumn('accounts', 'updated_at', 'INTEGER');
    _addColumn('raw_observations', 'source_id', 'TEXT REFERENCES sources(id)');
    _addColumn('raw_observations', 'content_hash', 'TEXT');
    _addColumn(
      'raw_observations',
      'import_batch_id',
      'TEXT REFERENCES import_batches(id)',
    );
    _addColumn('raw_observations', 'import_row_number', 'INTEGER');
    _addColumn(
      'raw_observations',
      'payload_json',
      "TEXT NOT NULL DEFAULT '{}'",
    );
    _addColumn(
      'event_candidates',
      'candidate_type',
      "TEXT NOT NULL DEFAULT 'unknown'",
    );
    _addColumn(
      'event_candidates',
      'parser_id',
      "TEXT NOT NULL DEFAULT 'legacy'",
    );
    _addColumn(
      'event_candidates',
      'parser_version',
      'INTEGER NOT NULL DEFAULT 1',
    );
    _addColumn(
      'event_candidates',
      'reasons_json',
      "TEXT NOT NULL DEFAULT '[]'",
    );
    _addColumn('transactions', 'category_id', 'TEXT REFERENCES categories(id)');
    _addColumn('transactions', 'confidence', 'INTEGER NOT NULL DEFAULT 100');
    _addColumn(
      'transactions',
      'reconcile_state',
      "TEXT NOT NULL DEFAULT 'confirmed'",
    );
    _addColumn(
      'transactions',
      'match_reasons_json',
      "TEXT NOT NULL DEFAULT '[]'",
    );
    _addColumn('transactions', 'updated_at', 'INTEGER');
    _addColumn('transactions', 'category_rule_id', 'TEXT');
    _addColumn('transactions', 'note', 'TEXT');

    _db.execute('''
      INSERT OR IGNORE INTO categories(id,name,icon_key,color_value,kind,is_system) VALUES
        ('food','Food & dining','restaurant',4283215696,'expense',1),
        ('groceries','Groceries','shopping_cart',4283215696,'expense',1),
        ('shopping','Shopping','shopping_bag',4294198070,'expense',1),
        ('transport','Transport','directions_car',4280391411,'expense',1),
        ('bills','Bills & utilities','receipt',4294940672,'expense',1),
        ('entertainment','Entertainment','movie',4286208615,'expense',1),
        ('subscriptions','Subscriptions & digital services','subscriptions',4288585374,'expense',1),
        ('health','Health & medical','medical_services',4283215696,'expense',1),
        ('education','Education','school',4280391411,'expense',1),
        ('travel','Travel','flight',4286208615,'expense',1),
        ('personal-care','Personal care','self_care',4294198070,'expense',1),
        ('home','Home','home',4288585374,'expense',1),
        ('insurance','Insurance','verified_user',4280391411,'expense',1),
        ('gifts-charity','Gifts & charity','volunteer_activism',4286208615,'expense',1),
        ('government-tax','Government & taxes','account_balance',4294940672,'expense',1),
        ('cash','Cash withdrawal','payments',4286141768,'expense',1),
        ('fees','Fees','account_balance',4294198070,'expense',1),
        ('income','Income','trending_up',4283215696,'income',1),
        ('transfer','Transfer','swap_horiz',4280391411,'both',1),
        ('other','Other','category',4288585374,'both',1);

      INSERT OR IGNORE INTO sources(
        id,kind,display_name,package_name,enabled,created_at,updated_at
      )
      SELECT 'legacy:' || source_package,'androidApp',source_package,source_package,1,created_at,created_at
      FROM accounts WHERE source_package IS NOT NULL;

      INSERT OR IGNORE INTO account_sources(account_id,source_id,created_at)
      SELECT id,'legacy:' || source_package,created_at
      FROM accounts WHERE source_package IS NOT NULL;
    ''');
    _recategorizeAutomaticTransactions();
    _dedupeRankingVolatileNotificationDuplicates();
    _db.execute('PRAGMA user_version = 3');
  }

  /// One-time cleanup for a fixed bug: the native capture path used to hash
  /// Android's volatile per-notification ranking data into the dedup key, so
  /// re-scanning the same still-visible notification kept inserting it again
  /// as "new" evidence instead of recognizing the duplicate. This removes the
  /// extra copies content-identical duplicates left behind, keeping the
  /// earliest raw_observation per (source, title, body, observed_at) group.
  void _dedupeRankingVolatileNotificationDuplicates() {
    final done = _db.select(
      "SELECT 1 FROM app_settings WHERE key = 'dedup_ranking_volatile_v1'",
    );
    if (done.isNotEmpty) return;
    final groups = _db.select('''
      SELECT source_package, title, body, observed_at, MIN(id) AS keep_id
      FROM raw_observations
      WHERE kind = 'notification'
      GROUP BY source_package, title, body, observed_at
      HAVING COUNT(*) > 1
    ''');
    var removed = 0;
    for (final group in groups) {
      final duplicates = _db.select(
        '''
        SELECT id FROM raw_observations
        WHERE kind = 'notification' AND source_package IS ? AND title IS ?
          AND body = ? AND observed_at = ? AND id != ?
        ''',
        [
          group['source_package'],
          group['title'],
          group['body'],
          group['observed_at'],
          group['keep_id'],
        ],
      );
      for (final row in duplicates) {
        final id = row['id'] as String;
        _db.execute(
          'DELETE FROM transaction_evidence WHERE observation_id = ?',
          [id],
        );
        _db.execute('DELETE FROM raw_observations WHERE id = ?', [id]);
        removed++;
      }
    }
    _db.execute(
      "INSERT OR REPLACE INTO app_settings(key, value) VALUES ('dedup_ranking_volatile_v1', ?)",
      ['$removed'],
    );
    if (removed > 0) _reconcile();
  }

  void _recategorizeAutomaticTransactions() {
    final transactions = _db
        .select(
          "SELECT * FROM transactions WHERE origin='automatic' AND locked=0 AND (category_id IS NULL OR category_id='other')",
        )
        .map(_transactionFromRow)
        .toList(growable: false);
    for (final transaction in transactions) {
      final classification = _automaticCategory(transaction);
      _db.execute(
        'UPDATE transactions SET category_id=?,category=?,category_rule_id=? WHERE id=?',
        [
          classification.categoryId,
          classification.categoryId,
          classification.ruleId,
          transaction.id,
        ],
      );
    }
  }

  void _addColumn(String table, String column, String definition) {
    final exists = _db
        .select('PRAGMA table_info($table)')
        .any((row) => row['name'] == column);
    if (!exists) {
      _db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  LedgerSnapshot snapshot() {
    final accounts = _db
        .select(
          'SELECT * FROM accounts WHERE archived = 0 ORDER BY created_at, name',
        )
        .map(_accountFromRow)
        .toList(growable: false);
    final openingBalances = {
      for (final row in _db.select(
        'SELECT id, opening_balance_minor FROM accounts WHERE archived = 0',
      ))
        row['id'] as String: row['opening_balance_minor'] as int,
    };
    final transactions = _db
        .select(
          'SELECT * FROM transactions WHERE deleted_at IS NULL ORDER BY occurred_at DESC, id',
        )
        .map(_transactionFromRow)
        .toList(growable: false);
    final unparsed =
        _db
                .select(
                  "SELECT COUNT(*) AS count FROM raw_observations WHERE parse_status IN ('review', 'error')",
                )
                .first['count']
            as int;
    final onboarding = _db.select(
      "SELECT value FROM app_settings WHERE key = 'onboarding_complete'",
    );
    return LedgerSnapshot(
      accounts: accounts,
      transactions: transactions,
      openingBalances: openingBalances,
      unparsedCount: unparsed,
      onboardingComplete:
          onboarding.isNotEmpty && onboarding.first['value'] == 'true',
    );
  }

  void completeOnboarding() {
    _db.execute(
      "INSERT OR REPLACE INTO app_settings(key, value) VALUES ('onboarding_complete', 'true')",
    );
  }

  List<StoredCategory> categories() => _db
      .select('SELECT * FROM categories ORDER BY is_system DESC, name')
      .map(
        (row) => StoredCategory(
          id: row['id'] as String,
          name: row['name'] as String,
          iconKey: row['icon_key'] as String,
          colorValue: row['color_value'] as int,
          kind: row['kind'] as String,
        ),
      )
      .toList(growable: false);

  CategoryClassification classifyDescription({
    required String text,
    required TransactionKind kind,
    Iterable<CandidateType> candidateTypes = const [],
  }) {
    final normalized = CategoryClassifier.normalize(text);
    for (final row in _db.select(
      'SELECT normalized_match,category_id,id FROM category_rules ORDER BY priority DESC,updated_at DESC',
    )) {
      final matcher = row['normalized_match'] as String;
      if (matcher.isNotEmpty && ' $normalized '.contains(' $matcher ')) {
        return CategoryClassification(
          categoryId: row['category_id'] as String,
          ruleId: row['id'] as String,
          confidence: 1,
        );
      }
    }
    return const CategoryClassifier().classify(
      text: text,
      kind: kind,
      candidateTypes: candidateTypes,
    );
  }

  String categoryName(String categoryId) {
    final matches = categories().where((category) => category.id == categoryId);
    return matches.isEmpty ? 'Other' : matches.first.name;
  }

  Map<String, String> transactionCategories() => {
    for (final row in _db.select('''
      SELECT t.id,COALESCE(c.name,t.category,'Other') AS category_name
      FROM transactions t LEFT JOIN categories c ON c.id = t.category_id
      WHERE t.deleted_at IS NULL
    '''))
      row['id'] as String: row['category_name'] as String,
  };

  List<Map<String, Object?>> exportTransactions({
    DateTime? from,
    DateTime? to,
    Set<String> accountIds = const {},
    Set<TransactionKind> kinds = const {},
    Set<String> categoryIds = const {},
  }) {
    final where = <String>['t.deleted_at IS NULL'];
    final parameters = <Object?>[];
    if (from != null) {
      where.add('t.occurred_at >= ?');
      parameters.add(from.toUtc().millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('t.occurred_at < ?');
      parameters.add(to.toUtc().millisecondsSinceEpoch);
    }
    if (kinds.isNotEmpty) {
      where.add('t.kind IN (${List.filled(kinds.length, '?').join(',')})');
      parameters.addAll(kinds.map((kind) => kind.name));
    }
    if (categoryIds.isNotEmpty) {
      where.add(
        'COALESCE(t.category_id,t.category) IN (${List.filled(categoryIds.length, '?').join(',')})',
      );
      parameters.addAll(categoryIds);
    }
    if (accountIds.isNotEmpty) {
      final placeholders = List.filled(accountIds.length, '?').join(',');
      where.add(
        '(t.account_id IN ($placeholders) OR t.from_account_id IN ($placeholders) OR t.to_account_id IN ($placeholders))',
      );
      parameters.addAll(accountIds);
      parameters.addAll(accountIds);
      parameters.addAll(accountIds);
    }
    final rows = _db.select('''
      SELECT t.*,c.name AS category_name,
             account.name AS account_name,source_account.name AS from_account_name,
             destination_account.name AS to_account_name
      FROM transactions t
      LEFT JOIN categories c ON c.id=t.category_id
      LEFT JOIN accounts account ON account.id=t.account_id
      LEFT JOIN accounts source_account ON source_account.id=t.from_account_id
      LEFT JOIN accounts destination_account ON destination_account.id=t.to_account_id
      WHERE ${where.join(' AND ')} ORDER BY t.occurred_at,t.id
      ''', parameters);
    return rows
        .map((row) {
          final transactionId = row['id'] as String;
          return <String, Object?>{
            'id': transactionId,
            'occurredAt': DateTime.fromMillisecondsSinceEpoch(
              row['occurred_at'] as int,
              isUtc: true,
            ).toIso8601String(),
            'type': row['kind'],
            'amountMinor': row['amount_minor'],
            'currency': row['currency'],
            'description': row['description'],
            'note': row['note'],
            'categoryId': row['category_id'] ?? row['category'],
            'category': row['category_name'] ?? row['category'] ?? 'Other',
            'accountId': row['account_id'],
            'account': row['account_name'],
            'fromAccountId': row['from_account_id'],
            'fromAccount': row['from_account_name'],
            'toAccountId': row['to_account_id'],
            'toAccount': row['to_account_name'],
            'origin': row['origin'],
            'reconciliationState': row['reconcile_state'],
            'confidence': row['confidence'],
            'evidence': evidenceForTransaction(transactionId)
                .map(
                  (item) => {
                    'id': item.id,
                    'observedAt': item.observedAt.toIso8601String(),
                    'source': item.sourceName,
                    'sourceKind': item.sourceKind,
                    'title': item.rawTitle,
                    'body': item.rawBody,
                    'parserId': item.parserId,
                    'parserVersion': item.parserVersion,
                    'confidence': item.confidence,
                    'reasons': item.reasonCodes,
                    'reference': item.reference,
                  },
                )
                .toList(growable: false),
          };
        })
        .toList(growable: false);
  }

  List<Map<String, Object?>> exportAccounts() => _db
      .select('SELECT * FROM accounts WHERE archived = 0 ORDER BY name')
      .map(
        (row) => <String, Object?>{
          'id': row['id'],
          'name': row['name'],
          'type': row['type'],
          'currency': row['currency'],
          'institution': row['institution_name'],
          'suffix': row['account_suffix'],
          'openingBalanceMinor': row['opening_balance_minor'],
          'sourceIds': _db
              .select(
                'SELECT source_id FROM account_sources WHERE account_id = ?',
                [row['id']],
              )
              .map((source) => source['source_id'])
              .toList(growable: false),
        },
      )
      .toList(growable: false);

  Map<String, int> spendingByCategory({required DateTime month}) {
    final start = DateTime.utc(month.year, month.month);
    final end = DateTime.utc(month.year, month.month + 1);
    return {
      for (final row in _db.select(
        '''
        SELECT COALESCE(c.name,t.category,'Other') AS category_name,
               SUM(t.amount_minor) AS total
        FROM transactions t LEFT JOIN categories c ON c.id = t.category_id
        WHERE t.deleted_at IS NULL AND t.kind = 'expense'
          AND t.occurred_at >= ? AND t.occurred_at < ?
        GROUP BY COALESCE(c.name,t.category,'Other') ORDER BY total DESC
        ''',
        [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      ))
        row['category_name'] as String: row['total'] as int,
    };
  }

  DateTime? get lastCsvImportAt {
    final rows = _db.select(
      "SELECT MAX(completed_at) AS value FROM import_batches WHERE status = 'committed'",
    );
    final value = rows.first['value'] as int?;
    return value == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }

  Map<String, Object?>? rememberedCsvMapping({
    required String accountId,
    required String headerFingerprint,
  }) {
    final rows = _db.select(
      'SELECT * FROM csv_mappings WHERE account_id = ? AND header_fingerprint = ? LIMIT 1',
      [accountId, headerFingerprint],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      'id': row['id'],
      'name': row['name'],
      'delimiter': row['delimiter'],
      'mapping': jsonDecode(row['mapping_json'] as String),
      'dateFormat': row['date_format'],
      'amountSignConvention': row['amount_sign_convention'],
    };
  }

  String rememberCsvMapping({
    required String name,
    required String accountId,
    required String headerFingerprint,
    required String delimiter,
    required Map<String, Object?> mapping,
    required String dateFormat,
    String? amountSignConvention,
  }) {
    final existing = _db.select(
      'SELECT id FROM csv_mappings WHERE account_id = ? AND header_fingerprint = ?',
      [accountId, headerFingerprint],
    );
    final id = existing.isEmpty ? _ids.v4() : existing.first['id'] as String;
    _db.execute(
      '''
      INSERT INTO csv_mappings(
        id,name,account_id,header_fingerprint,delimiter,mapping_json,date_format,
        amount_sign_convention,last_used_at,created_at
      ) VALUES (?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(account_id,header_fingerprint) DO UPDATE SET
        name=excluded.name,delimiter=excluded.delimiter,mapping_json=excluded.mapping_json,
        date_format=excluded.date_format,amount_sign_convention=excluded.amount_sign_convention,
        last_used_at=excluded.last_used_at
      ''',
      [
        id,
        name,
        accountId,
        headerFingerprint,
        delimiter,
        jsonEncode(mapping),
        dateFormat,
        amountSignConvention,
        _now,
        _now,
      ],
    );
    return id;
  }

  bool wasFileImported({
    required String fileSha256,
    required String accountId,
  }) => _db.select(
    "SELECT id FROM import_batches WHERE file_sha256 = ? AND account_id = ? AND status = 'committed' LIMIT 1",
    [fileSha256, accountId],
  ).isNotEmpty;

  bool probableEvidenceDuplicate({
    required String accountId,
    required EntryDirection direction,
    required Money amount,
    required DateTime occurredAt,
    required String description,
    String? reference,
    int? balanceMinor,
    String? dedupeFingerprint,
    String? sourceId,
  }) {
    final start = occurredAt
        .toUtc()
        .subtract(const Duration(days: 1))
        .millisecondsSinceEpoch;
    final end = occurredAt
        .toUtc()
        .add(const Duration(days: 1))
        .millisecondsSinceEpoch;
    final rows = _db.select(
      '''
      SELECT c.reference,c.description,c.occurred_at,r.payload_json
      FROM event_candidates c
      JOIN raw_observations r ON r.id = c.observation_id
      WHERE c.account_id = ? AND c.direction = ? AND c.amount_minor = ?
        AND c.currency = ? AND c.occurred_at BETWEEN ? AND ?
      ''',
      [
        accountId,
        direction.name,
        amount.minorUnits,
        amount.currency,
        start,
        end,
      ],
    );
    final normalizedDescription = _normalizeMatchText(description);
    return rows.any((row) {
      final payload = _tryJsonMap(row['payload_json'] as String?);
      final existingFingerprint = payload?['dedupeFingerprint'] as String?;
      if (dedupeFingerprint != null && existingFingerprint != null) {
        return dedupeFingerprint == existingFingerprint;
      }
      if (reference != null &&
          reference.trim().isNotEmpty &&
          row['reference']?.toString().toLowerCase() ==
              reference.toLowerCase()) {
        return true;
      }
      final existingDescription = _normalizeMatchText(
        row['description'] as String? ?? '',
      );
      final time = DateTime.fromMillisecondsSinceEpoch(
        row['occurred_at'] as int,
        isUtc: true,
      );
      return normalizedDescription.isNotEmpty &&
          normalizedDescription == existingDescription &&
          time.difference(occurredAt.toUtc()).abs() <= const Duration(days: 1);
    });
  }

  Map<String, Object?>? _tryJsonMap(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      return null;
    }
    return null;
  }

  String createImportBatch({
    required String fileName,
    required String fileSha256,
    required String accountId,
    required Map<String, Object?> mapping,
    required int rowCount,
    String? sourceId,
    String? mappingId,
  }) {
    final id = _ids.v4();
    _db.execute(
      '''
      INSERT INTO import_batches(
        id,file_name,file_sha256,account_id,source_id,mapping_id,mapping_json,
        status,row_count,started_at
      ) VALUES (?,?,?,?,?,?,?,'previewed',?,?)
      ''',
      [
        id,
        fileName,
        fileSha256,
        accountId,
        sourceId,
        mappingId,
        jsonEncode(mapping),
        rowCount,
        _now,
      ],
    );
    return id;
  }

  void recordImportRow({
    required String batchId,
    required int rowNumber,
    required Map<String, Object?> raw,
    required String status,
    Map<String, Object?>? normalized,
    String? errorMessage,
    String? rawObservationId,
  }) {
    _db.execute(
      '''
      INSERT OR REPLACE INTO import_rows(
        id,batch_id,row_number,raw_json,normalized_json,status,error_message,raw_observation_id
      ) VALUES (?,?,?,?,?,?,?,?)
      ''',
      [
        '$batchId:$rowNumber',
        batchId,
        rowNumber,
        jsonEncode(raw),
        normalized == null ? null : jsonEncode(normalized),
        status,
        errorMessage,
        rawObservationId,
      ],
    );
  }

  void finishImportBatch({
    required String batchId,
    required int importedCount,
    required int errorCount,
    required int duplicateCount,
  }) {
    _db.execute(
      '''
      UPDATE import_batches SET status='committed',imported_count=?,error_count=?,
        duplicate_count=?,completed_at=? WHERE id=?
      ''',
      [importedCount, errorCount, duplicateCount, _now, batchId],
    );
  }

  String _normalizeMatchText(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  List<StoredSource> sources({String? accountId}) {
    final rows = accountId == null
        ? _db.select('SELECT * FROM sources ORDER BY display_name')
        : _db.select(
            '''
            SELECT s.* FROM sources s
            JOIN account_sources a ON a.source_id = s.id
            WHERE a.account_id = ? ORDER BY a.priority DESC, s.display_name
            ''',
            [accountId],
          );
    return rows.map(_sourceFromRow).toList(growable: false);
  }

  void rememberAndroidSources(Iterable<Map<String, Object?>> sourceRows) {
    for (final row in sourceRows) {
      final packageName = row['packageName'] as String?;
      if (packageName == null || packageName.isEmpty) continue;
      final existing = _db.select(
        'SELECT id FROM sources WHERE package_name = ? AND sender_pattern IS NULL LIMIT 1',
        [packageName],
      );
      final id = existing.isEmpty ? _ids.v4() : existing.first['id'] as String;
      final icon = row['iconPng'];
      _db.execute(
        '''
        INSERT INTO sources(
          id,kind,display_name,package_name,icon_png,enabled,last_event_at,created_at,updated_at
        ) VALUES (?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET
          display_name=excluded.display_name,
          icon_png=COALESCE(excluded.icon_png,sources.icon_png),
          enabled=excluded.enabled,
          last_event_at=COALESCE(excluded.last_event_at,sources.last_event_at),
          updated_at=excluded.updated_at
        ''',
        [
          id,
          'androidApp',
          row['label'] as String? ?? packageName,
          packageName,
          icon is Uint8List
              ? icon
              : icon is List
              ? Uint8List.fromList(icon.cast<int>())
              : null,
          row['configured'] == true ? 1 : 0,
          (row['lastObservedAt'] as num?)?.toInt(),
          _now,
          _now,
        ],
      );
    }
  }

  String addSmsSenderSource({
    required String packageName,
    required String senderPattern,
    required String displayName,
    String? institutionName,
  }) {
    final id = _ids.v4();
    _db.execute(
      '''
      INSERT INTO sources(
        id,kind,display_name,package_name,sender_pattern,institution_name,enabled,created_at,updated_at
      ) VALUES (?,?,?,?,?,?,1,?,?)
      ''',
      [
        id,
        'smsSender',
        displayName,
        packageName,
        senderPattern,
        institutionName,
        _now,
        _now,
      ],
    );
    return id;
  }

  void attachSource({
    required String accountId,
    required String sourceId,
    String? parserDefinitionId,
  }) {
    _db.execute(
      '''
      INSERT INTO account_sources(account_id,source_id,parser_definition_id,created_at)
      VALUES (?,?,?,?)
      ON CONFLICT(account_id,source_id) DO UPDATE SET
        parser_definition_id=excluded.parser_definition_id
      ''',
      [accountId, sourceId, parserDefinitionId, _now],
    );
    final source = _db.select('SELECT package_name FROM sources WHERE id = ?', [
      sourceId,
    ]);
    if (source.isNotEmpty && source.first['package_name'] != null) {
      _reparseSource(source.first['package_name'] as String, accountId);
    }
  }

  void detachSource({required String accountId, required String sourceId}) {
    _db.execute(
      'DELETE FROM account_sources WHERE account_id = ? AND source_id = ?',
      [accountId, sourceId],
    );
  }

  StoredSource _sourceFromRow(Row row) => StoredSource(
    id: row['id'] as String,
    kind: row['kind'] as String,
    displayName: row['display_name'] as String,
    enabled: row['enabled'] == 1,
    packageName: row['package_name'] as String?,
    senderPattern: row['sender_pattern'] as String?,
    institutionName: row['institution_name'] as String?,
    iconPng: row['icon_png'] as Uint8List?,
    lastEventAt: row['last_event_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            row['last_event_at'] as int,
            isUtc: true,
          ),
  );

  String addAccount({
    required String name,
    required AccountType type,
    String currency = 'PKR',
    String? institutionName,
    String? accountSuffix,
    int openingBalanceMinor = 0,
    String? sourcePackage,
    Iterable<String> sourceIds = const [],
  }) {
    final id = _ids.v4();
    _db.execute(
      '''
      INSERT INTO accounts(
        id,name,type,currency,source_package,institution_name,account_suffix,
        opening_balance_minor,archived,created_at,updated_at
      ) VALUES (?,?,?,?,?,?,?,?,0,?,?)
      ''',
      [
        id,
        name.trim(),
        type.name,
        currency.toUpperCase(),
        sourcePackage,
        institutionName?.trim(),
        accountSuffix?.trim(),
        openingBalanceMinor,
        _now,
        _now,
      ],
    );
    for (final sourceId in sourceIds) {
      attachSource(accountId: id, sourceId: sourceId);
    }
    if (sourcePackage != null) {
      final source = _db.select(
        'SELECT id FROM sources WHERE package_name = ? AND sender_pattern IS NULL LIMIT 1',
        [sourcePackage],
      );
      if (source.isNotEmpty) {
        attachSource(accountId: id, sourceId: source.first['id'] as String);
      } else {
        _reparseSource(sourcePackage, id);
      }
    }
    return id;
  }

  void updateAccountSource(String accountId, String? packageName) {
    _db.execute(
      'UPDATE accounts SET source_package = NULL WHERE source_package = ?',
      [packageName],
    );
    _db.execute('UPDATE accounts SET source_package = ? WHERE id = ?', [
      packageName,
      accountId,
    ]);
    if (packageName != null) _reparseSource(packageName, accountId);
  }

  void updateAccount({
    required String id,
    required String name,
    required AccountType type,
    String? institutionName,
    String? accountSuffix,
  }) {
    _db.execute(
      'UPDATE accounts SET name=?, type=?, institution_name=?, account_suffix=?, updated_at=? WHERE id=?',
      [
        name.trim(),
        type.name,
        institutionName?.trim(),
        accountSuffix?.trim(),
        _now,
        id,
      ],
    );
  }

  void setAccountCurrentBalance({
    required String id,
    required int currentBalanceMinor,
    required int targetBalanceMinor,
  }) {
    final account = _db.select(
      'SELECT id FROM accounts WHERE id = ? AND archived = 0 LIMIT 1',
      [id],
    );
    if (account.isEmpty) throw StateError('Account was not found.');
    final difference = targetBalanceMinor - currentBalanceMinor;
    _db.execute(
      'UPDATE accounts SET opening_balance_minor = opening_balance_minor + ?, updated_at = ? WHERE id = ?',
      [difference, _now, id],
    );
  }

  void archiveAccount(String id) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      _db.execute(
        'UPDATE accounts SET archived = 1, source_package = NULL, updated_at = ? WHERE id = ?',
        [_now, id],
      );
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  Account? latestArchivedAccount() {
    final rows = _db.select(
      'SELECT * FROM accounts WHERE archived = 1 ORDER BY updated_at DESC, created_at DESC LIMIT 1',
    );
    return rows.isEmpty ? null : _accountFromRow(rows.first);
  }

  void restoreAccount(String id) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      _db.execute(
        'UPDATE accounts SET archived = 0, updated_at = ? WHERE id = ? AND archived = 1',
        [_now, id],
      );
      // Older builds detached sources while archiving. Recover every package
      // already observed for this account without inventing new mappings.
      _db.execute(
        '''
        INSERT OR IGNORE INTO account_sources(account_id,source_id,created_at)
        SELECT ?, source.id, ? FROM sources source
        WHERE source.package_name IN (
          SELECT DISTINCT source_package FROM raw_observations
          WHERE account_id = ? AND source_package IS NOT NULL
        )
        ''',
        [id, _now, id],
      );
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  bool ingestNotification(Map<String, Object?> envelope) {
    final stablePayload = Map<String, Object?>.from(envelope)
      ..remove('id')
      ..remove('capturedAt')
      ..remove('capturedAtEpochMs');
    final payloadJson = jsonEncode(stablePayload);
    final contentHash =
        envelope['contentHash'] as String? ??
        sha256.convert(utf8.encode(payloadJson)).toString();
    final notificationKey =
        envelope['notificationKey'] as String? ??
        'unknown:${envelope['packageName']}';
    final externalId =
        envelope['snapshotHash'] as String? ?? '$notificationKey:$contentHash';
    final packageName = envelope['packageName'] as String?;
    final existing = _db.select(
      "SELECT id FROM raw_observations WHERE kind = 'notification' AND external_id = ?",
      [externalId],
    );
    if (existing.isNotEmpty) return true;
    final text = _notificationText(envelope);
    final sourceAccount = packageName == null
        ? null
        : _matchSourceAccount(packageName, text);
    final sourceId = sourceAccount?['source_id'] as String?;
    final accountId = sourceAccount?['account_id'] as String?;
    final postedAt =
        (envelope['postedAt'] as num?)?.toInt() ??
        (envelope['postedAtEpochMs'] as num?)?.toInt() ??
        _now;
    final raw = RawObservation(
      id: _ids.v4(),
      kind: ObservationKind.notification,
      observedAt: DateTime.fromMillisecondsSinceEpoch(postedAt, isUtc: true),
      title: envelope['title'] as String?,
      body: text,
      sourcePackage: packageName,
      accountId: accountId,
      externalId: externalId,
      sourceId: sourceId,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
        (envelope['capturedAt'] as num?)?.toInt() ??
            (envelope['capturedAtEpochMs'] as num?)?.toInt() ??
            _now,
        isUtc: true,
      ),
      snapshot: packageName == null
          ? null
          : RawNotificationSnapshot(
              packageName: packageName,
              postedAt: DateTime.fromMillisecondsSinceEpoch(
                postedAt,
                isUtc: true,
              ),
              notificationKey: notificationKey,
              title: envelope['title'] as String?,
              text: (envelope['text'] ?? envelope['body']) as String?,
              bigText: envelope['bigText'] as String?,
              subText: envelope['subText'] as String?,
              sender: _notificationSender(envelope),
            ),
    );
    _insertRawAndParse(
      raw,
      sourceId: sourceId,
      payloadJson: payloadJson,
      contentHash: contentHash,
    );
    final sequence =
        (_db.select(
              'SELECT COUNT(*) AS count FROM raw_notification_snapshots WHERE notification_key = ?',
              [notificationKey],
            ).first['count']
            as int) +
        1;
    _db.execute(
      '''
      INSERT OR IGNORE INTO raw_notification_snapshots(
        id,raw_observation_id,notification_key,snapshot_sequence,content_hash,
        posted_at,captured_at,payload_json
      ) VALUES (?,?,?,?,?,?,?,?)
      ''',
      [
        _ids.v4(),
        raw.id,
        notificationKey,
        sequence,
        contentHash,
        postedAt,
        (envelope['capturedAt'] as num?)?.toInt() ??
            (envelope['capturedAtEpochMs'] as num?)?.toInt() ??
            _now,
        jsonEncode(envelope),
      ],
    );
    if (sourceId != null) {
      _db.execute(
        'UPDATE sources SET last_event_at = ?, updated_at = ? WHERE id = ?',
        [_now, _now, sourceId],
      );
    }
    _reconcile();
    return true;
  }

  Row? _matchSourceAccount(String packageName, String notificationText) {
    final candidates = _db.select(
      '''
      SELECT s.id AS source_id,s.sender_pattern,a.account_id
      FROM sources s
      JOIN account_sources a ON a.source_id = s.id
      JOIN accounts account ON account.id = a.account_id
      WHERE s.package_name = ? AND s.enabled = 1 AND account.archived = 0
      ORDER BY CASE WHEN s.sender_pattern IS NULL THEN 0 ELSE 1 END DESC,
               a.priority DESC
      ''',
      [packageName],
    );
    final matched = candidates.where((row) {
      final pattern = row['sender_pattern'] as String?;
      if (pattern == null || pattern.isEmpty) return true;
      try {
        return RegExp(pattern, caseSensitive: false).hasMatch(notificationText);
      } on FormatException {
        return notificationText.toLowerCase().contains(pattern.toLowerCase());
      }
    }).toList();
    if (matched.isEmpty) return null;
    final specific = matched
        .where((row) => row['sender_pattern'] != null)
        .toList();
    if (specific.length == 1) return specific.single;
    final accountIds = matched.map((row) => row['account_id']).toSet();
    return accountIds.length == 1 ? matched.first : null;
  }

  String _notificationText(Map<String, Object?> envelope) {
    final values = <String>[];
    void collect(Object? value) {
      if (value is String && value.trim().isNotEmpty) {
        values.add(value.trim());
      } else if (value is Iterable) {
        for (final item in value) {
          collect(item);
        }
      } else if (value is Map) {
        for (final item in value.values) {
          collect(item);
        }
      }
    }

    for (final key in const [
      'title',
      'bigTitle',
      'body',
      'text',
      'bigText',
      'subText',
      'summaryText',
      'infoText',
      'textLines',
      'messages',
    ]) {
      collect(envelope[key]);
    }
    return values.toSet().join(' ');
  }

  String? _notificationSender(Map<String, Object?> envelope) {
    final direct = envelope['sender'] as String?;
    if (direct?.trim().isNotEmpty == true) return direct!.trim();
    final messages = envelope['messages'];
    if (messages is Iterable) {
      for (final message in messages) {
        if (message is Map && message['sender'] is String) {
          final sender = (message['sender'] as String).trim();
          if (sender.isNotEmpty) return sender;
        }
      }
    }
    final notification = envelope['notification'];
    if (notification is Map && notification['messages'] is Iterable) {
      for (final message in notification['messages'] as Iterable) {
        if (message is Map && message['sender'] is String) {
          final sender = (message['sender'] as String).trim();
          if (sender.isNotEmpty) return sender;
        }
      }
    }
    return null;
  }

  void _insertRawAndParse(
    RawObservation raw, {
    String? sourceId,
    String payloadJson = '{}',
    String? contentHash,
  }) {
    final result = const NotificationParser().parseDetailed(raw);
    final candidate = result.candidate;
    debugPrint(
      'SpendWiseNotif: parse pkg=${raw.sourcePackage} status=${result.status} '
      'accountId=${raw.accountId} reasons=${result.reasons}',
    );
    final storedStatus = switch (result.status) {
      ParseStatus.parsed => 'parsed',
      ParseStatus.invalid => 'error',
      ParseStatus.unsupported || ParseStatus.ambiguous => 'review',
    };
    _db.execute(
      'INSERT OR IGNORE INTO raw_observations(id,kind,external_id,source_package,account_id,observed_at,title,body,parse_status,parse_error,source_id,content_hash,payload_json) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        raw.id,
        raw.kind.name,
        raw.externalId ?? raw.id,
        raw.sourcePackage,
        raw.accountId,
        raw.observedAt.toUtc().millisecondsSinceEpoch,
        raw.title,
        raw.body,
        storedStatus,
        candidate == null ? result.reasons.join(' ') : null,
        sourceId,
        contentHash,
        payloadJson,
      ],
    );
    if (candidate != null) _insertCandidate(candidate);
  }

  void _insertCandidate(EventCandidate item) {
    _db.execute(
      'INSERT OR REPLACE INTO event_candidates(id,observation_id,account_id,direction,amount_minor,currency,occurred_at,counterparty,reference,description,confidence,candidate_type,parser_id,parser_version,reasons_json) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        item.id,
        item.observation.id,
        item.accountId,
        item.direction.name,
        item.amount.minorUnits,
        item.amount.currency,
        item.occurredAt.toUtc().millisecondsSinceEpoch,
        item.counterparty,
        item.reference,
        item.description,
        item.confidence,
        item.type.name,
        item.parserId,
        item.parserVersion,
        jsonEncode(item.reasons),
      ],
    );
    _db.execute(
      '''
      INSERT OR REPLACE INTO financial_evidence(
        id,raw_observation_id,source_id,account_id,amount_minor,currency,direction,
        transaction_type,occurred_at,counterparty,reference_id,description,
        parser_id,parser_version,confidence,reason_codes_json,created_at
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ''',
      [
        'evidence:${item.id}',
        item.observation.id,
        item.observation.sourceId,
        item.accountId,
        item.amount.minorUnits,
        item.amount.currency,
        item.direction.name,
        item.type.name,
        item.occurredAt.toUtc().millisecondsSinceEpoch,
        item.counterparty,
        item.reference,
        item.description,
        item.parserId,
        item.parserVersion,
        (item.confidence * 100).round().clamp(0, 100),
        jsonEncode(item.reasons),
        _now,
      ],
    );
  }

  void _reparseSource(String packageName, String accountId) {
    final rows = _db.select(
      "SELECT * FROM raw_observations WHERE source_package = ? AND parse_status != 'parsed'",
      [packageName],
    );
    for (final row in rows) {
      final raw = _rawFromRow(row, accountOverride: accountId);
      final candidate = const NotificationParser().parseDetailed(raw).candidate;
      if (candidate == null) continue;
      _db.execute(
        "UPDATE raw_observations SET account_id = ?, parse_status = 'parsed', parse_error = NULL WHERE id = ?",
        [accountId, raw.id],
      );
      _insertCandidate(candidate);
    }
    _reconcile();
  }

  String addManualTransaction({
    required TransactionKind kind,
    required int amountMinor,
    required DateTime occurredAt,
    String? accountId,
    String? fromAccountId,
    String? toAccountId,
    String? description,
    String? note,
    String currency = 'PKR',
    String? categoryId,
  }) {
    if (amountMinor <= 0) throw ArgumentError.value(amountMinor, 'amountMinor');
    final id = _ids.v4();
    _db.execute(
      'INSERT INTO transactions(id,kind,amount_minor,currency,occurred_at,account_id,from_account_id,to_account_id,description,note,needs_review,locked,origin,category_id,category,reconcile_state,confidence,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        id,
        kind.name,
        amountMinor,
        currency,
        occurredAt.toUtc().millisecondsSinceEpoch,
        accountId,
        fromAccountId,
        toAccountId,
        description,
        note?.trim().isEmpty == true ? null : note?.trim(),
        0,
        1,
        TransactionOrigin.manual.name,
        categoryId,
        categoryId,
        'confirmed',
        100,
        _now,
      ],
    );
    return id;
  }

  bool get demoDataEnabled => _db
      .select("SELECT value FROM app_settings WHERE key = 'demo_data_enabled'")
      .any((row) => row['value'] == 'true');

  bool get showSavingsOnHome => _db
      .select("SELECT value FROM app_settings WHERE key = 'show_savings_home'")
      .any((row) => row['value'] == 'true');

  void setShowSavingsOnHome(bool enabled) {
    _db.execute(
      "INSERT OR REPLACE INTO app_settings(key,value) VALUES ('show_savings_home',?)",
      [enabled ? 'true' : 'false'],
    );
  }

  void seedDemoData() {
    if (demoDataEnabled) return;
    _db.execute('BEGIN IMMEDIATE');
    try {
      final bank = addAccount(
        name: 'Demo Meezan Current',
        type: AccountType.bank,
        institutionName: 'Meezan Bank',
        accountSuffix: '4821',
        openingBalanceMinor: 18500000,
      );
      final wallet = addAccount(
        name: 'Demo SadaPay Wallet',
        type: AccountType.wallet,
        institutionName: 'SadaPay',
        accountSuffix: '9012',
        openingBalanceMinor: 2450000,
      );
      final now = DateTime.now();
      final transactionIds = <String>[
        addManualTransaction(
          kind: TransactionKind.income,
          amountMinor: 15260000,
          occurredAt: DateTime(now.year, now.month, 1, 9),
          accountId: bank,
          description: 'Demo salary',
          categoryId: 'income',
        ),
        addManualTransaction(
          kind: TransactionKind.expense,
          amountMinor: 425000,
          occurredAt: now.subtract(const Duration(days: 1, hours: 2)),
          accountId: bank,
          description: 'Demo Foodpanda order',
          categoryId: 'food',
        ),
        addManualTransaction(
          kind: TransactionKind.expense,
          amountMinor: 600000,
          occurredAt: now.subtract(const Duration(days: 2)),
          accountId: bank,
          description: 'Demo fuel',
          categoryId: 'transport',
        ),
        addManualTransaction(
          kind: TransactionKind.transfer,
          amountMinor: 1000000,
          occurredAt: now.subtract(const Duration(days: 3)),
          fromAccountId: bank,
          toAccountId: wallet,
          description: 'Demo wallet top-up',
          categoryId: 'transfer',
        ),
        addManualTransaction(
          kind: TransactionKind.expense,
          amountMinor: 1225000,
          occurredAt: now.subtract(const Duration(days: 4)),
          accountId: wallet,
          description: 'Demo electricity bill',
          categoryId: 'bills',
        ),
      ];
      for (final id in [bank, wallet]) {
        _db.execute(
          "INSERT INTO demo_entities(entity_type,entity_id) VALUES ('account',?)",
          [id],
        );
      }
      for (final id in transactionIds) {
        _db.execute(
          "INSERT INTO demo_entities(entity_type,entity_id) VALUES ('transaction',?)",
          [id],
        );
      }
      _db.execute(
        "INSERT OR REPLACE INTO app_settings(key,value) VALUES ('demo_data_enabled','true')",
      );
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void removeDemoData() {
    _db.execute('BEGIN IMMEDIATE');
    try {
      _db.execute(
        "DELETE FROM transactions WHERE id IN (SELECT entity_id FROM demo_entities WHERE entity_type='transaction')",
      );
      _db.execute(
        "DELETE FROM accounts WHERE id IN (SELECT entity_id FROM demo_entities WHERE entity_type='account')",
      );
      _db.execute('DELETE FROM demo_entities');
      _db.execute(
        "INSERT OR REPLACE INTO app_settings(key,value) VALUES ('demo_data_enabled','false')",
      );
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void deleteTransaction(String id) {
    _db.execute('UPDATE transactions SET deleted_at = ? WHERE id = ?', [
      _now,
      id,
    ]);
  }

  void confirmTransaction(String id) {
    _db.execute(
      'UPDATE transactions SET needs_review = 0, locked = 1 WHERE id = ?',
      [id],
    );
  }

  List<StoredEvidence> evidenceForTransaction(String transactionId) {
    final rows = _db.select(
      '''
      SELECT r.id,r.observed_at,r.title,r.body,r.payload_json,
             COALESCE(s.display_name,r.source_package,'Manual') AS source_name,
             COALESCE(s.kind,r.kind) AS source_kind,
             c.reference,c.confidence
      FROM transaction_evidence link
      JOIN raw_observations r ON r.id = link.observation_id
      LEFT JOIN sources s ON s.id = r.source_id
      LEFT JOIN event_candidates c ON c.observation_id = r.id
      WHERE link.transaction_id = ?
      ORDER BY r.observed_at, r.id
      ''',
      [transactionId],
    );
    return rows
        .map(
          (row) => StoredEvidence(
            id: row['id'] as String,
            observedAt: DateTime.fromMillisecondsSinceEpoch(
              row['observed_at'] as int,
              isUtc: true,
            ),
            sourceName: row['source_name'] as String,
            sourceKind: row['source_kind'] as String,
            rawTitle: row['title'] as String?,
            rawBody: row['body'] as String,
            parserId: 'pakistan.generic.notification',
            parserVersion: 1,
            confidence: (((row['confidence'] as num?)?.toDouble() ?? 1) * 100)
                .round()
                .clamp(0, 100),
            reasonCodes: [
              if (row['reference'] != null) 'matching_reference',
              'amount_currency_direction',
            ],
            payloadJson: row['payload_json'] as String? ?? '{}',
            reference: row['reference'] as String?,
          ),
        )
        .toList(growable: false);
  }

  void updateTransaction({
    required String id,
    required TransactionKind kind,
    required String description,
    required DateTime occurredAt,
    required int amountMinor,
    String currency = 'PKR',
    String? accountId,
    String? fromAccountId,
    String? toAccountId,
    String? categoryId,
  }) {
    if (amountMinor <= 0) throw ArgumentError.value(amountMinor, 'amountMinor');
    if (kind == TransactionKind.transfer &&
        (fromAccountId == null ||
            toAccountId == null ||
            fromAccountId == toAccountId)) {
      throw ArgumentError('Transfers require two different accounts.');
    }
    final learnedRuleId = categoryId == null
        ? null
        : _rememberUserCategoryRule(
            transactionId: id,
            categoryId: categoryId,
            fallbackDescription: description,
          );
    _db.execute(
      '''
      UPDATE transactions SET
        kind=?,amount_minor=?,currency=?,occurred_at=?,account_id=?,
        from_account_id=?,to_account_id=?,description=?,category_id=?,
        category=?,category_rule_id=?,needs_review=0,locked=1,reconcile_state='confirmed',
        confidence=100,updated_at=?
      WHERE id=?
      ''',
      [
        kind.name,
        amountMinor,
        currency,
        occurredAt.toUtc().millisecondsSinceEpoch,
        kind == TransactionKind.transfer ? null : accountId,
        kind == TransactionKind.transfer ? fromAccountId : null,
        kind == TransactionKind.transfer ? toAccountId : null,
        description.trim(),
        categoryId,
        categoryId,
        learnedRuleId,
        _now,
        id,
      ],
    );
  }

  String? _rememberUserCategoryRule({
    required String transactionId,
    required String categoryId,
    required String fallbackDescription,
  }) {
    final transaction = _db.select(
      'SELECT origin FROM transactions WHERE id = ? LIMIT 1',
      [transactionId],
    );
    String? merchant;
    if (transaction.isNotEmpty &&
        transaction.first['origin'] == TransactionOrigin.manual.name) {
      merchant = fallbackDescription;
    } else {
      final candidates = _db.select(
        '''
            SELECT c.counterparty FROM transaction_evidence link
            JOIN event_candidates c ON c.observation_id=link.observation_id
            WHERE link.transaction_id=? AND c.counterparty IS NOT NULL
              AND TRIM(c.counterparty) != '' LIMIT 1
            ''',
        [transactionId],
      );
      merchant = candidates.isEmpty
          ? null
          : candidates.first['counterparty'] as String?;
    }
    final normalized = CategoryClassifier.normalize(merchant ?? '');
    if (normalized.length < 2 || normalized.length > 80) return null;
    final id = 'user-category:${sha256.convert(utf8.encode(normalized))}';
    _db.execute(
      '''
      INSERT INTO category_rules(
        id,normalized_match,category_id,source,priority,created_at,updated_at
      ) VALUES (?,? ,?,'user',1000,?,?)
      ON CONFLICT(normalized_match) DO UPDATE SET
        category_id=excluded.category_id,source='user',priority=1000,
        updated_at=excluded.updated_at
      ''',
      [id, normalized, categoryId, _now, _now],
    );
    return id;
  }

  void dismissUnparsed() {
    _db.execute(
      "UPDATE raw_observations SET parse_status = 'ignored' WHERE parse_status IN ('review', 'error')",
    );
  }

  String? ingestCsvCandidate({
    required String batchId,
    required int rowNumber,
    required String accountId,
    required EntryDirection direction,
    required Money amount,
    required DateTime occurredAt,
    required String description,
    String? reference,
    int? balanceMinor,
    String? dedupeFingerprint,
    String? sourceId,
  }) {
    final externalId = '$batchId:$rowNumber';
    final existing = _db.select(
      "SELECT id FROM raw_observations WHERE kind = 'csvImport' AND external_id = ?",
      [externalId],
    );
    if (existing.isNotEmpty) return null;
    final raw = RawObservation(
      id: _ids.v4(),
      kind: ObservationKind.csvImport,
      observedAt: occurredAt,
      body: description,
      accountId: accountId,
      externalId: externalId,
      importBatchId: batchId,
      importRowNumber: rowNumber,
      sourceId: sourceId,
      metadata: dedupeFingerprint == null
          ? const {}
          : {'dedupeFingerprint': dedupeFingerprint},
    );
    _db.execute(
      'INSERT INTO raw_observations(id,kind,external_id,account_id,observed_at,body,parse_status,payload_json,content_hash,source_id,import_batch_id,import_row_number) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        raw.id,
        raw.kind.name,
        raw.externalId,
        accountId,
        occurredAt.toUtc().millisecondsSinceEpoch,
        description,
        'parsed',
        jsonEncode({
          'batchId': batchId,
          'rowNumber': rowNumber,
          'description': description,
          'reference': reference,
          'balanceMinor': balanceMinor,
          'dedupeFingerprint': dedupeFingerprint,
        }),
        sha256.convert(utf8.encode('$externalId|$description')).toString(),
        sourceId,
        null,
        rowNumber,
      ],
    );
    _insertCandidate(
      EventCandidate(
        id: 'candidate:${raw.id}',
        observation: raw,
        accountId: accountId,
        amount: amount,
        direction: direction,
        occurredAt: occurredAt,
        description: description,
        reference: reference,
        type: direction == EntryDirection.debit
            ? CandidateType.purchase
            : CandidateType.income,
        parserId: 'csv.user-mapping',
        parserVersion: 1,
        reasons: const ['Mapped and approved during CSV import preview.'],
      ),
    );
    return raw.id;
  }

  void finishBatch({bool insideTransaction = false}) =>
      _reconcile(manageTransaction: !insideTransaction);

  void _reconcile({bool manageTransaction = true}) {
    final candidates = _db
        .select('''
      SELECT c.*, r.kind AS raw_kind, r.external_id, r.source_package,
             r.source_id,r.observed_at, r.title, r.body,r.payload_json
      FROM event_candidates c JOIN raw_observations r ON r.id = c.observation_id
    ''')
        .map((row) {
          final payload = jsonDecode(row['payload_json'] as String) as Map;
          final raw = RawObservation(
            id: row['observation_id'] as String,
            kind: ObservationKind.values.byName(row['raw_kind'] as String),
            observedAt: DateTime.fromMillisecondsSinceEpoch(
              row['observed_at'] as int,
              isUtc: true,
            ),
            title: row['title'] as String?,
            body: row['body'] as String,
            sourcePackage: row['source_package'] as String?,
            accountId: row['account_id'] as String,
            externalId: row['external_id'] as String,
            sourceId: row['source_id'] as String?,
            metadata: {
              if (payload['dedupeFingerprint'] is String)
                'dedupeFingerprint': payload['dedupeFingerprint'] as String,
            },
          );
          return EventCandidate(
            id: row['id'] as String,
            observation: raw,
            accountId: row['account_id'] as String,
            amount: Money(
              minorUnits: row['amount_minor'] as int,
              currency: row['currency'] as String,
            ),
            direction: EntryDirection.values.byName(row['direction'] as String),
            occurredAt: DateTime.fromMillisecondsSinceEpoch(
              row['occurred_at'] as int,
              isUtc: true,
            ),
            counterparty: row['counterparty'] as String?,
            reference: row['reference'] as String?,
            description: row['description'] as String?,
            confidence: (row['confidence'] as num).toDouble(),
            type: CandidateType.values.byName(row['candidate_type'] as String),
            parserId: row['parser_id'] as String,
            parserVersion: row['parser_version'] as int,
            reasons: (jsonDecode(row['reasons_json'] as String) as List)
                .cast<String>(),
          );
        })
        .toList();
    final existingLocked = _db
        .select(
          "SELECT * FROM transactions WHERE locked = 1 OR origin = 'manual'",
        )
        .map(_transactionFromRow)
        .toList();
    final result = const Reconciler().reconcile(
      candidates,
      existing: existingLocked,
    );
    if (manageTransaction) _db.execute('BEGIN IMMEDIATE');
    try {
      _db.execute(
        "DELETE FROM transactions WHERE origin = 'automatic' AND locked = 0",
      );
      for (final item in result.transactions.where(
        (item) => item.origin == TransactionOrigin.automatic,
      )) {
        final locked = _db.select(
          'SELECT 1 FROM transactions WHERE id = ? AND locked = 1 LIMIT 1',
          [item.id],
        );
        if (locked.isNotEmpty) continue;
        _insertTransaction(item);
      }
      for (final decision in result.decisions) {
        _db.execute(
          '''
          INSERT OR REPLACE INTO reconciliation_decisions(
            id,decision_type,evidence_ids_json,reason,created_at
          ) VALUES (?,?,?,?,?)
          ''',
          [
            decision.id,
            decision.type.name,
            jsonEncode(decision.candidateIds.toList()..sort()),
            jsonEncode({
              'score': decision.score,
              'reasons': decision.reasons,
              'reversible': decision.reversible,
            }),
            _now,
          ],
        );
      }
      if (manageTransaction) _db.execute('COMMIT');
    } catch (_) {
      if (manageTransaction) _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _insertTransaction(CanonicalTransaction item) {
    final classification = _automaticCategory(item);
    _db.execute(
      'INSERT OR REPLACE INTO transactions(id,kind,amount_minor,currency,occurred_at,account_id,from_account_id,to_account_id,description,needs_review,locked,origin,category_id,category,category_rule_id,reconcile_state,confidence,match_reasons_json,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        item.id,
        item.kind.name,
        item.amount.minorUnits,
        item.amount.currency,
        item.occurredAt.toUtc().millisecondsSinceEpoch,
        item.accountId,
        item.fromAccountId,
        item.toAccountId,
        item.description,
        item.needsReview ? 1 : 0,
        item.locked ? 1 : 0,
        item.origin.name,
        classification.categoryId,
        classification.categoryId,
        classification.ruleId,
        item.effectiveReconciliationState.name,
        item.effectiveReconciliationState == ReconciliationState.confirmed
            ? 100
            : item.effectiveReconciliationState == ReconciliationState.probable
            ? 75
            : 50,
        jsonEncode(item.decisionIds.toList()),
        _now,
      ],
    );
    for (final evidenceId in item.evidenceIds) {
      _db.execute(
        'INSERT OR IGNORE INTO transaction_evidence(transaction_id, observation_id) VALUES (?,?)',
        [item.id, evidenceId],
      );
    }
  }

  CategoryClassification _automaticCategory(CanonicalTransaction item) {
    final ids = item.evidenceIds.toList(growable: false);
    final text = <String>[item.description ?? ''];
    final types = <CandidateType>[];
    if (ids.isNotEmpty) {
      final placeholders = List.filled(ids.length, '?').join(',');
      for (final row in _db.select('''
        SELECT r.title,r.body,c.counterparty,c.description,c.candidate_type
        FROM raw_observations r
        LEFT JOIN event_candidates c ON c.observation_id=r.id
        WHERE r.id IN ($placeholders)
        ''', ids)) {
        text.addAll([
          row['title'] as String? ?? '',
          row['body'] as String? ?? '',
          row['counterparty'] as String? ?? '',
          row['description'] as String? ?? '',
        ]);
        final type = row['candidate_type'] as String?;
        if (type != null) types.add(CandidateType.values.byName(type));
      }
    }
    return classifyDescription(
      text: text.join(' '),
      kind: item.kind,
      candidateTypes: types,
    );
  }

  Account _accountFromRow(Row row) => Account(
    id: row['id'] as String,
    name: row['name'] as String,
    type: AccountType.values.byName(row['type'] as String),
    currency: row['currency'] as String,
    notificationPackages: row['source_package'] == null
        ? const {}
        : {row['source_package'] as String},
    archived: row['archived'] == 1,
  );

  CanonicalTransaction _transactionFromRow(Row row) => CanonicalTransaction(
    id: row['id'] as String,
    kind: TransactionKind.values.byName(row['kind'] as String),
    amount: Money(
      minorUnits: row['amount_minor'] as int,
      currency: row['currency'] as String,
    ),
    occurredAt: DateTime.fromMillisecondsSinceEpoch(
      row['occurred_at'] as int,
      isUtc: true,
    ),
    accountId: row['account_id'] as String?,
    fromAccountId: row['from_account_id'] as String?,
    toAccountId: row['to_account_id'] as String?,
    description: row['description'] as String?,
    note: row['note'] as String?,
    needsReview: row['needs_review'] == 1,
    locked: row['locked'] == 1,
    origin: TransactionOrigin.values.byName(row['origin'] as String),
    reconciliationState: ReconciliationState.values.byName(
      row['reconcile_state'] as String? ??
          (row['needs_review'] == 1 ? 'needsReview' : 'confirmed'),
    ),
    evidenceIds: _db
        .select(
          'SELECT observation_id FROM transaction_evidence WHERE transaction_id = ?',
          [row['id']],
        )
        .map((item) => item['observation_id'] as String)
        .toSet(),
  );

  RawObservation _rawFromRow(Row row, {String? accountOverride}) =>
      RawObservation(
        id: row['id'] as String,
        kind: ObservationKind.values.byName(row['kind'] as String),
        observedAt: DateTime.fromMillisecondsSinceEpoch(
          row['observed_at'] as int,
          isUtc: true,
        ),
        body: row['body'] as String,
        sourcePackage: row['source_package'] as String?,
        title: row['title'] as String?,
        accountId: accountOverride ?? row['account_id'] as String?,
        externalId: row['external_id'] as String,
        sourceId: row['source_id'] as String?,
        importBatchId: row['import_batch_id'] as String?,
        importRowNumber: row['import_row_number'] as int?,
      );

  Future<void> wipe() async {
    _db.close();
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('$_path$suffix');
      if (await file.exists()) await file.delete();
    }
    await _secureStorage.delete(key: _keyName);
  }

  void close() => _db.close();

  static int get _now => DateTime.now().toUtc().millisecondsSinceEpoch;
}

extension on Iterable<Object?> {
  Object? get firstOrNull => isEmpty ? null : first;
}
