import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:spendwise/app/palette.dart';
import 'package:spendwise/features/reports/report_hero.dart';
import 'package:spendwise/features/reports/spending_report.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// Physical page count of a rendered PDF, read from the document itself
/// rather than assumed.
///
/// The `pdf` package only deflates content streams, not the object table, so
/// every page dictionary's `/Type /Page` still appears as plain text in the
/// saved bytes -- verified against the package's own output, not a guess
/// about its internals. `/Type /Pages` (the tree node, always exactly one)
/// is excluded by requiring the next character not be an `s`.
int _pageCount(List<int> bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  return RegExp(r'/Type\s*/Page[^s]').allMatches(text).length;
}

/// WCAG relative luminance and contrast ratio, used to hold every paper tone
/// to an actual, checkable minimum rather than trusting the formula that
/// produced it.
double _linear(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(PdfColor c) =>
    0.2126 * _linear(c.red) +
    0.7152 * _linear(c.green) +
    0.0722 * _linear(c.blue);

double _contrastAgainstPaper(PdfColor c) {
  const paper = PdfColor.fromInt(0xFFFAF9F6);
  final l1 = _luminance(paper);
  final l2 = _luminance(c);
  final lighter = math.max(l1, l2), darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TransactionViewData entry({
    required String id,
    required String title,
    required int minor,
    required TransactionKind kind,
    required int day,
    int month = 9,
    int year = 2026,
    String category = 'Groceries',
    String account = 'Meezan Debit',
    String? debtId,
  }) => TransactionViewData(
    id: id,
    title: title,
    subtitle: account,
    amount: MoneyViewData(kind == TransactionKind.expense ? -minor : minor),
    kind: kind,
    occurredAt: DateTime(year, month, day, 12),
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
    // The prior month, so "the change" has something real to compare
    // against -- deliberately a different shape (less income, a category
    // "shop" does not touch this time) so a test that only matched by
    // coincidence would be caught.
    entry(
      id: 'prev-salary',
      title: 'Salary',
      minor: 12000000,
      kind: TransactionKind.income,
      day: 2,
      month: 8,
      category: 'Income',
    ),
    entry(
      id: 'prev-groceries',
      title: 'Old Town Grocer',
      minor: 300000,
      kind: TransactionKind.expense,
      day: 10,
      month: 8,
    ),
    entry(
      id: 'prev-transport',
      title: 'Fuel',
      minor: 100000,
      kind: TransactionKind.expense,
      day: 15,
      month: 8,
      category: 'Transport',
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

  group('the numbers a report is built from', () {
    test('this period', () {
      final data = dataFor(ReportTemplate.ribbon);
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

    test('the period immediately before it, for "the change"', () {
      final data = dataFor(ReportTemplate.trace);
      expect(data.previousLabel, 'August 2026');
      expect(data.previousReceivedMinor, 12000000);
      expect(
        data.previousSpentMinor,
        400000,
        reason: '300,000 groceries + 100,000 transport',
      );
      expect(data.previousByCategory.first.key, 'Groceries');
      expect(data.previousByCategory.first.value, 300000);
      expect(data.spentDeltaMinor, 314620 - 400000);
      expect(
        data.spentDeltaFraction,
        closeTo((314620 - 400000) / 400000, 1e-9),
      );
    });

    test(
      'a period with nothing before it reports no comparison, not a crash',
      () {
        final data = ReportData.gather(
          request: ReportRequest.forRange(
            ReportRange.thisMonth,
            ReportTemplate.trace,
            now: DateTime(2026, 9, 30),
          ),
          transactions: ledger
              .where(
                (t) =>
                    t.id != 'prev-salary' &&
                    t.id != 'prev-groceries' &&
                    t.id != 'prev-transport',
              )
              .toList(),
          accounts: const [],
        );
        expect(data.previousSpentMinor, 0);
        expect(data.spentDeltaFraction, isNull);
      },
    );
  });

  group('categoryGroups (the docket\'s grouping)', () {
    test('groups expenses by category, ranked by subtotal, income and transfers excluded', () {
      final groups = categoryGroups(ledger);
      // Two expenses in the current period, plus two in the "previous
      // month" fixture entries above -- categoryGroups does not filter by
      // date, it groups whatever list it is handed.
      expect(groups.map((g) => g.category).toSet(), {
        'Groceries',
        'Health & medical',
        'Transport',
      });
      expect(groups.first.category, 'Groceries');
      expect(groups.first.totalMinor, 106000 + 300000);
      expect(groups.first.items.length, 2);
      final medical = groups.firstWhere(
        (g) => g.category == 'Health & medical',
      );
      expect(medical.totalMinor, 208620);
      // Income and the transfer never appear in any group.
      for (final group in groups) {
        expect(
          group.items.every((i) => i.kind == TransactionKind.expense),
          isTrue,
        );
      }
    });

    test('an all-income ledger produces no groups at all', () {
      expect(categoryGroups([ledger.first]), isEmpty);
    });
  });

  group('monthBuckets (the almanac\'s tiles)', () {
    test(
      'one bucket per calendar month, including a quiet one with nothing in it',
      () {
        final buckets = monthBuckets(
          DateTime(2026, 7),
          DateTime(2026, 9, 30),
          ledger.where((t) => t.occurredAt.month != 8).toList(),
        );
        expect(buckets.length, 3, reason: 'July, August, September');
        expect(buckets[0].start, DateTime(2026, 7));
        expect(buckets[1].start, DateTime(2026, 8));
        expect(buckets[2].start, DateTime(2026, 9));

        final august = buckets[1];
        expect(august.receivedMinor, 0);
        expect(august.spentMinor, 0);
        expect(
          august.topCategory,
          isNull,
          reason: 'nothing was filtered into it',
        );

        final september = buckets[2];
        expect(september.receivedMinor, 15000000);
        expect(september.spentMinor, 314620);
        expect(september.topCategory, 'Health & medical');
        expect(september.netMinor, 15000000 - 314620);
      },
    );
  });

  group('paperTone: every palette holds a real contrast minimum on paper', () {
    test('keep, spend, mine and the full ramp all clear 3.5:1 against the page', () {
      for (final palette in SpendWisePalette.all) {
        final tones = <String, PdfColor>{
          'keep': paperTone(palette.keep),
          'spend': paperTone(palette.spend),
          'mine': paperTone(palette.mine),
          for (var i = 0; i < palette.ramp.length; i++)
            'ramp$i': paperTone(palette.ramp[i]),
        };
        for (final tone in tones.entries) {
          expect(
            _contrastAgainstPaper(tone.value),
            greaterThanOrEqualTo(3.5),
            reason:
                '${palette.id}.${tone.key} is too light to read as ink on paper',
          );
        }
      }
    });

    test('an already-dark tone is left alone rather than darkened further', () {
      // sage's darkest ramp member is already near-black; paperTone should
      // not push it past legibility into looking like a printing fault.
      const dark = Color(0xFF4A5054);
      final relit = paperTone(dark);
      expect(_contrastAgainstPaper(relit), lessThan(9));
    });
  });

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
      // Arrived, and was never ours.
      entry(
        id: 'held-in',
        title: 'From a relative, to pass on',
        minor: 20000000,
        kind: TransactionKind.income,
        day: 6,
        category: 'Transfer',
        debtId: 'debt-held',
      ),
      // And passed on.
      entry(
        id: 'held-out',
        title: 'Passed on',
        minor: 20000000,
        kind: TransactionKind.expense,
        day: 7,
        category: 'Transfer',
        debtId: 'debt-held',
      ),
      // Lent out: leaves the account, is not spending, and is coming back.
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
        ReportTemplate.ribbon,
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
    });
  });

  group('page layout: overflow spills to another page instead of clipping', () {
    final longCategories = [
      'Household utilities and shared building maintenance charges',
      'Personal healthcare, pharmacy and wellness related purchases',
      'Restaurants, cafes and food delivery service subscriptions',
      'Public and private transportation, fuel and vehicle upkeep',
      'Clothing, footwear and seasonal wardrobe replacement items',
      'Entertainment, streaming subscriptions and hobby purchases',
      'Education, courses, books and professional certifications',
      'Gifts, celebrations and charitable community contributions',
    ];
    final heavyLedger = [
      entry(
        id: 'salary',
        title: 'Salary',
        minor: 30000000,
        kind: TransactionKind.income,
        day: 1,
        category: 'Income',
      ),
      for (var i = 0; i < longCategories.length; i++)
        entry(
          id: 'e$i',
          title: 'Merchant number $i for testing purposes only',
          minor: 500000 + i * 10000,
          kind: TransactionKind.expense,
          day: (i % 27) + 1,
          category: longCategories[i],
        ),
      for (var i = 0; i < 8; i++)
        entry(
          id: 'm$i',
          title: 'Distinct Merchant Name Number $i Ltd',
          minor: 90000 + i * 5000,
          kind: TransactionKind.expense,
          day: (i % 27) + 1,
          category: longCategories[i % longCategories.length],
        ),
    ];

    test('the shape holds to one page for an ordinary month', () async {
      final bytes = await const SpendingReport(palette: SpendWisePalette.sage)
          .build(dataFor(ReportTemplate.ribbon));
      expect(_pageCount(bytes), 1);
      await File('build/report-shape.pdf').writeAsBytes(bytes);
    });

    test('the shape spills to a second page rather than clipping when categories run long', () async {
      final bytes = await const SpendingReport(palette: SpendWisePalette.sage)
          .build(dataFor(ReportTemplate.ribbon, of: heavyLedger));
      expect(_pageCount(bytes), greaterThan(1));
      await File('build/report-shape-heavy.pdf').writeAsBytes(bytes);
    });

    test('the register follows the drawing instead of restarting', () async {
      // "The statement" used to be two documents stapled together: a shape
      // page, then a register page that began the paper again with its own
      // header and its own margins. There is one document now, whichever
      // drawing opens it, so a short period is one page rather than a page
      // and a mostly empty second one.
      final bytes = await const SpendingReport(palette: SpendWisePalette.tide)
          .build(dataFor(ReportTemplate.ribbon));
      expect(_pageCount(bytes), 1);
      await File('build/report-ribbon.pdf').writeAsBytes(bytes);
    });

    test('every drawing produces a document, and the same register', () async {
      // A template is a choice of opening figure, not a different report.
      for (final template in ReportTemplate.values) {
        final bytes = await const SpendingReport(palette: SpendWisePalette.tide)
            .build(dataFor(template));
        expect(
          _pageCount(bytes),
          greaterThanOrEqualTo(1),
          reason: '${template.id} produced no page at all',
        );
      }
    });

    test('the docket paginates once there is enough to itemise', () async {
      final small = await const SpendingReport(palette: SpendWisePalette.brass)
          .build(dataFor(ReportTemplate.desk));
      final heavy = await const SpendingReport(palette: SpendWisePalette.brass)
          .build(dataFor(ReportTemplate.desk, of: heavyLedger));
      expect(_pageCount(small), 1);
      expect(_pageCount(heavy), greaterThan(1));
      await File('build/report-docket.pdf').writeAsBytes(heavy);
    });

    test(
      'the change paginates once there are enough categories to compare',
      () async {
        final manyCategories = [
          entry(
            id: 'inc',
            title: 'Salary',
            minor: 15000000,
            kind: TransactionKind.income,
            day: 1,
            category: 'Income',
          ),
          for (var i = 0; i < 40; i++)
            entry(
              id: 'c$i',
              title: 'Merchant $i',
              minor: 50000 + i * 1000,
              kind: TransactionKind.expense,
              day: (i % 27) + 1,
              category: 'Category number $i',
            ),
        ];
        final small = await const SpendingReport(palette: SpendWisePalette.ink)
            .build(dataFor(ReportTemplate.trace));
        final heavy = await const SpendingReport(palette: SpendWisePalette.ink)
            .build(dataFor(ReportTemplate.trace, of: manyCategories));
        expect(_pageCount(small), 1);
        expect(_pageCount(heavy), greaterThan(1));
        await File('build/report-change.pdf').writeAsBytes(small);
      },
    );

    test('the almanac draws one row per three months and paginates over a long span', () async {
      final years = [
        for (var y = 2023; y <= 2026; y++)
          for (var m = 1; m <= 12; m++)
            entry(
              id: 'inc-$y-$m',
              title: 'Salary',
              minor: 1000000,
              kind: TransactionKind.income,
              day: 2,
              month: m,
              year: y,
              category: 'Income',
            ),
      ];
      final request = ReportRequest.forRange(
        ReportRange.everything,
        ReportTemplate.dial,
        now: DateTime(2026, 9, 30),
        earliest: DateTime(2023, 1, 1),
      );
      final data = ReportData.gather(
        request: request,
        transactions: years,
        accounts: const [],
      );
      expect(
        monthBuckets(
          data.request.from,
          data.request.to,
          data.transactions,
        ).length,
        45,
      );
      final bytes = await const SpendingReport(palette: SpendWisePalette.slate)
          .build(data);
      expect(_pageCount(bytes), greaterThan(1));
      await File('build/report-almanac.pdf').writeAsBytes(bytes);
    });
  });

  test(
    'an empty period still produces a readable page, on every template',
    () async {
      for (final template in ReportTemplate.values) {
        final bytes = await const SpendingReport(palette: SpendWisePalette.sage)
            .build(dataFor(template, of: const []));
        expect(
          _pageCount(bytes),
          greaterThanOrEqualTo(1),
          reason: template.name,
        );
      }
    },
  );

  test('every palette renders the shape as exactly one page', () async {
    for (final palette in SpendWisePalette.all) {
      final bytes = await SpendingReport(palette: palette)
          .build(dataFor(ReportTemplate.ribbon));
      expect(_pageCount(bytes), 1, reason: palette.id);
    }
  });
}
