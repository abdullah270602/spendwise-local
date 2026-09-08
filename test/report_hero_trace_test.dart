import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:spendwise/features/reports/report_hero.dart';
import 'package:spendwise/features/reports/report_hero_trace.dart';
import 'package:spendwise/features/reports/spending_report.dart' as spend;
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// A page of nothing but the hero, so its own output can be inspected in
/// isolation from the masthead and register `spending_report.dart` normally
/// wraps it in. `compress: false` keeps every content stream as literal
/// text in the saved bytes -- the same reasoning `spending_report_test.dart`
/// applies to page dictionaries, extended here to the strings a base-14 font
/// writes for plain ASCII, which travel through `latin1.encode` unchanged.
Future<List<int>> _renderHero(ReportHero hero, ReportPaper paper) async {
  final document = pw.Document(compress: false);
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: hero.build(paper),
      ),
    ),
  );
  return document.save();
}

/// The words a page actually prints, in paint order, with a single space
/// between them regardless of how the layout kerned them apart.
///
/// The package positions every word of a `pw.Text` with its own `Td` offset
/// rather than a single run of glyphs -- `(Nothing)]TJ ET ... (before)]TJ`,
/// not `(Nothing before)]TJ` -- so a literal search for a whole sentence
/// never matches even though every word of it is right there in the stream.
/// Pulling out each parenthesised run and rejoining it with plain spaces
/// undoes exactly that, and nothing else: the words themselves travel
/// through `latin1.encode` unchanged for the plain ASCII (and Latin-1
/// middle dot) this file ever prints.
String _renderedText(List<int> bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final words = RegExp(r'\(((?:\\.|[^\\()])*)\)\]TJ')
      .allMatches(raw)
      .map((m) => m.group(1)!);
  return words.join(' ');
}

ReportPaper _paperFor(spend.ReportData data) => ReportPaper(
  data: data,
  sans: pw.Font.helvetica(),
  bold: pw.Font.helveticaBold(),
  mono: pw.Font.courier(),
  ink: const PdfColor.fromInt(0xFF17191A),
  muted: const PdfColor.fromInt(0xFF6B7176),
  rule: const PdfColor.fromInt(0xFFDFDDD6),
  paper: const PdfColor.fromInt(0xFFFAF9F6),
  keep: const PdfColor.fromInt(0xFF4E6B57),
  spend: const PdfColor.fromInt(0xFF8A4A33),
  mine: const PdfColor.fromInt(0xFF39505C),
  channelOf: (category) => 1,
  toneOf: (category) => const PdfColor.fromInt(0xFF55595C),
  money: (minorUnits) {
    final value = (minorUnits.abs() / 100).toStringAsFixed(2);
    final parts = value.split('.');
    final grouped = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return parts.last == '00' ? grouped : '$grouped.${parts.last}';
  },
  width: 499.28,
);

TransactionViewData _expense({
  required String id,
  required int minor,
  required DateTime at,
  required String category,
}) => TransactionViewData(
  id: id,
  title: id,
  subtitle: '',
  amount: MoneyViewData(-minor),
  kind: TransactionKind.expense,
  occurredAt: at,
  category: category,
);

