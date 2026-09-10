import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'report_hero.dart';
import 'spending_report.dart' show ReportData;

/// Whether the ribbon has a trunk worth splitting, or nothing came in to
/// divide.
///
/// [ReportData.keptFraction] already answers "how much of what came in
/// stayed" with a defensible `0` whenever nothing came in -- but that `0`
/// stands for two different stories: "you kept none of what arrived" and
/// "nothing arrived, so the question does not apply". Painting the same
/// full-width spent branch for both would tell the second story as if it
/// were the first, so the two are told apart before a single point is
/// plotted rather than papered over with one more clamp.
enum RibbonMode {
  /// A real trunk to divide: [RibbonGeometry.keptW] and
  /// [RibbonGeometry.spentW] are a true proportion of what came in.
  split,

  /// Nothing came in this period. The trunk is drawn hollow rather than
  /// filled, and nothing is drawn beneath it -- a share of a period with no
  /// income is not a small share, it is an undefined one, and an invented
  /// bar would be read as a real measurement.
  noIncome,
}

/// The ribbon's horizontal geometry at a given canvas width, computed once so
/// painting and a test read the identical numbers.
///
/// Kept free of `pdf`'s drawing types on purpose: a test holding this to true
/// proportion should not have to ask a canvas to answer a question about
/// arithmetic.
class RibbonGeometry {
  const RibbonGeometry({
    required this.mode,
    required this.topX,
    required this.topW,
    required this.keptW,
    required this.spentW,
    required this.overspent,
  });

  final RibbonMode mode;

  /// Left edge and width of the trunk bar the ribbon fans out from.
  final double topX;
  final double topW;

  /// The two branches' share of [topW]. Both are `0` when [mode] is
  /// [RibbonMode.noIncome] -- there is nothing to share, not a vanishingly
  /// small share.
  final double keptW;
  final double spentW;

  /// True when more left than arrived. Kept still holds to `0` rather than a
  /// negative width -- a share of the trunk cannot run past the trunk's own
  /// edges -- but the fact of the overspend cannot just vanish with the
  /// negative sign, which is why the caller carries it through to the
  /// legend's wording rather than trying to draw it.
  final bool overspent;
}

/// Computes [RibbonGeometry] for a canvas of the given width. Pure
/// arithmetic: no division happens on a figure that can be zero, so there is
/// no case here that produces NaN rather than a defensible number.
RibbonGeometry ribbonGeometry(ReportData data, double width) {
  final topW = width * .44;
  final topX = (width - topW) / 2;
  if (data.receivedMinor <= 0) {
    return RibbonGeometry(
      mode: RibbonMode.noIncome,
      topX: topX,
      topW: topW,
      keptW: 0,
      spentW: 0,
      overspent: false,
    );
  }
  // keptFraction is already held to [0, 1] by ReportData itself, including
  // the overspend case (a negative fraction clamped to 0) -- reused rather
  // than re-derived, so the ribbon can never disagree with the number the
  // legend beneath it is also reading.
  final keptW = topW * data.keptFraction;
  return RibbonGeometry(
    mode: RibbonMode.split,
    topX: topX,
    topW: topW,
    keptW: keptW,
    spentW: topW - keptW,
    overspent: data.spentMinor > data.receivedMinor,
  );
}

/// The three tones the ribbon is ever allowed to reach for, named so a
/// reviewer checking "no tone outside the passed paper" has one call site per
/// tone to compare rather than the whole painter.
PdfColor ribbonTrunkTone(ReportPaper paper) => paper.ink;
PdfColor ribbonKeptTone(ReportPaper paper) => paper.keep;
PdfColor ribbonSpentTone(ReportPaper paper) => paper.spend;

/// The ribbon at full measure: everything that came in, splitting into the
/// share still yours and the share that left, at true proportion -- Home's
/// own object, opening the report the way Home opens the app.
///
/// Drawn with solid fills rather than the on-screen [FlowShape]'s translucent
/// ones. [paperTone] only measures a palette's tones at full strength against
/// the page; a fill thinned to Home's 34% or 50% alpha is a tone that
/// measurement never looked at, and on an already-graphite tone the result is
/// exactly the kind of pale, printer-losable fill this page is not allowed to
/// introduce.
class RibbonHero implements ReportHero {
  const RibbonHero();

  @override
  ReportTemplate get template => ReportTemplate.ribbon;

