import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'report_hero.dart';

/// 12 o'clock is index 0; the rest follow clockwise -- the exact convention
/// `Chronograph` draws with on Insights, restated here in degrees rather than
/// imported, because this file has to keep compiling and testing on its own
/// while `lib/features/insights/` stays off limits to touch.
double dialAngleDegrees(int index, int count) => -90 + index * (360 / count);

/// A tick's radial length, anchored at a fixed outer radius and grown
/// *inward* toward the hub -- the same interpolation the screen uses, scaled
/// against the largest share actually being drawn rather than a fixed 100%,
/// so one dominant category cannot flatten every other tick to the floor.
/// [minLen] is also the floor a share of nearly nothing still draws at: the
/// length can never reach zero, which is what keeps a 0.4% category visible
/// next to a 23% one instead of vanishing.
double dialTickLength(
  double fraction,
  double maxFraction, {
  required double minLen,
  required double maxLen,
}) {
  if (maxFraction <= 0) return minLen;
  final t = (fraction / maxFraction).clamp(0.0, 1.0);
  return minLen + t * (maxLen - minLen);
}

/// Where a tick at [angleDeg] and [radius] actually lands in *this* canvas's
/// own coordinates.
///
/// The angle convention above was written against a screen `Canvas`, whose y
/// grows downward, so "clockwise" there falls out of ordinary trigonometry.
/// A PDF page's y grows upward instead -- the same angle run through the
/// same formula unchanged would draw counter-clockwise, silently mirroring
/// the one thing this hero exists to keep faithful. Negating the y term is
/// the entire fix, which is exactly why it is worth its own named function
/// rather than four call sites each remembering the minus sign on their own.
(double, double) dialTickPoint(
  double centerX,
  double centerY,
  double angleDeg,
  double radius,
) {
  final rad = angleDeg * math.pi / 180;
  return (centerX + radius * math.cos(rad), centerY - radius * math.sin(rad));
}

/// The dial: where the money went, drawn as a rim of markers rather than a
/// donut, exactly as Insights draws it -- radial length is share, 12 o'clock
/// is the largest, the rest fall away clockwise. The spec plate beneath it
/// exists only on paper: a screen dial can be tapped for a category's exact
/// reading, but nothing here can be tapped, so every category this report
/// has to name has to be named and numbered in the plate whether or not it
/// was legible enough to earn a label on the rim itself.
class DialHero implements ReportHero {
  const DialHero();

  @override
  ReportTemplate get template => ReportTemplate.dial;

  /// Below this many categories a dial has no spread to show: two ticks are
  /// just two ticks 180 degrees apart with nothing to compare them against,
  /// and one is a single spoke stating "100%", true and useless. The same
  /// floor as `Chronograph.minForDial`, restated rather than imported for the
  /// reason given on [dialAngleDegrees].
  static const _floor = 3;

  /// The dial's printed diameter, deliberately short of the screen's own 280
  /// logical pixels rather than stretched to answer for the page's width.
  ///
  /// Growing the circle adds no information -- every tick's length is
  /// already a *ratio*, so doubling the canvas doubles every tick by the
  /// same factor and nobody reads the drawing any more precisely for it. What
  /// growing it *would* cost is the room the spec plate needs, and the plate
  /// carries the one thing paper cannot do without: every category's exact
  /// figure, named, with nothing to tap for the rest. So the dial keeps its
  /// own recognisable size and sits beside the plate rather than floating
  /// alone in the middle of a page it does not need to fill.
  static const boxSize = 200.0;

  static const _gap = 22.0;

  // Proportions lifted directly from `_Geo` in chronograph.dart (a 280-unit
  // reference box: rim 118, tick anchor 114, tick length 7..41, hub 58) and
  // carried as fractions of [boxSize] rather than re-picked -- the dial only
  // reads as the same object if its bones are the same shape, not merely the
  // same colours.
  static const _rimFraction = 118 / 280;
  static const _outerFraction = 114 / 280;
  static const _minLenFraction = 7 / 280;
  static const _maxLenFraction = 41 / 280;
  static const _hubFraction = 58 / 280;

