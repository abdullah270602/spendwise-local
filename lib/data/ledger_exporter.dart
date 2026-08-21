import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';

import '../domain/domain.dart';
import 'local_ledger.dart';

final class LedgerExportFilter {
  const LedgerExportFilter({
    this.from,
    this.to,
    this.accountIds = const {},
    this.kinds = const {},
    this.categoryIds = const {},
  });

  final DateTime? from;
  final DateTime? to;
  final Set<String> accountIds;
  final Set<TransactionKind> kinds;
  final Set<String> categoryIds;
}

final class LedgerExporter {
  const LedgerExporter(this.ledger);
  final LocalLedger ledger;

  Uint8List csv(LedgerExportFilter filter) {
    final transactions = _rows(filter);
    final rows = <List<Object?>>[
      [
        'Date',
        'Type',
        'Description',
        'Amount minor units',
        'Currency',
        'Category',
        'Account',
        'From account',
        'To account',
        'Evidence count',
        'Reconciliation state',
      ],
      for (final item in transactions)
        [
          item['occurredAt'],
          item['type'],
          item['description'],
          item['amountMinor'],
          item['currency'],
          item['category'],
          item['account'],
          item['fromAccount'],
          item['toAccount'],
          (item['evidence'] as List).length,
          item['reconciliationState'],
        ],
    ];
    return Uint8List.fromList(utf8.encode(Csv(addBom: true).encode(rows)));
  }

  Uint8List jsonBackup(LedgerExportFilter filter) {
    final payload = {
      'format': 'spendwise-portable-backup',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'warning':
          'This file contains plaintext financial data and raw evidence.',
      'accounts': ledger.exportAccounts(),
      'sources': ledger
          .sources()
          .map(
            (source) => {
              'id': source.id,
              'kind': source.kind,
              'name': source.displayName,
              'packageName': source.packageName,
              'senderPattern': source.senderPattern,
              'institution': source.institutionName,
              'enabled': source.enabled,
              'lastEventAt': source.lastEventAt?.toIso8601String(),
            },
          )
          .toList(growable: false),
      'transactions': _rows(filter),
    };
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
    );
  }

  List<Map<String, Object?>> _rows(LedgerExportFilter filter) =>
      ledger.exportTransactions(
        from: filter.from,
        to: filter.to,
        accountIds: filter.accountIds,
        kinds: filter.kinds,
        categoryIds: filter.categoryIds,
      );
}
