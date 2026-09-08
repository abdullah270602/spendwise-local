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
    String? debtId,
  }) => TransactionViewData(
    id: id,
    title: title,
    subtitle: account,
    amount: MoneyViewData(kind == TransactionKind.expense ? -minor : minor),
    kind: kind,
    occurredAt: DateTime(2026, 9, day, 12),
    category: category,
    accountName: account,
    debtId: debtId,
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

  group('money that was never spending stays out of the figures', () {
    // Lending, being repaid, and holding money for somebody else all move an
    // account without being spending or income -- the ledger already knows,
    // through `debtId`, and Home and Insights both leave them out. The report
    // did not, so a month in which 200,000 passed through on its way to a
    // relative reported 200,000 of income and 200,000 of spending that never
    // belonged to anybody here.
    final held = [
      entry(
        id: 'salary',
        title: 'Salary',
        minor: 15000000,
        kind: TransactionKind.income,
        day: 1,
        category: 'Income',
      ),
      entry(
        id: 'groceries',
        title: 'Corner shop',
        minor: 420000,
        kind: TransactionKind.expense,
        day: 4,
      ),
      entry(
        id: 'held-in',
        title: 'From a relative, to pass on',
        minor: 20000000,
        kind: TransactionKind.income,
        day: 6,
        category: 'Transfer',
        debtId: 'debt-held',
      ),
      entry(
        id: 'held-out',
        title: 'Passed on',
        minor: 20000000,
        kind: TransactionKind.expense,
        day: 7,
        category: 'Transfer',
        debtId: 'debt-held',
      ),
      entry(
        id: 'lent',
        title: 'Lent to a friend',
        minor: 5000000,
        kind: TransactionKind.expense,
        day: 9,
        category: 'Transfer',
        debtId: 'debt-lent',
      ),
    ];

    ReportData read() => ReportData.gather(
      request: ReportRequest.forRange(
        ReportRange.thisMonth,
        ReportTemplate.shape,
        now: DateTime(2026, 9, 30),
      ),
      transactions: held,
      accounts: const [],
    );

    test('held money is neither received nor spent', () {
      final data = read();
      expect(data.receivedMinor, 15000000, reason: 'only the salary arrived');
      expect(
        data.spentMinor,
        420000,
        reason: 'only the groceries were spending',
      );
    });

    test('no debt movement reaches the category breakdown', () {
      final categories = read().byCategory.map((entry) => entry.key);
      expect(categories, contains('Groceries'));
      expect(
        categories,
        isNot(contains('Transfer')),
        reason: 'holding and lending are not a category of spending',
      );
    });

    test('the register still lists them, because they happened', () {
      // Leaving them out of the figures is not the same as pretending the
      // money never moved: the account really did go up and down, and a
      // register that hid it could not be reconciled against a statement.
      final ids = read().transactions.map((item) => item.id);
      expect(ids, containsAll(<String>['held-in', 'held-out', 'lent']));
      expect(read().hasExcludedMovements, isTrue);
    });
  });

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

  group('the shape states the whole it divides', () {
    // The trunk of the shape is everything that came in, and that figure was
    // never printed -- it existed only as the denominator of two percentages.
    // Under it sat three numbers against a two-branch drawing, one of which
    // (money moved between the reader's own accounts) was not a branch of
    // anything. Three figures that cannot be reconciled against the picture
    // above them is worse than two that can.
    test('the two branches account for all of it', () {
      final data = dataFor(ReportTemplate.shape);
      expect(
        data.keptMinor + data.spentMinor,
        data.receivedMinor,
        reason: 'still yours plus gone is what came in, or the legend lies',
      );
    });

    test('a period with nothing coming in still renders', () async {
      // Spending against no income is a real month. The percentages have no
      // denominator, and the page has to say so rather than print 0%.
      final spendOnly = [
        entry(
          id: 'shop',
          title: 'Corner shop',
          minor: 350000,
          kind: TransactionKind.expense,
          day: 3,
        ),
      ];
      final data = ReportData.gather(
        request: ReportRequest.forRange(
          ReportRange.thisMonth,
          ReportTemplate.shape,
          now: DateTime(2026, 9, 30),
        ),
        transactions: spendOnly,
        accounts: const [],
      );
      expect(data.receivedMinor, 0);
      expect(data.keptFraction, 0);

      final bytes = await const SpendingReport(palette: SpendWisePalette.sage)
          .build(data);
      // A real document, not an exception swallowed into an empty file. The
      // page-count assertions live on the branch that made the report a
      // MultiPage; here the question is only whether a month with no income
      // still produces one.
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), startsWith('%PDF'));
    });
  });

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