  @override
  List<pw.Widget> build(ReportPaper paper) {
    final categories = paper.data.byCategory;
    final total = categories.fold<int>(0, (sum, entry) => sum + entry.value);

    if (categories.isEmpty) {
      return [
        _header(paper, 0),
        pw.SizedBox(height: 10),
        pw.Text(
          'Categorised spending will appear here.',
          style: pw.TextStyle(fontSize: 10.5, color: paper.muted),
        ),
      ];
    }

    if (categories.length == 1) {
      final entry = categories.single;
      return [
        _header(paper, 1),
        pw.SizedBox(height: 12),
        pw.Text(
          paper.money(entry.value),
          style: pw.TextStyle(
            font: paper.bold,
            fontSize: 27,
            color: paper.ink,
            letterSpacing: -.8,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          '${_percent(entry.value, total)} · ${entry.key.toUpperCase()}',
          style: pw.TextStyle(
            font: paper.mono,
            fontSize: 8,
            color: paper.muted,
            letterSpacing: .6,
          ),
        ),
      ];
    }

    if (categories.length < _floor) {
      return [
        _header(paper, categories.length),
        pw.SizedBox(height: 12),
        _plate(paper, categories, total),
      ];
    }

    return [
      _header(paper, categories.length),
      pw.SizedBox(height: 16),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: boxSize,
            height: boxSize,
            child: pw.Stack(
              alignment: pw.Alignment.center,
              children: [
                pw.CustomPaint(
                  // Given explicitly rather than left to default to zero: a
                  // `Stack` lays its non-positioned children out with loose
                  // constraints, and an unsized `CustomPaint` resolves that
                  // to its own zero-size default rather than growing to fill
                  // the box the way a `SizedBox`-wrapped one elsewhere in
                  // this report can rely on its parent's tight constraints
                  // to do.
                  size: const PdfPoint(boxSize, boxSize),
                  painter: (canvas, size) =>
                      _paintDial(canvas, size, paper, categories, total),
                ),
                pw.Center(
                  child: pw.Text(
                    '${categories.length} CATEGORIES',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      font: paper.mono,
                      fontSize: 8,
                      color: paper.muted,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: _gap),
          pw.Expanded(child: _plate(paper, categories, total)),
        ],
      ),
    ];
  }

  // ---- furniture --------------------------------------------------------

  pw.Widget _header(ReportPaper paper, int count) => pw.Row(
    children: [
      pw.Expanded(
        child: pw.Text(
          'WHERE YOUR MONEY WENT',
          style: pw.TextStyle(
            font: paper.mono,
            fontSize: 7.5,
            color: paper.muted,
            letterSpacing: 2,
          ),
        ),
      ),
      if (count > 0)
        pw.Text(
          '$count ${count == 1 ? 'category' : 'categories'}',
          style: pw.TextStyle(
            font: paper.mono,
            fontSize: 7.5,
            color: paper.muted,
            letterSpacing: 2,
          ),
        ),
    ],
  );

  /// Every category, in the same descending order the rim reads in,
  /// stated in full regardless of how many there are -- the dial is only
  /// ever asked to show comparison, not the exact reading, so paper's own
  /// version of "tap a tick to find out" is a plate that never truncates.
  pw.Widget _plate(
    ReportPaper paper,
    List<MapEntry<String, int>> categories,
    int total,
  ) => pw.Column(
    children: [
      for (var i = 0; i < categories.length; i++)
        _plateRow(paper, categories[i], total, i == categories.length - 1),
    ],
  );

  pw.Widget _plateRow(
    ReportPaper paper,
    MapEntry<String, int> entry,
    int total,
    bool isLast,
  ) => pw.Container(
    decoration: isLast
        ? null
        : pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: paper.rule)),
          ),
    padding: const pw.EdgeInsets.symmetric(vertical: 5.5),
    child: pw.Row(
      children: [
        pw.Container(width: 8, height: 8, color: paper.toneOf(entry.key)),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Text(
            entry.key,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(fontSize: 9.5, color: paper.ink),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.SizedBox(
          width: 34,
          child: pw.Text(
            _percent(entry.value, total),
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              font: paper.mono,
              fontSize: 8,
              color: paper.muted,
            ),
          ),
        ),
        pw.SizedBox(width: 10),
        pw.SizedBox(
          width: 64,
          child: pw.Text(
            paper.money(entry.value),
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              font: paper.bold,
              fontSize: 9.5,
              color: paper.ink,
            ),
          ),
        ),
      ],
    ),
  );

  static String _percent(int part, int whole) =>
      whole <= 0 ? '0.0%' : '${(part / whole * 100).toStringAsFixed(1)}%';

  // ---- the drawing --------------------------------------------------------

  /// The rim and hub are true circles, so they are drawn with
  /// [PdfGraphics.drawEllipse] (equal radii) -- `pdf` has no dedicated circle
  /// primitive, but this one composes the identical four-Bezier
  /// approximation `Canvas.drawCircle` uses under the hood, so it is not an
  /// approximation of an approximation. Every tick is a straight
  /// [PdfGraphics.drawLine] from the rim inward, which is all a radial mark
  /// ever was on the screen either -- `_ChronographPainter` never draws an
  /// arc for a tick, only a line and a dot at its tip, so there is no wedge
  /// or pie-slice geometry to reach for here that the reference itself does
  /// not use.
  void _paintDial(
    PdfGraphics canvas,
    PdfPoint size,
    ReportPaper paper,
    List<MapEntry<String, int>> categories,
    int total,
  ) {
    final n = categories.length;
    if (n == 0) return;
    final cx = size.x / 2;
    final cy = size.y / 2;
    final rim = size.x * _rimFraction;
    final outer = size.x * _outerFraction;
    final minLen = size.x * _minLenFraction;
    final maxLen = size.x * _maxLenFraction;
    final hub = size.x * _hubFraction;

    final fractions = [
      for (final entry in categories) total <= 0 ? 0.0 : entry.value / total,
    ];
    final maxFraction = fractions.fold<double>(0, math.max);

    // The case-back: always drawn, never part of the reading itself, same as
    // on screen.
    canvas
      ..setStrokeColor(paper.rule)
      ..setLineWidth(.75);
    canvas.drawEllipse(cx, cy, rim, rim);
    canvas.strokePath();
    canvas.drawEllipse(cx, cy, hub, hub);
    canvas.strokePath();

    for (var i = 0; i < n; i++) {
      final angle = dialAngleDegrees(i, n);
      final len = dialTickLength(
        fractions[i],
        maxFraction,
        minLen: minLen,
        maxLen: maxLen,
      );
      final (ox, oy) = dialTickPoint(cx, cy, angle, outer);
      final (ix, iy) = dialTickPoint(cx, cy, angle, outer - len);
      final color = paper.toneOf(categories[i].key);

      canvas
        ..setStrokeColor(color)
        ..setLineWidth(1.4)
        ..setLineCap(PdfLineCap.round)
        ..drawLine(ox, oy, ix, iy)
        ..strokePath();
      canvas.setFillColor(color);
      canvas.drawEllipse(ix, iy, 1.5, 1.5);
      canvas.fillPath();
    }

    // The centre pin, same as the screen's always-drawn dot -- an anchor for
    // the eye, not a reading. No needle: a needle is a record of *motion*,
    // and a printed page has none to record.
    canvas.setFillColor(paper.muted);
    canvas.drawEllipse(cx, cy, 1.8, 1.8);
    canvas.fillPath();
  }
}