  @override
  List<pw.Widget> build(ReportPaper paper) {
    final data = paper.data;
    if (data.isEmpty) return [_nothing(paper)];
    return [
      _eyebrow('What came in, and what happened to it', paper),
      pw.SizedBox(height: 10),
      // The trunk of the ribbon below is this figure. It was never printed:
      // it existed only as the denominator of two percentages, so the page
      // showed the parts of a total it never named.
      _cameIn(data, paper),
      pw.SizedBox(height: 14),
      pw.SizedBox(
        height: 150,
        width: double.infinity,
        child: pw.CustomPaint(
          painter: (canvas, size) => paintRibbon(canvas, size, data, paper),
        ),
      ),
      pw.SizedBox(height: 14),
      _legend(data, paper),
    ];
  }

  pw.Widget _nothing(ReportPaper paper) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Nothing moved in this period.',
        style: pw.TextStyle(font: paper.bold, fontSize: 17, color: paper.ink),
      ),
      pw.SizedBox(height: 8),
      pw.Text(
        'No transactions fall inside these dates, so there is nothing for '
        'the ribbon to split.',
        style: pw.TextStyle(fontSize: 10, color: paper.muted),
      ),
    ],
  );

  pw.Widget _eyebrow(String text, ReportPaper paper) => pw.Text(
    text.toUpperCase(),
    style: pw.TextStyle(
      font: paper.mono,
      fontSize: 7.5,
      color: paper.muted,
      letterSpacing: 2,
    ),
  );

  /// The three figures the ribbon states in words, beside the shape that
  /// states them in ink -- "moved" only appears when there is one to name,
  /// exactly as the picture above it only draws a branch worth drawing.
  pw.Widget _legend(ReportData data, ReportPaper paper) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(child: _stillYours(data, paper)),
      pw.Expanded(child: _gone(data, paper)),
    ],
  );

  /// Everything that arrived, which is what the ribbon divides.
  pw.Widget _cameIn(ReportData data, ReportPaper paper) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      pw.Text(
        paper.money(data.receivedMinor),
        style: pw.TextStyle(
          font: paper.bold,
          fontSize: 32,
          color: paper.ink,
          letterSpacing: -1.1,
        ),
      ),
      pw.SizedBox(width: 9),
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Text(
          'came in',
          style: pw.TextStyle(fontSize: 10, color: paper.muted),
        ),
      ),
    ],
  );

  /// "Still yours" never prints a negative amount. [ReportData.keptMinor] can
  /// go negative when the period spent more than it received, and the figure
  /// that would print is the true one -- but a minus sign in front of "still
  /// yours" reads as a typo, not as an overspend, so the overspend gets its
  /// own sentence instead of being smuggled into a number that cannot
  /// honestly show it.
  pw.Widget _stillYours(ReportData data, ReportPaper paper) {
    if (data.receivedMinor <= 0) {
      return _figure(
        'Still yours',
        paper.money(0),
        'nothing came in',
        paper.ink,
        paper,
      );
    }
    if (data.keptMinor < 0) {
      // A negative "kept" is not proof of an overspend. Money lent out comes
      // off what is still yours without ever joining what was spent, so a
      // month that received 100,000, spent 20,000 and lent 200,000 has a kept
      // of -120,000 and has overspent nothing at all. Printing "spent 120,000
      // more than came in" of that month is simply false, on a document
      // people keep and send on.
      final overspend = data.spentMinor - data.receivedMinor;
      return _figure(
        'Still yours',
        paper.money(0),
        overspend > 0
            ? 'spent ${paper.money(overspend)} more than came in'
            : '${paper.money(data.loanOutMinor)} went out on loans',
        paper.ink,
        paper,
      );
    }
    return _figure(
      'Still yours',
      paper.money(data.keptMinor),
      '${_percent(data.keptMinor, data.receivedMinor)} of it',
      paper.ink,
      paper,
    );
  }

  /// Unlike the kept fraction, "gone" is never clamped -- a period that spent
  /// more than it received should read "128% of it", not a silently capped
  /// 100%, because the overspend is exactly the fact this figure exists to
  /// state.
  pw.Widget _gone(ReportData data, ReportPaper paper) => _figure(
    'Gone',
    paper.money(data.spentMinor),
    data.receivedMinor > 0
        ? '${_percent(data.spentMinor, data.receivedMinor)} of it'
        : 'nothing came in to measure it against',
    paper.spend,
    paper,
  );

  pw.Widget _figure(
    String label,
    String value,
    String note,
    PdfColor tone,
    ReportPaper paper,
  ) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _eyebrow(label, paper),
      pw.SizedBox(height: 5),
      pw.Text(
        value,
        style: pw.TextStyle(
          font: paper.bold,
          fontSize: 19,
          color: tone,
          letterSpacing: -.6,
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Text(note, style: pw.TextStyle(fontSize: 8.5, color: paper.muted)),
    ],
  );

  /// Deliberately unclamped past 100 -- see [_gone].
  static String _percent(int part, int whole) {
    if (whole <= 0) return '0%';
    final value = (part / whole) * 100;
    return value < 10 && value > 0
        ? '${value.toStringAsFixed(1)}%'
        : '${value.round()}%';
  }
}

