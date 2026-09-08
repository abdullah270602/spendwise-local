import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:spendwise/features/reports/report_hero.dart';
import 'package:spendwise/features/reports/report_hero_ribbon.dart';
import 'package:spendwise/features/reports/spending_report.dart'
    show ReportData, ReportRequest, ReportRange;
// A second import of the same file, under a prefix and narrowed to just its
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// Builds a [ReportData] from a plain list of transactions, the same way
/// `spending_report_test.dart` does.
ReportData _dataFrom(
  List<TransactionViewData> transactions, {
  int fromDay = 1,
  int toDay = 30,
  int month = 9,
  int year = 2026,
}) => ReportData.gather(
  request: ReportRequest.forRange(
    ReportRange.custom,
    ReportTemplate.ribbon,
    customFrom: DateTime(year, month, fromDay),
    customTo: DateTime(year, month, toDay),
    now: DateTime(year, month, toDay),
  ),
  transactions: transactions,
  accounts: const [],
);

TransactionViewData _entry({
  required String id,
  required String title,
  required int minor,
  required TransactionKind kind,
  required int day,
  int month = 9,
  int year = 2026,
  String category = 'Groceries',
}) => TransactionViewData(
  id: id,
  title: title,
  subtitle: 'Sample Bank',
  amount: MoneyViewData(kind == TransactionKind.expense ? -minor : minor),
  kind: kind,
  occurredAt: DateTime(year, month, day, 12),
  category: category,
  accountName: 'Sample Bank',
);

/// A [ReportPaper] with every tone distinct from every other, so a test can
/// tell "drew the kept tone" apart from "drew some other tone that happens to
/// look similar" -- and distinct too from any colour this file or the
/// implementation might accidentally hardcode.
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