/// Builds a `ReportData` from two hand-placed sets of category totals -- the
/// current period's and the one immediately before it -- without needing
/// every category's actual day-by-day transactions, since the trace only
/// ever reads `byCategory`/`previousByCategory` and the two period labels.
/// `now`/`previous` map a category to its minor-unit total; a category
/// absent from `previous` is new, one absent from `now` has stopped.
spend.ReportData _dataFor({
  required Map<String, int> now,
  required Map<String, int> previous,
}) {
  final request = spend.ReportRequest.forRange(
    spend.ReportRange.thisMonth,
    ReportTemplate.ribbon,
    now: DateTime(2026, 9, 15),
  );
  final transactions = <TransactionViewData>[
    for (final entry in now.entries)
      _expense(
        id: 'now-${entry.key}',
        minor: entry.value,
        at: DateTime(2026, 9, 10),
        category: entry.key,
      ),
    for (final entry in previous.entries)
      _expense(
        id: 'prev-${entry.key}',
        minor: entry.value,
        at: DateTime(2026, 8, 10),
        category: entry.key,
      ),
  ];
  return spend.ReportData.gather(
    request: request,
    transactions: transactions,
    accounts: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('traceRowFigures -- the fixed scale', () {
    test('a calm period stays small and a violent one reaches the edge, under one scale', () {
      // Every category within a few percent of last period -- the
      // Seismograph's own "quiet month" case (see
      // local/design/final-seismograph.html §4).
      final calm = traceRowFigures(
        _dataFor(
          now: {
            'Groceries': 40100,
            'Transport': 15650,
            'Dining out': 17200,
            'Shopping': 12950,
            'Health': 4300,
          },
          previous: {
            'Groceries': 39800,
            'Transport': 15300,
            'Dining out': 17900,
            'Shopping': 13100,
            'Health': 4100,
          },
        ),
      );

      // One category swings violently; the rest are ordinary. The
      // Seismograph's own "violent month" case (§5): Home repairs moves
      // from 140 to 3,080, a +2100% swing.
      final violent = traceRowFigures(
        _dataFor(
          now: {
            'Groceries': 43900,
            'Dining out': 26400,
            'Home repairs': 3080,
            'Health': 9100,
          },
          previous: {
            'Groceries': 38200,
            'Dining out': 12600,
            'Home repairs': 140,
            'Health': 2600,
          },
        ),
      );

      final calmMax = calm
          .map((f) => f.deviationFraction.abs())
          .reduce((a, b) => a > b ? a : b);
      final violentMax = violent
          .map((f) => f.deviationFraction.abs())
          .reduce((a, b) => a > b ? a : b);

      // This is the assertion a per-period scale would fail: normalising
      // to each dataset's own loudest category would stretch the calm
      // month's own largest row out to the same edge the violent month's
      // reaches, making the two indistinguishable. Under the fixed scale,
      // the calm month's loudest row (Health, +4.9%) stays a small
      // fraction of the lane while Home repairs' +2100% is clamped flush
      // to it.
      expect(
        calmMax,
        lessThan(0.15),
        reason: 'a calm period must not fill the lane',
      );
      expect(
        violentMax,
        closeTo(1.0, 1e-6),
        reason: 'an outlier past the reference swing clamps at the edge',
      );

      final homeRepairs = violent.firstWhere(
        (f) => f.category == 'Home repairs',
      );
      expect(homeRepairs.isClamped, isTrue);
      expect(homeRepairs.changePercent, closeTo(2100.0, 0.5));
    });

    test('a category with nothing before it is new, not a manufactured 0%', () {
      final figures = traceRowFigures(
        _dataFor(
          now: {'Groceries': 40000, 'Pet care': 4200},
          previous: {'Groceries': 38000},
        ),
      );
      final petCare = figures.firstWhere((f) => f.category == 'Pet care');

      expect(petCare.isNew, isTrue);
      expect(petCare.isFlat, isFalse);
      expect(
        petCare.changePercent,
        isNull,
        reason: 'now over a zero previous is undefined, not zero',
      );
      // Placed by share, in the sub-range that can never reach as far as a
      // real percentage would (see `_figureFor`'s isNew branch: at most
      // 0.5 of the lane).
      expect(petCare.deviationFraction, greaterThan(0));
      expect(petCare.deviationFraction, lessThanOrEqualTo(0.5));
    });

    test('a category that stopped entirely reads as a real -100%', () {
      final figures = traceRowFigures(
        _dataFor(
          now: {'Groceries': 40000},
          previous: {'Groceries': 38000, 'Gym membership': 3600},
        ),
      );
      final gym = figures.firstWhere((f) => f.category == 'Gym membership');

      expect(gym.isStopped, isTrue);
      expect(gym.isNew, isFalse);
      expect(gym.changePercent, -100.0);
      expect(gym.amountMinor, 0);
      expect(gym.previousAmountMinor, 3600);
      // -100% is the most negative any row can ever read, and (per the
      // finalized design, §5) reaches only ≈62% of the lane under this
      // calibration -- a rise and a fall of "the same visual distance" are
      // not events of the same size.
      expect(gym.deviationFraction, closeTo(-0.620, 0.01));
      expect(gym.isClamped, isFalse);
    });

    test('a completely flat period draws as a nearly straight line', () {
      final figures = traceRowFigures(
        _dataFor(
          now: {
            'Groceries': 40000,
            'Rent & utilities': 30500,
            'Transport': 15000,
          },
          previous: {
            'Groceries': 40000,
            'Rent & utilities': 30500,
            'Transport': 15000,
          },
        ),
      );

      expect(figures, hasLength(3));
      for (final figure in figures) {
        expect(
          figure.isFlat,
          isTrue,
          reason: '${figure.category} did not move',
        );
        expect(figure.deviationFraction, 0);
        expect(figure.changePercent, 0);
      }
    });

    test('thirty categories are all present, none folded away', () {
      final now = <String, int>{};
      final previous = <String, int>{};
      for (var i = 0; i < 30; i++) {
        final amount = 1000 + i * 250;
        now['Category $i'] = amount;
        previous['Category $i'] = (amount * 0.9).round();
      }
      final figures = traceRowFigures(_dataFor(now: now, previous: previous));

      expect(
        figures,
        hasLength(30),
        reason: 'paper has no tap to recover a folded category\'s figure',
      );
      expect(figures.map((f) => f.category).toSet(), hasLength(30));
    });
  });

  group('TraceHero.build -- survives the real cases', () {
    const hero = TraceHero();

    test(
      'a period with no previous period says so, and draws no trace',
      () async {
        final data = _dataFor(
          now: {'Groceries': 40000, 'Transport': 15000, 'Dining out': 9000},
          previous: const {},
        );
        final paper = _paperFor(data);

        expect(data.previousByCategory, isEmpty);

        final bytes = await _renderHero(hero, paper);
        final text = _renderedText(bytes);
        expect(
          text,
          contains('Nothing before this to trace against.'),
          reason:
              'a naive implementation would draw every category as new '
              'instead of saying plainly that there is nothing behind this '
              'period to compare it against',
        );
        // No trace geometry is drawn: none of the ordinary categories' own
        // names reach the page in this branch, since the whole drawing is
        // replaced by the one statement above.
        expect(text, isNot(contains('Groceries')));
      },
    );

    test('nothing moved in either period', () async {
      final data = _dataFor(now: const {}, previous: const {});
      final paper = _paperFor(data);
      final bytes = await _renderHero(hero, paper);
      expect(_renderedText(bytes), contains('Nothing moved.'));
    });

    test(
      'a brand-new category renders, named, with its exact figure',
      () async {
        final data = _dataFor(
          now: {'Groceries': 40000, 'Pet care': 4200},
          previous: {'Groceries': 38000},
        );
        final paper = _paperFor(data);
        final bytes = await _renderHero(hero, paper);
        final text = _renderedText(bytes);

        expect(text, contains('Pet care'));
        expect(text, contains('NEW'));
        // The exact amount, not only the percentage -- paper has no tap to
        // recover it the way the screen's semantics label can.
        expect(text, contains('42'));
      },
    );

    test(
      'a category dropped to zero is struck through and named "was"',
      () async {
        final data = _dataFor(
          now: {'Groceries': 40000},
          previous: {'Groceries': 38000, 'Gym membership': 3600},
        );
        final paper = _paperFor(data);
        final bytes = await _renderHero(hero, paper);
        final text = _renderedText(bytes);

        expect(text, contains('Gym membership'));
        expect(text, contains('stopped'));
        expect(text, contains('was'));
      },
    );

    test('a completely flat period still names every category', () async {
      final data = _dataFor(
        now: {'Groceries': 40000, 'Rent & utilities': 30500},
        previous: {'Groceries': 40000, 'Rent & utilities': 30500},
      );
      final paper = _paperFor(data);
      final bytes = await _renderHero(hero, paper);
      final text = _renderedText(bytes);

      expect(text, contains('Groceries'));
      expect(text, contains('Rent & utilities'));
      expect(text, contains('0%'));
    });

    test('thirty categories render on one page without throwing', () async {
      final now = <String, int>{};
      final previous = <String, int>{};
      for (var i = 0; i < 30; i++) {
        final amount = 1000 + i * 250;
        now['Category $i'] = amount;
        previous['Category $i'] = (amount * 0.9).round();
      }
      final data = _dataFor(now: now, previous: previous);
      final paper = _paperFor(data);

      final bytes = await _renderHero(hero, paper);
      final text = _renderedText(bytes);
      for (var i = 0; i < 30; i++) {
        expect(text, contains('Category $i'));
      }

      await Directory('build').create(recursive: true);
      await File('build/report-hero-trace-thirty.pdf').writeAsBytes(bytes);
    });

    test('an empty period does not throw', () async {
      final data = _dataFor(now: const {}, previous: const {});
      final paper = _paperFor(data);
      await _renderHero(hero, paper); // must not throw
    });

    test('a single category does not throw', () async {
      final data = _dataFor(
        now: {'Groceries': 40000},
        previous: {'Groceries': 38000},
      );
      final paper = _paperFor(data);
      await _renderHero(hero, paper); // must not throw
    });
  });
}