/// Paints the ribbon proper.
///
/// Curved with `PdfGraphics.curveTo` -- a real cubic Bézier -- rather than
/// composed from short straight segments. The `pdf` package's content stream
/// has a native curve operator (PDF's `c`), so one `curveTo` call is drawn
/// exactly by whatever opens the file; a fan of line segments would need
/// dozens of them to read as smooth at this size, would still be a polygon
/// under a printer's higher DPI or a reader's zoom, and would cost that many
/// more instructions in the saved file for a worse result. [FlowShape] on
/// screen and the flow figure already in `spending_report.dart` both reach
/// for the same operation for the same reason.
void paintRibbon(
  PdfGraphics canvas,
  PdfPoint size,
  ReportData data,
  ReportPaper paper,
) {
  final geometry = ribbonGeometry(data, size.x);
  const barH = 9.0;
  final topY = size.y - barH;
  const botY = 2.0;

  if (geometry.mode == RibbonMode.noIncome) {
    // Stroked, not filled: a hollow trunk reads as "nothing passed through
    // here" on its own, and nothing is drawn beneath it because a share of
    // nothing has no honest width to give it -- see RibbonMode.noIncome.
    canvas
      ..setStrokeColor(ribbonTrunkTone(paper))
      ..setLineWidth(1.1)
      ..drawRect(geometry.topX, topY, geometry.topW, barH)
      ..strokePath();
    return;
  }

  final margin = size.x * .06;
  final keptBotX = margin;
  final spentBotX = size.x - margin - geometry.spentW;
  final splitX = geometry.topX + geometry.keptW;

  final yTop = topY;
  final c1 = topY - (topY - botY - barH) * .42;
  final c2 = topY - (topY - botY - barH) * .60;
  final barTop = botY + barH;

  void ribbon(
    double aTop,
    double bTop,
    double aBot,
    double bBot,
    PdfColor color,
  ) {
    canvas
      ..setFillColor(color)
      ..moveTo(aTop, yTop)
      ..curveTo(aTop, c1, aBot, c2, aBot, barTop)
      ..lineTo(bBot, barTop)
      ..curveTo(bBot, c2, bTop, c1, bTop, yTop)
      ..closePath()
      ..fillPath();
  }

  // Guarded rather than always called: a branch that is genuinely zero --
  // nothing spent, or nothing kept -- earns a real zero-width absence, not a
  // degenerate path instruction sitting unseen in the file.
  if (geometry.keptW > 0) {
    ribbon(
      geometry.topX,
      splitX,
      keptBotX,
      keptBotX + geometry.keptW,
      ribbonKeptTone(paper),
    );
  }
  if (geometry.spentW > 0) {
    ribbon(
      splitX,
      geometry.topX + geometry.topW,
      spentBotX,
      spentBotX + geometry.spentW,
      ribbonSpentTone(paper),
    );
  }

  canvas
    ..setFillColor(ribbonTrunkTone(paper))
    ..drawRect(geometry.topX, topY, geometry.topW, barH)
    ..fillPath();
  if (geometry.keptW > 0) {
    canvas
      ..setFillColor(ribbonKeptTone(paper))
      ..drawRect(keptBotX, botY, geometry.keptW, barH)
      ..fillPath();
  }
  if (geometry.spentW > 0) {
    canvas
      ..setFillColor(ribbonSpentTone(paper))
      ..drawRect(spentBotX, botY, geometry.spentW, barH)
      ..fillPath();
  }
}