/// Renders [widgets] inside a minimal real PDF page and returns the saved
/// bytes -- the only way to prove the `pw.CustomPaint` painter actually runs
/// against a real `PdfGraphics` without throwing, rather than merely that the
/// widget tree was constructed.
Future<List<int>> _renderPage(List<pw.Widget> widgets) async {
  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Column(children: widgets),
    ),
  );
  return document.save();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ribbonGeometry: true proportion', () {
    test(
      'an ordinary period splits the trunk to exactly the kept fraction',
      () {
        final data = _dataFrom([
          _entry(
            id: 'salary',
            title: 'Salary',
            minor: 1000000,
            kind: TransactionKind.income,
            day: 2,
          ),
          _entry(
            id: 'rent',
            title: 'Rent',
            minor: 110000,
            kind: TransactionKind.expense,
            day: 4,
          ),
        ]);
        // Received 1,000,000; spent 110,000 -- kept fraction is exactly .89,
        // so the spent branch is the thin 11% thread the brief describes.
        expect(data.keptFraction, closeTo(.89, 1e-9));

        final geometry = ribbonGeometry(data, 480);
        expect(geometry.mode, RibbonMode.split);
        expect(geometry.keptW / geometry.topW, closeTo(.89, 1e-9));
        expect(geometry.spentW / geometry.topW, closeTo(.11, 1e-9));
        // The two arms still add up to the whole trunk -- no width is
        // invented or lost splitting it.
        expect(geometry.keptW + geometry.spentW, closeTo(geometry.topW, 1e-9));
      },
    );

    test(
      'a thin spent thread really is thin: 11% of the trunk, not a floor width',
      () {
        final data = _dataFrom([
          _entry(
            id: 'salary',
            title: 'Salary',
            minor: 5000000,
            kind: TransactionKind.income,
            day: 2,
          ),
          _entry(
            id: 'coffee',
            title: 'Coffee',
            minor: 55000,
            kind: TransactionKind.expense,
            day: 4,
          ),
        ]);
        final geometry = ribbonGeometry(data, 1000);
        // 55,000 / 5,000,000 = 1.1% spent -- the arm should read as almost
        // nothing, not be padded up to some readable minimum.
        expect(geometry.spentW / geometry.topW, closeTo(.011, 1e-9));
        expect(geometry.spentW, lessThan(geometry.keptW * .02));
      },
    );
  });

  group('ribbonGeometry: the degenerate cases', () {
    test('nothing came in: no denominator, so no split is drawn at all', () {
      final data = _dataFrom([
        _entry(
          id: 'groceries',
          title: 'Groceries bought from savings',
          minor: 40000,
          kind: TransactionKind.expense,
          day: 4,
        ),
      ]);
      expect(data.receivedMinor, 0);
      // ReportData.keptFraction clamps this regime to a bare 0 -- honest as
      // far as it goes, but a bare 0 also describes "you kept nothing of a
      // real income", which this is not. ribbonGeometry tells the two apart
      // instead of drawing the same full-width spent branch for both.
      expect(data.keptFraction, 0);

      final geometry = ribbonGeometry(data, 480);
      expect(geometry.mode, RibbonMode.noIncome);
      expect(geometry.keptW, 0);
      expect(geometry.spentW, 0);
      expect(geometry.overspent, isFalse);
      expect(geometry.topW.isFinite, isTrue);
      expect(geometry.topX.isFinite, isTrue);
    });

    test('nothing was spent: the spent arm is a real, honest zero', () {
      final data = _dataFrom([
        _entry(
          id: 'salary',
          title: 'Salary',
          minor: 800000,
          kind: TransactionKind.income,
          day: 2,
        ),
      ]);
      final geometry = ribbonGeometry(data, 480);
      expect(geometry.mode, RibbonMode.split);
      expect(geometry.spentW, 0);
      expect(geometry.keptW, closeTo(geometry.topW, 1e-9));
      expect(geometry.overspent, isFalse);
    });

    test(
      'spending exceeded income: kept is pinned to 0, not negative or NaN',
      () {
        final data = _dataFrom([
          _entry(
            id: 'salary',
            title: 'Salary',
            minor: 100000,
            kind: TransactionKind.income,
            day: 2,
          ),
          _entry(
            id: 'rent',
            title: 'Rent',
            minor: 250000,
            kind: TransactionKind.expense,
            day: 4,
          ),
        ]);
        expect(data.keptMinor, lessThan(0));
        // keptFraction's clamp is doing real work here: dividing the raw
        // negative kept amount by received would put the split past the
        // trunk's own left edge.
        expect(data.keptFraction, 0);

        final geometry = ribbonGeometry(data, 480);
        expect(geometry.mode, RibbonMode.split);
        expect(geometry.keptW, 0);
        expect(geometry.spentW, closeTo(geometry.topW, 1e-9));
        expect(geometry.overspent, isTrue);
        expect(geometry.keptW.isNaN, isFalse);
        expect(geometry.spentW.isNaN, isFalse);
      },
    );

    test('zero-width canvas still produces finite, non-NaN geometry', () {
      final data = _dataFrom([
        _entry(
          id: 'salary',
          title: 'Salary',
          minor: 100000,
          kind: TransactionKind.income,
          day: 2,
        ),
        _entry(
          id: 'rent',
          title: 'Rent',
          minor: 40000,
          kind: TransactionKind.expense,
          day: 4,
        ),
      ]);
      final geometry = ribbonGeometry(data, 0);
      expect(geometry.topW, 0);
      expect(geometry.keptW.isNaN, isFalse);
      expect(geometry.spentW.isNaN, isFalse);
    });
  });

  group('RibbonHero.build: an entirely empty period', () {
    test('draws no ribbon at all, only a plain statement', () {
      final data = _dataFrom(const []);
      expect(data.isEmpty, isTrue);

      final widgets = const RibbonHero().build(_paperFor(data));
      expect(widgets, hasLength(1));
      expect(_countCustomPaints(widgets), 0);
    });

    test('still renders as a valid, non-throwing PDF page', () async {
      final data = _dataFrom(const []);
      final bytes = await _renderPage(
        const RibbonHero().build(_paperFor(data)),
      );
      expect(bytes, isNotEmpty);
    });
  });

  group(
    'RibbonHero.build: the ribbon is only ever drawn when there is one',
    () {
      test('a real period draws exactly one ribbon', () {
        final data = _dataFrom([
          _entry(
            id: 'salary',
            title: 'Salary',
            minor: 500000,
            kind: TransactionKind.income,
            day: 2,
          ),
          _entry(
            id: 'rent',
            title: 'Rent',
            minor: 100000,
            kind: TransactionKind.expense,
            day: 4,
          ),
        ]);
        final widgets = const RibbonHero().build(_paperFor(data));
        expect(_countCustomPaints(widgets), 1);
      });
    },
  );

  group('every degenerate case survives real PDF rendering', () {
    Future<void> expectRenders(List<TransactionViewData> ledger) async {
      final data = _dataFrom(ledger);
      final bytes = await _renderPage(
        const RibbonHero().build(_paperFor(data)),
      );
      expect(bytes, isNotEmpty);
    }

    test(
      'nothing came in',
      () => expectRenders([
        _entry(
          id: 'groceries',
          title: 'Groceries from savings',
          minor: 40000,
          kind: TransactionKind.expense,
          day: 4,
        ),
      ]),
    );

    test(
      'nothing was spent',
      () => expectRenders([
        _entry(
          id: 'salary',
          title: 'Salary',
          minor: 500000,
          kind: TransactionKind.income,
          day: 2,
        ),
      ]),
    );

    test(
      'spending exceeded income',
      () => expectRenders([
        _entry(
          id: 'salary',
          title: 'Salary',
          minor: 100000,
          kind: TransactionKind.income,
          day: 2,
        ),
        _entry(
          id: 'rent',
          title: 'Rent',
          minor: 250000,
          kind: TransactionKind.expense,
          day: 4,
        ),
      ]),
    );

    test('an entirely empty period', () => expectRenders(const []));
  });

  group('honesty of the legend text beside the ribbon', () {
    test('"still yours" never prints a negative amount when overspent', () {
      final data = _dataFrom([
        _entry(
          id: 'salary',
          title: 'Salary',
          minor: 100000,
          kind: TransactionKind.income,
          day: 2,
        ),
        _entry(
          id: 'rent',
          title: 'Rent',
          minor: 250000,
          kind: TransactionKind.expense,
          day: 4,
        ),
      ]);
      final texts = _collectText(const RibbonHero().build(_paperFor(data)));
      expect(texts.any((t) => t.contains('-')), isFalse);
      expect(
        texts.any((t) => t.contains('more than came in')),
        isTrue,
        reason: 'the overspend has to be stated in words somewhere',
      );
    });

    test('"gone" is allowed past 100% rather than being silently capped', () {
      final data = _dataFrom([
        _entry(
          id: 'salary',
          title: 'Salary',
          minor: 100000,
          kind: TransactionKind.income,
          day: 2,
        ),
        _entry(
          id: 'rent',
          title: 'Rent',
          minor: 250000,
          kind: TransactionKind.expense,
          day: 4,
        ),
      ]);
      final texts = _collectText(const RibbonHero().build(_paperFor(data)));
      expect(texts.any((t) => t.contains('250%')), isTrue);
    });
  });

  group('tone discipline: only the passed paper\'s own colours are used', () {
    test(
      'the ribbon\'s three tones are exactly the paper\'s ink, keep and spend',
      () {
        final paperA = _paperFor(_dataFrom(const []));
        final paperB = ReportPaper(
          data: paperA.data,
          sans: paperA.sans,
          bold: paperA.bold,
          mono: paperA.mono,
          ink: const PdfColor.fromInt(0xFF010101),
          muted: paperA.muted,
          rule: paperA.rule,
          paper: paperA.paper,
          keep: const PdfColor.fromInt(0xFF020202),
          spend: const PdfColor.fromInt(0xFF030303),
          mine: paperA.mine,
          channelOf: (category) => 1,
          toneOf: paperA.toneOf,
          money: paperA.money,
          width: paperA.width,
        );
        // A second paper with different keep/spend/ink than the first proves
        // the mapping reads the passed instance rather than a value baked in
        // at compile time.
        expect(ribbonTrunkTone(paperA), paperA.ink);
        expect(ribbonTrunkTone(paperB), paperB.ink);
        expect(ribbonTrunkTone(paperB), isNot(paperA.ink));
        expect(ribbonKeptTone(paperB), paperB.keep);
        expect(ribbonSpentTone(paperB), paperB.spend);
      },
    );
  });
}

/// The child widgets of any container [RibbonHero.build] is known to use --
/// shared by both walkers below so a container this hero starts nesting
/// widgets inside later only has to be taught here once.
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

int _countCustomPaints(List<pw.Widget> widgets) {
  var count = 0;
  _walk(widgets, (widget) {
    if (widget is pw.CustomPaint) count++;
  });
  return count;
}

List<String> _collectText(List<pw.Widget> widgets) {
  final found = <String>[];
  _walk(widgets, (widget) {
    if (widget is pw.Text) {
      final span = widget.text;
      if (span is pw.TextSpan && span.text != null) {
        found.add(span.text!);
      }
    }
  });
  return found;
}
