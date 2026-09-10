import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:spendwise/features/reports/report_hero.dart';
import 'package:spendwise/features/reports/report_hero_ribbon.dart';
import 'package:spendwise/features/reports/spending_report.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// A report is allowed to name a stretch of time only if that is the stretch
/// it measured.
///
/// Two ways it stopped being: the comparison period was rolled back by a day
/// count, which cannot land on the 1st of anything because months are
/// different lengths -- so "last 3 months" compared July-September against
/// 31 March to 30 June, four month names wide, with a day of the quarter
/// before last counted against the quarter just gone. And `periodLabel` gave
/// any window inside one month that month's name, so a report of 1-15
/// September and its 17-31 August comparison were both labelled with a whole
/// month they only half covered. A salary lands on the 1st; a window that
/// says "August" and starts on the 17th loses it, and a fall in spending
/// reads as a rise from nothing.
///
/// And one way the figures stopped being: money lent out comes off what is
/// still yours without ever joining what was spent, so "still yours" can go
/// negative in a month that overspent nothing. The page used to explain that
/// as "spent N more than came in", which is a false sentence about a person's
/// own money, printed on a document they keep.
void main() {
  TransactionViewData spend(String id, DateTime when, int minor) =>
      TransactionViewData(
        id: id,
        title: id,
        subtitle: '',
        amount: MoneyViewData(-minor),
        kind: TransactionKind.expense,
        occurredAt: when,
        category: 'Groceries',
      );

  ReportData rangeReport(
    ReportRange range, {
    required DateTime now,
    List<TransactionViewData> transactions = const [],
  }) => ReportData.gather(
    request: ReportRequest.forRange(range, ReportTemplate.trace, now: now),
    transactions: transactions,
    accounts: const [],
  );

  group('the comparison window is the one the label names', () {
    test('one whole month compares against the whole month before it', () {
      final data = rangeReport(
        ReportRange.thisMonth,
        now: DateTime(2026, 9, 15),
        transactions: [
          spend('first-of-august', DateTime(2026, 8, 1, 10), 5000000),
          spend('last-of-august', DateTime(2026, 8, 31, 22), 100000),
          spend('july', DateTime(2026, 7, 31, 22), 900000),
        ],
      );

      expect(data.previousLabel, 'August 2026');
      expect(
        data.previousSpentMinor,
        5100000,
        reason: 'the 1st and the 31st are both in August, and July is not',
      );
    });

    test('three whole months compare against the three before them', () {
      final data = rangeReport(
        ReportRange.lastThreeMonths,
        now: DateTime(2026, 9, 15),
        transactions: [
          spend('march-31', DateTime(2026, 3, 31, 10), 5000000),
          spend('april-1', DateTime(2026, 4, 1, 10), 700000),
        ],
      );

      expect(data.previousLabel, 'Apr – Jun 2026');
      expect(
        data.previousSpentMinor,
        700000,
        reason: 'the three months before July are April, May and June -- '
            'a day-count rollback reached back into March',
      );
    });

    test('a whole year compares against the whole year before it', () {
      final data = rangeReport(
        ReportRange.thisYear,
        now: DateTime(2024, 6, 15),
        transactions: [
          spend('new-years-eve-2022', DateTime(2022, 12, 31, 10), 5000000),
          spend('new-years-day-2023', DateTime(2023, 1, 1, 10), 300000),
        ],
      );

      expect(
        data.previousSpentMinor,
        300000,
        reason: 'the year before 2024 is 2023, and stops at its own 1 January',
      );
    });

    test('January reaches back into the December before it', () {
      final data = rangeReport(
        ReportRange.thisMonth,
        now: DateTime(2026, 1, 15),
        transactions: [spend('dec', DateTime(2025, 12, 1, 10), 500000)],
      );

      expect(data.previousLabel, 'December 2025');
      expect(data.previousSpentMinor, 500000);
    });

    test('a leap February is a whole month like any other', () {
      final data = rangeReport(
        ReportRange.thisMonth,
        now: DateTime(2024, 2, 10),
        transactions: [spend('jan', DateTime(2024, 1, 1, 10), 500000)],
      );

      expect(data.previousLabel, 'January 2024');
      expect(data.previousSpentMinor, 500000);
    });
  });

  group('a part-month window is never given a whole month\'s name', () {
    ReportData halfSeptember() => ReportData.gather(
      request: ReportRequest.forRange(
        ReportRange.custom,
        ReportTemplate.trace,
        now: DateTime(2026, 9, 20),
        customFrom: DateTime(2026, 9),
        customTo: DateTime(2026, 9, 15),
      ),
      transactions: [
        spend('august-5', DateTime(2026, 8, 5, 10), 5000000),
        spend('september-12', DateTime(2026, 9, 12, 10), 1000000),
      ],
      accounts: const [],
    );

    test('not the window itself', () {
      expect(halfSeptember().request.label, '1 Sep – 15 Sep 2026');
    });

    test('and not the window it is compared against', () {
      final data = halfSeptember();
      // The comparison really runs 17-31 August. Calling it "August 2026"
      // told the reader the 5th was inside it when it was not.
      expect(data.previousLabel, '17 Aug – 31 Aug 2026');
      expect(data.previousSpentMinor, 0);
    });
  });

  group('the report does not call a loan an overspend', () {
    /// 100,000 came in, 20,000 was spent, 200,000 was lent out and is not
    /// back. Nothing was overspent; "still yours" is negative all the same.
    ReportData lentMore() => ReportData.gather(
      request: ReportRequest.forRange(
        ReportRange.thisMonth,
        ReportTemplate.ribbon,
        now: DateTime(2026, 9, 20),
      ),
      transactions: [
        TransactionViewData(
          id: 'salary',
          title: 'Salary',
          subtitle: '',
          amount: const MoneyViewData(10000000),
          kind: TransactionKind.income,
          occurredAt: DateTime(2026, 9, 2, 10),
          category: 'Income',
        ),
        spend('shop', DateTime(2026, 9, 3, 10), 2000000),
        TransactionViewData(
          id: 'lent',
          title: 'To Sana',
          subtitle: '',
          amount: const MoneyViewData(-20000000),
          kind: TransactionKind.expense,
          occurredAt: DateTime(2026, 9, 4, 10),
          category: 'Other',
          debtId: 'loan-1',
        ),
      ],
      accounts: const [],
    );

    test('the words under "Still yours" name the loan, not a spend', () {
      final data = lentMore();
      expect(data.keptMinor, -12000000, reason: 'the loan is not back yet');
      expect(data.spentMinor, 2000000, reason: 'lending is not spending');

      final texts = _collectText(const RibbonHero().build(_paperFor(data)));
      expect(
        texts.where((line) => line.contains('more than came in')),
        isEmpty,
        reason: 'only 20,000 of the 100,000 that came in was spent',
      );
      expect(
        texts.where((line) => line.contains('went out on loans')),
        isNotEmpty,
      );
    });

    test('and a real overspend still says so', () {
      final data = ReportData.gather(
        request: ReportRequest.forRange(
          ReportRange.thisMonth,
          ReportTemplate.ribbon,
          now: DateTime(2026, 9, 20),
        ),
        transactions: [
          TransactionViewData(
            id: 'salary',
            title: 'Salary',
            subtitle: '',
            amount: const MoneyViewData(10000000),
            kind: TransactionKind.income,
            occurredAt: DateTime(2026, 9, 2, 10),
            category: 'Income',
          ),
          spend('rent', DateTime(2026, 9, 3, 10), 13000000),
        ],
        accounts: const [],
      );

      final texts = _collectText(const RibbonHero().build(_paperFor(data)));
      expect(
        texts.where((line) => line.contains('more than came in')),
        isNotEmpty,
      );
    });
  });
}

