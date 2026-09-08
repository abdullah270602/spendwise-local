import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'report_hero.dart';
import 'spending_report.dart' show ReportData;

/// The trace: this period against the one before it, as one continuous line
/// that leaves the centre and returns to it once per category.
///
/// The drawing itself is the screen's own `Seismograph`, ported rather than
/// reinvented -- the same per-row bump (a category never reads as "becoming"
/// its neighbour, because every row's on-curve points sit at the centre and
/// nowhere else), the same fixed global scale (a swing of 260% always
/// reaches the lane's edge, whatever else is on this page, which is the only
/// way a calm period and a violent one can look different from each other),
/// and the same clamp-with-a-chevron for whatever exceeds it. `ReportData`
/// does not carry the screen's `CategoryAnalytics` -- only the two ranked
/// category totals a report already needed for "the change" -- so the union
/// of categories, the money-moved sort and the per-row shape are recomputed
/// here from those totals directly, rather than smuggling a screen-only type
/// into a report.
///
/// Paper adds one rule the screen does not have to keep: there is no tap to
/// reveal a figure, so every row states its category and its exact amount in
/// the names column, not only the percentage beside the curve.
class TraceHero implements ReportHero {
  const TraceHero();

  @override
  ReportTemplate get template => ReportTemplate.trace;

  static const _namesWidth = 150.0;

  /// Reserved so a label near the lane's edge never collides with the next
  /// row's own text -- mirrors `Seismograph._labelReserve`.
  static const _labelReserve = 40.0;
  static const _verticalPad = 8.0;

  /// Thirty categories must all still be named, one line each -- paper
  /// cannot fold a tail into "+K more" the way the screen does, because
  /// folding would mean the folded categories are no longer individually
  /// named, which is the one requirement paper adds to this drawing. Rows
  /// shrink to fit instead: comfortable at up to about twenty, still legible
  /// at thirty.
  static const _minRowHeight = 9.0;
  static const _maxRowHeight = 17.0;
  static const _rowHeightBudget = 340.0;

  /// The swing that exactly reaches the lane's edge under the fixed scale --
  /// identical to `Seismograph._referencePercent`, not a fresh number picked
  /// for paper. Two different constants here and on screen would mean a
  /// category reads as "ordinary" on one and "extreme" on the other for a
  /// figure that has not changed.
  static const _referencePercent = 260.0;

