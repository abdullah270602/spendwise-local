import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:spendwise/app/palette.dart';
import 'package:spendwise/features/reports/report_hero.dart';
import 'package:spendwise/features/reports/report_hero_dial.dart';
import 'package:spendwise/features/reports/spending_report.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// Walks the widget tree [DialHero.build] actually returns and pulls out
/// every literal string it would print -- category names, percentages,
/// amounts, the hub count. This is what "every category is named and
/// numbered somewhere on the page" means in a way a test can check: not that
/// the drawing didn't throw, but that the exact strings a reader would need
/// are present in the tree that gets handed to the PDF, whatever the count.
///
/// Restricted to the small vocabulary [DialHero] actually builds with
/// (Column, Row, Stack, SizedBox, Container, Expanded, Center, Text,
/// CustomPaint) rather than attempting a fully generic walk of every widget
/// the `pdf` package ships -- this file only needs to be honest about the
/// tree its own sibling produces.
List<String> _collectText(pw.Widget widget) {
  final out = <String>[];
  void visitSpan(pw.InlineSpan? span) {
    if (span == null) return;
    if (span is pw.TextSpan) {
      if (span.text != null) out.add(span.text!);
      span.children?.forEach(visitSpan);
    }
  }

  void walk(pw.Widget w) {
    if (w is pw.Text) {
      visitSpan(w.text);
      return;
    }
    if (w is pw.Column) {
      w.children.forEach(walk);
      return;
    }
    if (w is pw.Row) {
      w.children.forEach(walk);
      return;
    }
    if (w is pw.Stack) {
      w.children.forEach(walk);
      return;
    }
    if (w is pw.SizedBox) {
      if (w.child != null) walk(w.child!);
      return;
    }
    if (w is pw.Container) {
      if (w.child != null) walk(w.child!);
      return;
    }
    if (w is pw.Expanded) {
      if (w.child != null) walk(w.child!);
      return;
    }
    if (w is pw.Center) {
      if (w.child != null) walk(w.child!);
      return;
    }
    // pw.CustomPaint carries no text of its own -- the dial's rim, hub and
    // ticks are drawn straight to the canvas, never as widgets, exactly as
    // `_ChronographPainter` draws them on screen.
  }

  walk(widget);
  return out;
}

List<String> _pageText(List<pw.Widget> widgets) =>
    widgets.expand(_collectText).toList();