ReportPaper _paperFor(ReportData data) => ReportPaper(
  data: data,
  sans: pw.Font.helvetica(),
  bold: pw.Font.helveticaBold(),
  mono: pw.Font.courier(),
  ink: const PdfColor.fromInt(0xFF111213),
  muted: const PdfColor.fromInt(0xFF222324),
  rule: const PdfColor.fromInt(0xFF333435),
  paper: const PdfColor.fromInt(0xFFFAFAFA),
  keep: const PdfColor.fromInt(0xFF445566),
  spend: const PdfColor.fromInt(0xFF665544),
  mine: const PdfColor.fromInt(0xFF556644),
  channelOf: (category) => 1,
  toneOf: (category) => const PdfColor.fromInt(0xFF000000),
  money: (minor) => (minor / 100).toStringAsFixed(2),
  width: 480,
);

List<pw.Widget> _childrenOf(pw.Widget widget) => switch (widget) {
  pw.Column(:final children) => children,
  pw.Row(:final children) => children,
  pw.Expanded(:final child) when child != null => [child],
  pw.SizedBox(:final child) when child != null => [child],
  _ => const [],
};

void _walk(List<pw.Widget> widgets, void Function(pw.Widget) visit) {
  for (final widget in widgets) {
    visit(widget);
    _walk(_childrenOf(widget), visit);
  }
}

List<String> _collectText(List<pw.Widget> widgets) {
  final found = <String>[];
  _walk(widgets, (widget) {
    if (widget is pw.Text) {
      final span = widget.text;
      if (span is pw.TextSpan && span.text != null) found.add(span.text!);
    }
  });
  return found;
}
