import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/palette.dart';
import 'package:spendwise/features/reports/spending_report.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// A report is the one thing in SpendWise that leaves the device, so it has to
/// build from a real ledger shape without throwing, on every template, and
/// keep working when the period is empty.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TransactionViewData entry({
    required String id,
    required String title,
    required int minor,
    required TransactionKind kind,
    required int day,
    String category = 'Groceries',
    String account = 'Meezan Debit',
  }) => TransactionViewData(
    id: id,
    title: title,
    subtitle: account,
    amount: MoneyViewData(kind == TransactionKind.expense ? -minor : minor),
    kind: kind,
    occurredAt: DateTime(2026, 9, day, 12),
    category: category,
    accountName: account,
  );

  final ledger = [
    entry(
      id: 'salary',
      title: 'Salary',
      minor: 15000000,
      kind: TransactionKind.income,
      day: 2,
      category: 'Income',
    ),
    entry(
      id: 'shop',
      title: 'Sample Supermarket',
      minor: 106000,
      kind: TransactionKind.expense,
      day: 4,
    ),
    entry(
      id: 'pharmacy',
      title: 'Demo Pharmacy',
      minor: 208620,
      kind: TransactionKind.expense,
      day: 4,
      category: 'Health & medical',
    ),
    entry(
      id: 'move',
      title: 'Account transfer',
      minor: 1000000,
      kind: TransactionKind.transfer,
      day: 2,
      category: 'Between your accounts',
      account: 'Meezan Debit → NayaPay',
    ),
  ];

  ReportData dataFor(
    ReportTemplate template, {
    List<TransactionViewData>? of,
  }) => ReportData.gather(
    request: ReportRequest.forRange(
      ReportRange.thisMonth,
      template,
      now: DateTime(2026, 9, 30),
    ),
    transactions: of ?? ledger,
    accounts: const [],
  );

  test('the numbers a report is built from', () {
    final data = dataFor(ReportTemplate.shape);
    expect(data.receivedMinor, 15000000);
    expect(data.spentMinor, 314620);
    expect(
      data.movedMinor,
      1000000,
      reason: 'a move between your own accounts is neither in nor out',
    );
    expect(data.keptMinor, 14685380);
    expect(data.byCategory.first.key, 'Health & medical');
  });

  test('the shape template builds one page', () async {
    final bytes = await const SpendingReport(palette: SpendWisePalette.sage)
        .build(dataFor(ReportTemplate.shape));

    expect(bytes.lengthInBytes, greaterThan(2000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    await File('build/report-shape.pdf').writeAsBytes(bytes);
  });

  test('the statement template adds the register', () async {
    final bytes = await const SpendingReport(palette: SpendWisePalette.tide)
        .build(dataFor(ReportTemplate.statement));

    expect(bytes.lengthInBytes, greaterThan(2000));
    await File('build/report-statement.pdf').writeAsBytes(bytes);
  });

  test('an empty period still produces a readable page', () async {
    final bytes = await const SpendingReport(palette: SpendWisePalette.sage)
        .build(dataFor(ReportTemplate.shape, of: const []));

    expect(bytes.lengthInBytes, greaterThan(1000));
    await File('build/report-empty.pdf').writeAsBytes(bytes);
  });

  test('every palette renders', () async {
    for (final palette in SpendWisePalette.all) {
      final bytes = await SpendingReport(palette: palette)
          .build(dataFor(ReportTemplate.shape));
      expect(bytes.lengthInBytes, greaterThan(2000), reason: palette.id);
    }
  });
}