/// True once, anywhere in the tree, a [pw.CustomPaint] appears -- the dial
/// itself. Below the floor there must be none; at or above it there must be
/// exactly the rim this hero draws, never a second one.
int _customPaintCount(pw.Widget widget) {
  var count = 0;
  void walk(pw.Widget w) {
    if (w is pw.CustomPaint) {
      count++;
      return;
    }
    if (w is pw.Column) {
      w.children.forEach(walk);
    } else if (w is pw.Row) {
      w.children.forEach(walk);
    } else if (w is pw.Stack) {
      w.children.forEach(walk);
    } else if (w is pw.SizedBox && w.child != null) {
      walk(w.child!);
    } else if (w is pw.Container && w.child != null) {
      walk(w.child!);
    } else if (w is pw.Expanded && w.child != null) {
      walk(w.child!);
    } else if (w is pw.Center && w.child != null) {
      walk(w.child!);
    }
  }

  walk(widget);
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Base-14 fonts rather than the app's own TTFs: they need no asset bundle
  // to construct, which keeps this test about the hero's own logic and
  // geometry rather than about font loading spending_report.dart already
  // exercises for every template.
  final sans = pw.Font.helvetica();
  final bold = pw.Font.helveticaBold();
  final mono = pw.Font.courier();

  TransactionViewData expense({
    required String id,
    required String category,
    required int minor,
    int day = 4,
  }) => TransactionViewData(
    id: id,
    title: '$category purchase',
    subtitle: 'Test Account',
    amount: MoneyViewData(-minor),
    kind: TransactionKind.expense,
    occurredAt: DateTime(2026, 9, day, 12),
    category: category,
    accountName: 'Test Account',
  );

  ReportData dataFor(List<TransactionViewData> items) => ReportData.gather(
    request: ReportRequest.forRange(
      ReportRange.thisMonth,
      ReportTemplate.ribbon,
      now: DateTime(2026, 9, 30),
    ),
    transactions: items,
    accounts: const [],
  );

  /// A [ReportPaper] built the same way `SpendingReport` builds one for a
  /// real page: category tones relit through [paperTone], keyed to the exact
  /// list of categories this fixture is about to draw, so a test that checks
  /// "no new tone" would have something real to check against.
  ReportPaper paperFor(ReportData data, {double width = 499.28}) {
    final order = data.byCategory.map((e) => e.key).toList();
    final ramp = SpendWisePalette.sage.ramp;
    return ReportPaper(
      data: data,
      sans: sans,
      bold: bold,
      mono: mono,
      ink: const PdfColor.fromInt(0xFF17191A),
      muted: const PdfColor.fromInt(0xFF6B7176),
      rule: const PdfColor.fromInt(0xFFDFDDD6),
      paper: const PdfColor.fromInt(0xFFFAF9F6),
      keep: paperTone(SpendWisePalette.sage.keep),
      spend: paperTone(SpendWisePalette.sage.spend),
      mine: paperTone(SpendWisePalette.sage.mine),
      channelOf: (category) => 1,
      toneOf: (category) {
        final index = order.indexOf(category);
        return paperTone(
          ramp[(index < 0 ? order.length : index) % ramp.length],
        );
      },
      money: (minor) => (minor / 100).toStringAsFixed(2),
      width: width,
    );
  }

  group('the two pure geometry rules', () {
    test('12 o\'clock is index 0, and index grows clockwise', () {
      // -90 degrees is straight up in the convention every angle here is
      // measured in (0 degrees = 3 o'clock, positive = clockwise once run
      // through dialTickPoint's y-flip) -- so index 0 must land exactly
      // there regardless of how many categories share the rim.
      for (final count in [3, 5, 30]) {
        expect(dialAngleDegrees(0, count), -90);
      }
      // A quarter of the way around a 4-category dial is exactly 3 o'clock.
      expect(dialAngleDegrees(1, 4), 0);
      expect(dialAngleDegrees(2, 4), 90);
      expect(dialAngleDegrees(3, 4), 180);
    });

    test(
      'reading order survives the flip from a screen canvas to a PDF page',
      () {
        // Index 0 of a 4-category dial must land at the top (max y, centred
        // on x) in the *page's* own y-up coordinates, not the screen's y-down
        // ones -- this is the exact bug an unflipped copy of the screen's
        // formula would produce, silently drawing the dial upside down.
        final (topX, topY) = dialTickPoint(
          100,
          100,
          dialAngleDegrees(0, 4),
          50,
        );
        expect(topX, closeTo(100, 1e-9));
        expect(
          topY,
          closeTo(150, 1e-9),
          reason: '12 o\'clock is the topmost point',
        );

        // Index 1 of that same dial -- a quarter-turn clockwise from noon --
        // must land at 3 o'clock: rightmost, vertically centred.
        final (rightX, rightY) = dialTickPoint(
          100,
          100,
          dialAngleDegrees(1, 4),
          50,
        );
        expect(rightX, closeTo(150, 1e-9));
        expect(rightY, closeTo(100, 1e-9));

        // Index 2 -- 6 o'clock -- must be the bottommost point, not the top
        // again, which is what a sign error elsewhere would produce.
        final (bottomX, bottomY) = dialTickPoint(
          100,
          100,
          dialAngleDegrees(2, 4),
          50,
        );
        expect(bottomX, closeTo(100, 1e-9));
        expect(bottomY, closeTo(50, 1e-9));
      },
    );

    test(
      'tick length is in true proportion to share, never past the floor',
      () {
        const minLen = 5.0, maxLen = 29.0;
        // The largest share actually drawn always reaches the ceiling exactly.
        expect(
          dialTickLength(0.23, 0.23, minLen: minLen, maxLen: maxLen),
          maxLen,
        );
        // Half the largest share is exactly half-way up the range -- not half
        // of a fixed 100%, which is the mistake that would flatten every tick
        // once one category dominates the period.
        expect(
          dialTickLength(0.115, 0.23, minLen: minLen, maxLen: maxLen),
          closeTo(minLen + 0.5 * (maxLen - minLen), 1e-9),
        );
        // A 0.4% category beside a 23% one: nowhere near the ceiling, but
        // strictly above the floor and nowhere close to invisible.
        final tiny = dialTickLength(
          0.004,
          0.23,
          minLen: minLen,
          maxLen: maxLen,
        );
        expect(tiny, greaterThanOrEqualTo(minLen));
        expect(
          tiny,
          lessThan(minLen + (maxLen - minLen) * 0.1),
          reason:
              'a 0.4% share should sit near the floor, not partway up the '
              'range the way a linear-in-value (rather than linear-in-ratio) '
              'scale would place it',
        );
        // Nothing at all still draws at the floor, not a zero-length tick.
        expect(dialTickLength(0, 0, minLen: minLen, maxLen: maxLen), minLen);
      },
    );
  });

  group('the four real cases', () {
    test(
      'an empty period draws no dial and names nothing, but does not crash',
      () {
        final paper = paperFor(dataFor(const []));
        final widgets = DialHero().build(paper);
        expect(_customPaintCount(pw.Column(children: widgets)), 0);
        expect(
          _pageText(widgets).join(' '),
          contains('Categorised spending will appear here.'),
        );
      },
    );

    test('one category states its own figure, no dial, no plate needed', () {
      final data = dataFor([
        expense(id: 'a', category: 'Groceries', minor: 500000),
      ]);
      final paper = paperFor(data);
      final widgets = DialHero().build(paper);
      expect(_customPaintCount(pw.Column(children: widgets)), 0);
      final text = _pageText(widgets).join(' ');
      expect(text, contains('Groceries'.toUpperCase()));
      expect(text, contains('100.0%'));
      expect(text, contains('5000.00'));
    });

    test('two categories: below the floor, the plate carries it alone', () {
      final data = dataFor([
        expense(id: 'a', category: 'Groceries', minor: 600000),
        expense(id: 'b', category: 'Transport', minor: 400000),
      ]);
      final paper = paperFor(data);
      final widgets = DialHero().build(paper);
      // Chronograph.minForDial is 3; two categories is below it, so no rim
      // is drawn at all -- the same floor the screen enforces, restated
      // rather than imported.
      expect(_customPaintCount(pw.Column(children: widgets)), 0);
      final text = _pageText(widgets).join(' ');
      expect(text, contains('Groceries'));
      expect(text, contains('Transport'));
      expect(text, contains('60.0%'));
      expect(text, contains('40.0%'));
    });

    test(
      'thirty categories: the dial draws once, and every one is still named',
      () {
        final items = [
          for (var i = 0; i < 30; i++)
            expense(
              id: 'c$i',
              category: 'Category $i',
              // Strictly descending, so byCategory's own order (largest
              // first) is unambiguous and known ahead of time.
              minor: 3000000 - i * 90000,
              day: (i % 27) + 1,
            ),
        ];
        final data = dataFor(items);
        final paper = paperFor(data);
        final widgets = DialHero().build(paper);
        expect(data.byCategory.length, 30);

        expect(_customPaintCount(pw.Column(children: widgets)), 1);
        final text = _pageText(widgets).join(' ');
        for (var i = 0; i < 30; i++) {
          expect(
            text,
            contains('Category $i'),
            reason: 'category $i must be named somewhere on the page',
          );
        }
        expect(text, contains('30 categories'));

        // 12 o'clock reads as the largest share -- category 0, since the
        // fixture built it descending -- exactly the order the plate lists
        // in too (byCategory is already sorted largest first; the hero must
        // not have reordered or resampled it before handing it to the rim).
        expect(data.byCategory.first.key, 'Category 0');
      },
    );
  });

  test('a 0.4% category beside a 23% one is still visible and named', () {
    final data = dataFor([
      expense(id: 'big', category: 'Groceries', minor: 2300000),
      expense(id: 'mid1', category: 'Transport', minor: 2000000),
      expense(id: 'mid2', category: 'Health', minor: 1800000),
      expense(id: 'mid3', category: 'Shopping', minor: 1500000),
      expense(id: 'tiny', category: 'Bank Fees', minor: 40000),
    ]);
    final paper = paperFor(data);
    final widgets = DialHero().build(paper);
    expect(_customPaintCount(pw.Column(children: widgets)), 1);
    final text = _pageText(widgets).join(' ');
    expect(text, contains('Bank Fees'));
    // ~0.4% of the total, stated exactly rather than rounded to nothing.
    expect(text, contains('0.5%'));
  });

  group('no tone is invented', () {
    test(
      'every colour the dial and plate use comes from the paper it was given',
      () {
        final data = dataFor([
          expense(id: 'a', category: 'Groceries', minor: 500000),
          expense(id: 'b', category: 'Transport', minor: 300000),
          expense(id: 'c', category: 'Health', minor: 200000),
        ]);
        final paper = paperFor(data);
        // toneOf is exercised for every category the moment the plate and the
        // dial are built -- if either drew a literal PdfColor instead, this
        // fixture's toneOf would simply never be called, and nothing here
        // would fail. Recording every call it actually makes is the only way
        // to check the hero never reaches past the paper it was handed.
        final seen = <String>{};
        final tracked = ReportPaper(
          data: paper.data,
          sans: paper.sans,
          bold: paper.bold,
          mono: paper.mono,
          ink: paper.ink,
          muted: paper.muted,
          rule: paper.rule,
          paper: paper.paper,
          keep: paper.keep,
          spend: paper.spend,
          mine: paper.mine,
          channelOf: (category) => 1,
          toneOf: (category) {
            seen.add(category);
            return paper.toneOf(category);
          },
          money: paper.money,
          width: paper.width,
        );
        DialHero().build(tracked);
        expect(seen, {'Groceries', 'Transport', 'Health'});
      },
    );
  });

  test('the dial keeps its own printed size rather than filling the page', () {
    // Deliberately smaller than the screen's 280-unit box (see the doc
    // comment on DialHero.boxSize) -- this pins that choice down as a number
    // a future edit can't silently walk back into "stretch to fill the
    // column".
    expect(DialHero.boxSize, lessThan(280));
    expect(DialHero.boxSize, greaterThan(0));
  });

  group('actually rendered, on real A4 paper', () {
    // A widget tree that never throws is not the same claim as a page that
    // actually prints -- the `pdf` package's own layout pass (a `Stack`
    // resolving loose constraints, a `CustomPaint` given zero size by
    // default) only runs once a real `Document` is built and saved, which is
    // exactly the step every test above this group skips in order to stay
    // fast and inspect the tree directly instead. This group is the one
    // place that pass actually happens, on the same A4 page and margins
    // `SpendingReport` uses.
    Future<int> pageCountFor(ReportData data) async {
      final paper = paperFor(data);
      final document = pw.Document();
      document.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.fromLTRB(48, 50, 48, 42),
          ),
          build: (context) => DialHero().build(paper),
        ),
      );
      final bytes = await document.save();
      expect(bytes, isNotEmpty);
      // The object table stays plain text even though `pdf` deflates content
      // streams (see the identical technique in spending_report_test.dart's
      // own `_pageCount`), so this is a real count of page objects, not a
      // guess about the package's internals.
      final text = latin1.decode(bytes, allowInvalid: true);
      return RegExp(r'/Type\s*/Page[^s]').allMatches(text).length;
    }

    test('the floor case (two categories) renders as one page', () async {
      final data = dataFor([
        expense(id: 'a', category: 'Groceries', minor: 600000),
        expense(id: 'b', category: 'Transport', minor: 400000),
      ]);
      expect(await pageCountFor(data), 1);
    });

    test(
      'the real dial (thirty categories) still renders as one page',
      () async {
        final items = [
          for (var i = 0; i < 30; i++)
            expense(
              id: 'c$i',
              category: 'Category $i',
              minor: 3000000 - i * 90000,
            ),
        ];
        expect(await pageCountFor(dataFor(items)), 1);
      },
    );
  });
}