  @override
  List<pw.Widget> build(ReportPaper paper) {
    final figures = traceRowFigures(paper.data);

    if (figures.isEmpty) {
      return _statement(
        paper,
        'Nothing moved.',
        'No category took money in ${paper.data.request.label} or in '
            '${paper.data.previousLabel}.',
      );
    }

    // Every category in this period would otherwise plot as new -- there is
    // no earlier figure anywhere to divide by -- and a lane full of "new"
    // rings reads as a busy shape, not as the true fact, which is that
    // there is nothing behind this period to compare it against at all.
    // Said in words instead, once, rather than drawn as a shape that could
    // be mistaken for a calm (or any) month.
    if (paper.data.previousByCategory.isEmpty) {
      return _statement(
        paper,
        'Nothing before this to trace against.',
        'The ledger has no record of ${paper.data.previousLabel}, so there '
            "is no 'before' for this drawing to leave and return to. It "
            'resumes from the next period this one has behind it.',
      );
    }

    final rowHeight = _rowHeight(figures.length);
    final totalHeight = _verticalPad * 2 + rowHeight * figures.length;
    final curveWidth = math.max(60.0, paper.width - _namesWidth);
    final centerX = curveWidth / 2;
    final maxDeviation = math.max(6.0, centerX - _labelReserve);

    final rows = <_LaidRow>[
      for (var i = 0; i < figures.length; i++)
        _LaidRow(
          figure: figures[i],
          y0: _verticalPad + i * rowHeight,
          y1: _verticalPad + (i + 1) * rowHeight,
          x: centerX + figures[i].deviationFraction * maxDeviation,
        ),
    ];

    return [
      _eyebrow(paper, 'What changed', 'vs ${paper.data.previousLabel}'),
      pw.SizedBox(height: 10),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: _namesWidth,
            child: pw.Column(
              children: [for (final row in rows) _nameCell(row, paper)],
            ),
          ),
          pw.SizedBox(
            width: curveWidth,
            height: totalHeight,
            // A `Stack`, not a bare `CustomPaint`: the curve is real ink
            // drawn on `PdfGraphics` (below), but the percentage beside each
            // apex is ordinary `pw.Text`, laid out and measured by the
            // widget tree the normal way. `PdfGraphics.drawString` needs a
            // `Context` to resolve a `pw.Font` into the low-level `PdfFont`
            // it draws with, and a `CustomPaint` painter is only ever handed
            // a canvas and a size -- so text has to live one layer up, as a
            // widget positioned at the same point the canvas drew its mark.
            child: pw.Stack(
              children: [
                pw.Positioned.fill(
                  child: pw.CustomPaint(
                    painter: (canvas, size) =>
                        _paintTrace(canvas, size, rows, centerX, paper),
                  ),
                ),
                for (final row in rows) _label(row, centerX, curveWidth, paper),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  // ---- layout -----------------------------------------------------------

  double _rowHeight(int count) => count <= 0
      ? _maxRowHeight
      : (_rowHeightBudget / count).clamp(_minRowHeight, _maxRowHeight);

  pw.Widget _eyebrow(ReportPaper paper, String lead, String trailing) => pw.Row(
    children: [
      pw.Expanded(
        child: pw.Text(
          lead.toUpperCase(),
          style: pw.TextStyle(
            font: paper.mono,
            fontSize: 7.5,
            color: paper.muted,
            letterSpacing: 2,
          ),
        ),
      ),
      pw.Text(
        trailing.toUpperCase(),
        style: pw.TextStyle(
          font: paper.mono,
          fontSize: 7.5,
          color: paper.muted,
          letterSpacing: 2,
        ),
      ),
    ],
  );

  List<pw.Widget> _statement(
    ReportPaper paper,
    String headline,
    String detail,
  ) => [
    pw.Text(
      headline,
      style: pw.TextStyle(font: paper.bold, fontSize: 15, color: paper.ink),
    ),
    pw.SizedBox(height: 7),
    pw.Text(
      detail,
      style: pw.TextStyle(font: paper.sans, fontSize: 9.5, color: paper.muted),
    ),
  ];

  /// The names column: a tone chip, the category (struck through once it has
  /// stopped), and its exact amount -- the one thing paper cannot leave to a
  /// tap the way the screen's own semantics label can.
  pw.Widget _nameCell(_LaidRow row, ReportPaper paper) {
    final figure = row.figure;
    final loud =
        !figure.isNew &&
        !figure.isStopped &&
        (figure.changePercent?.abs() ?? 0) >= 25;
    final displayAmount = figure.isStopped
        ? figure.previousAmountMinor
        : figure.amountMinor;
    final prefix = figure.isStopped ? 'was ' : '';

    return pw.Container(
      height: row.y1 - row.y0,
      alignment: pw.Alignment.centerLeft,
      child: pw.Row(
        children: [
          pw.Container(
            width: 5,
            height: 5,
            color: paper.toneOf(figure.category),
          ),
          pw.SizedBox(width: 5),
          pw.Expanded(
            child: pw.Text(
              figure.category,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(
                font: loud ? paper.bold : paper.sans,
                fontSize: 7.6,
                color: loud ? paper.ink : paper.muted,
                decoration: figure.isStopped
                    ? pw.TextDecoration.lineThrough
                    : pw.TextDecoration.none,
                decorationColor: paper.rule,
              ),
            ),
          ),
          pw.SizedBox(width: 4),
          pw.Text(
            '$prefix${paper.money(displayAmount)}',
            style: pw.TextStyle(
              font: paper.mono,
              fontSize: 6.2,
              color: paper.muted,
            ),
          ),
        ],
      ),
    );
  }

  /// The percentage (or `NEW` / `· stopped`) beside a row's own apex --
  /// positioned at exactly the point the canvas drew its marker, using the
  /// same `x`/`y` this build already computed once for the curve.
  pw.Widget _label(
    _LaidRow row,
    double centerX,
    double curveWidth,
    ReportPaper paper,
  ) {
    final figure = row.figure;
    final pct = figure.changePercent;
    final String text;
    if (figure.isNew) {
      text = 'NEW';
    } else if (pct == 0) {
      text = '0%';
    } else {
      text = '${_formatPercent(pct!)}${figure.isStopped ? ' · stopped' : ''}';
    }

    final rowColor = _rowColor(figure, paper);
    final labelColor = figure.isClamped
        ? rowColor
        : figure.isNew
        ? paper.mine
        : ((pct?.abs() ?? 0) >= 25 ? paper.ink : paper.muted);

    final style = pw.TextStyle(
      font: paper.mono,
      fontSize: 6.6,
      color: labelColor,
      fontWeight: figure.isClamped ? pw.FontWeight.bold : pw.FontWeight.normal,
    );

    final yMid = (row.y0 + row.y1) / 2;
    const halfTextHeight = 4.2;
    final top = yMid - halfTextHeight;

    if (figure.isClamped) {
      final positive = (pct ?? 0) > 0;
      return positive
          ? pw.Positioned(
              top: top,
              right: 3,
              child: pw.Text(text, style: style),
            )
          : pw.Positioned(
              top: top,
              left: 3,
              child: pw.Text(text, style: style),
            );
    }

    final offset = figure.isFlat ? 5.0 : 6.0;
    if (row.x >= centerX) {
      return pw.Positioned(
        top: top,
        left: row.x + offset,
        child: pw.Text(text, style: style),
      );
    }
    return pw.Positioned(
      top: top,
      right: curveWidth - (row.x - offset),
      child: pw.Text(text, style: style),
    );
  }

  static String _formatPercent(double pct) {
    final digits = pct.abs() >= 100 ? 0 : 1;
    final sign = pct > 0 ? '+' : '';
    return '$sign${pct.toStringAsFixed(digits)}%';
  }

  static PdfColor _rowColor(TraceRowFigure figure, ReportPaper paper) {
    if (figure.isNew || figure.isFlat) return paper.mine;
    return (figure.changePercent ?? 0) > 0 ? paper.spend : paper.keep;
  }

  static PdfColor _fillColor(TraceRowFigure figure, ReportPaper paper) =>
      (figure.isNew || (figure.changePercent ?? 0) > 0)
      ? paper.spend
      : paper.keep;

  // ---- drawing ------------------------------------------------------------

  /// The curve, the tinted area beneath it, the marker and (for the one row
  /// past the reference swing) its chevron. Every shape is built from real
  /// cubic Béziers on `PdfGraphics` (`curveTo`, mirroring `Path.cubicTo` on
  /// screen) rather than approximated with straight segments, because the
  /// per-row bump only reads as one continuous stroke -- never a sequence of
  /// short diagonal hops -- if its curvature is real.
  ///
  /// `PdfGraphics` draws bottom-up (page-space, not widget-space), so every
  /// row's own top-down `y0`/`y1` is flipped once, here, rather than carried
  /// as two different conventions through the rest of this file.
  static void _paintTrace(
    PdfGraphics canvas,
    PdfPoint size,
    List<_LaidRow> rows,
    double centerX,
    ReportPaper paper,
  ) {
    double flip(double y) => size.y - y;

    canvas
      ..setStrokeColor(paper.rule)
      ..setLineWidth(0.8)
      ..drawLine(centerX, flip(2), centerX, flip(size.y - 2))
      ..strokePath();

    for (final row in rows) {
      final figure = row.figure;
      final y0 = flip(row.y0);
      final y1 = flip(row.y1);
      final yMid = (y0 + y1) / 2;
      final x = row.x;
      final color = _rowColor(figure, paper);

      if (!figure.isFlat) {
        _traceCurve(canvas, centerX: centerX, x: x, y0: y0, y1: y1, yMid: yMid);
        canvas
          ..closePath()
          ..setFillColor(_fillColor(figure, paper))
          // The screen tints this area at 13% opacity against a near-black
          // ground; that reads on a backlit panel but risks disappearing
          // into a home printer's own dot gain once the ground is paper --
          // the physical dots a cheap inkjet or laser lays down do not
          // reliably resolve a fill that light. 16% is chosen to survive
          // that without reading as a second solid block beside the ink
          // line drawn over it.
          ..setGraphicState(const PdfGraphicState(fillOpacity: .16))
          ..fillPath()
          ..setGraphicState(const PdfGraphicState(fillOpacity: 1));
      }

      // A new category's whole row -- its curve and its ring -- is dashed
      // rather than solid, the same distinction the screen draws: its
      // lateral position is a share of spending, not a measurement, and a
      // dashed line says so at a glance, before a reader gets as far as the
      // "NEW" beside it.
      if (figure.isNew) canvas.setLineDashPattern(const [2, 1.5]);
      _traceCurve(canvas, centerX: centerX, x: x, y0: y0, y1: y1, yMid: yMid);
      canvas
        ..setStrokeColor(color)
        ..setLineWidth(1.1)
        ..strokePath();
      if (figure.isNew) canvas.setLineDashPattern();

      if (figure.isFlat) {
        const half = 3.0;
        canvas
          ..setFillColor(paper.mine)
          ..moveTo(x, yMid - half)
          ..lineTo(x + half, yMid)
          ..lineTo(x, yMid + half)
          ..lineTo(x - half, yMid)
          ..closePath()
          ..fillPath();
      } else if (figure.isNew) {
        canvas
          ..setStrokeColor(paper.mine)
          ..setLineWidth(1.0)
          ..setLineDashPattern(const [2, 1.5])
          ..drawEllipse(x, yMid, 2.6, 2.6)
          ..strokePath()
          ..setLineDashPattern();
      } else {
        canvas
          ..setFillColor(color)
          ..drawEllipse(x, yMid, 2.0, 2.0)
          ..fillPath();
      }

      if (figure.isClamped) {
        final dir = (figure.changePercent ?? 0) > 0 ? 1.0 : -1.0;
        final x1 = x + dir * 2, x2 = x + dir * 6;
        canvas
          ..setFillColor(color)
          ..moveTo(x1, yMid - 3)
          ..lineTo(x2, yMid)
          ..lineTo(x1, yMid + 3)
          ..closePath()
          ..fillPath();
      }
    }
  }

  /// One row's own bump: leaves the centre spine at its top edge, bows out
  /// to `(x, yMid)`, returns to the centre spine at its bottom edge --
  /// identical control-point placement to `Seismograph`'s own `_curvePath`
  /// (each control point sits 62% of the half-span toward the far end), so
  /// the two objects are recognisably the same curve, not a paper
  /// approximation of it. Left unfilled and unstroked -- the caller decides
  /// which (or both) to do with the path this leaves open.
  static void _traceCurve(
    PdfGraphics canvas, {
    required double centerX,
    required double x,
    required double y0,
    required double y1,
    required double yMid,
  }) {
    final span = (y1 - y0) / 2;
    final c1y = y0 + span * 0.62;
    final c2y = yMid - span * 0.62;
    final c3y = yMid + span * 0.62;
    final c4y = y1 - span * 0.62;
    canvas
      ..moveTo(centerX, y0)
      ..curveTo(centerX, c1y, x, c2y, x, yMid)
      ..curveTo(x, c3y, centerX, c4y, centerX, y1);
  }
}

/// One row's place in the shape and the figures it stands for, before any
/// page width is known.
///
/// Public, and not `_`-prefixed, for one reason: a test that never renders a
/// page needs somewhere to hold the fixed global scale to account. This is
/// the seam -- the same role `_SeismographPainter.toString()` plays for a
/// widget test on screen, reading `largestDeviation` back without
/// recomputing the build's own layout math.
@immutable
class TraceRowFigure {
  const TraceRowFigure({
    required this.category,
    required this.amountMinor,
    required this.previousAmountMinor,
    required this.changePercent,
    required this.deviationFraction,
    required this.isNew,
    required this.isStopped,
    required this.isFlat,
    required this.isClamped,
  });

  final String category;
  final int amountMinor;
  final int previousAmountMinor;

  /// Null exactly when [isNew]: there is no previous figure to divide by,
  /// which is undefined, not an infinite increase and not zero either.
  final double? changePercent;

  /// This row's deviation as a signed fraction of the lane's own half width,
  /// under the fixed global scale -- a swing of exactly 260% reaches ±1.0,
  /// whatever else is on this page. Multiplying by an actual `maxDeviation`
  /// in points is the only step left once a real page width is known.
  final double deviationFraction;

  final bool isNew;
  final bool isStopped;

  /// True only for a real, unchanged (0%) reading -- never for [isNew],
  /// whose lack of a previous figure is a different fact from having moved
  /// by nothing.
  final bool isFlat;

  /// True once this row's real swing exceeds the reference and has been
  /// pinned to the lane's edge -- its exact percentage is still what
  /// [changePercent] reports; only the drawn position is compressed.
  final bool isClamped;
}

/// Every category that moved money in either period, in `Seismograph`'s own
/// display order -- by money moved, largest first, not by percentage, so a
/// category that rose by a small fortune outranks one that merely doubled
/// from pocket change.
///
/// `ReportData` does not carry `CategoryAnalytics`; it only has the two
/// ranked category totals "the change" already needed, so the union of
/// categories, the sort and each row's shape are all recomputed here from
/// those totals directly. Never folds a tail into one aggregate row the way
/// the screen does past sixteen categories -- paper has no tap to recover a
/// folded category's own figure, so every category stays named through
/// however many rows that takes.
@visibleForTesting
List<TraceRowFigure> traceRowFigures(ReportData data) {
  final current = {for (final entry in data.byCategory) entry.key: entry.value};
  final previous = {
    for (final entry in data.previousByCategory) entry.key: entry.value,
  };
  final names = <String>{...current.keys, ...previous.keys}.toList();

  final entries =
      [
        for (final name in names)
          (
            category: name,
            amountMinor: current[name] ?? 0,
            previousAmountMinor: previous[name] ?? 0,
          ),
      ]..sort(
        (a, b) => (b.amountMinor - b.previousAmountMinor).abs().compareTo(
          (a.amountMinor - a.previousAmountMinor).abs(),
        ),
      );

  final totalNow = entries.fold<int>(
    0,
    (sum, entry) => sum + entry.amountMinor,
  );
  final safeTotalNow = totalNow == 0 ? 1 : totalNow;
  var maxShare = 1e-9;
  for (final entry in entries) {
    maxShare = math.max(maxShare, entry.amountMinor / safeTotalNow);
  }

  return [
    for (final entry in entries)
      _figureFor(
        entry,
        share: entry.amountMinor / safeTotalNow,
        maxShare: maxShare,
      ),
  ];
}

TraceRowFigure _figureFor(
  ({String category, int amountMinor, int previousAmountMinor}) entry, {
  required double share,
  required double maxShare,
}) {
  final isNew = entry.previousAmountMinor == 0 && entry.amountMinor > 0;
  final isStopped = entry.amountMinor == 0 && entry.previousAmountMinor > 0;

  // A brand-new category has no honest percentage to plot -- its previous
  // total is zero, so "now over previous" is division by zero, not infinity
  // and not zero either. It is placed by its share of this period's
  // spending instead, scaled into a sub-range that can never reach as far as
  // a real percentage would, so it can never be mistaken for one. A category
  // that stopped entirely is the opposite case: a real, well-defined -100%,
  // handled by the same signed-square-root scale as any other change.
  if (isNew) {
    final shareNorm = maxShare <= 0
        ? 0.0
        : math.sqrt((share / maxShare).clamp(0.0, 1.0));
    return TraceRowFigure(
      category: entry.category,
      amountMinor: entry.amountMinor,
      previousAmountMinor: entry.previousAmountMinor,
      changePercent: null,
      deviationFraction: 0.5 * (0.3 + 0.7 * shareNorm),
      isNew: true,
      isStopped: false,
      isFlat: false,
      isClamped: false,
    );
  }

  final pct =
      (entry.amountMinor - entry.previousAmountMinor) /
      entry.previousAmountMinor *
      100;

  if (pct == 0) {
    return TraceRowFigure(
      category: entry.category,
      amountMinor: entry.amountMinor,
      previousAmountMinor: entry.previousAmountMinor,
      changePercent: 0,
      deviationFraction: 0,
      isNew: false,
      isStopped: false,
      isFlat: true,
      isClamped: false,
    );
  }

  // Fixed once, not recomputed from whatever this period's own loudest
  // category happens to be: a per-period scale is the one thing that would
  // make a calm period and a violent one look equally busy, which is the
  // bug the screen version of this drawing shipped with and then fixed (see
  // `local/design/final-seismograph.html`, §4-5). REF_PCT is the swing that
  // exactly reaches the lane's edge; TraceHero._referencePercent is the same
  // 260 `Seismograph._referencePercent` uses, not a fresh number for paper.
  final capMagnitude = math.sqrt(TraceHero._referencePercent);
  final raw = _signedSquareRoot(pct).abs();
  final magnitude = math.min(raw, capMagnitude);
  final clamped = raw > capMagnitude + 1e-9;
  final sign = pct > 0 ? 1.0 : -1.0;
  return TraceRowFigure(
    category: entry.category,
    amountMinor: entry.amountMinor,
    previousAmountMinor: entry.previousAmountMinor,
    changePercent: pct,
    deviationFraction: sign * (magnitude / capMagnitude),
    isNew: false,
    isStopped: isStopped,
    isFlat: false,
    isClamped: clamped,
  );
}

double _signedSquareRoot(double v) =>
    v.isNegative ? -math.sqrt(-v) : math.sqrt(v);

class _LaidRow {
  const _LaidRow({
    required this.figure,
    required this.y0,
    required this.y1,
    required this.x,
  });

  final TraceRowFigure figure;

  /// Top-down, in points from the top of the drawing -- the same convention
  /// `pw.Positioned.top` uses, so a row's label lands exactly where its own
  /// curve was drawn without a second coordinate system to keep in sync.
  final double y0;
  final double y1;

  /// This row's apex, in the curve area's own local coordinates (0 at its
  /// left edge) -- already includes the centre offset and the fixed-scale
  /// deviation, so neither the painter nor the label recomputes it.
  final double x;
}
