import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../app/category_tones.dart';
import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../shell/spendwise_view_model.dart';
import 'spending_analytics.dart';

/// What changed since last period, as one continuous trace: each category
/// gets its own row, and each row leaves the centre line and returns to it
/// before the next one starts, so nothing ever reads as "this category became
/// that one" the way a plain dot-to-dot line would.
///
/// The deflection scale is fixed once, at a swing of [_referencePercent],
/// never recomputed from whatever this screen's own loudest category happens
/// to be -- a per-render scale is the one thing that would make a calm month
/// and a violent month look identically busy, which defeats the entire point
/// of drawing a silhouette a reader can recognise from one month to the next.
/// A category past that reference clamps at the lane's edge with a chevron
/// and prints its real figure in bold, rather than stretching the whole lane
/// to fit it.
///
/// [changes] is expected exactly as [SpendingAnalytics.categoryChanges]
/// already arrives: every category that moved in either period, ordered by
/// money moved (not by percentage) so a category that rose by 6,500 outranks
/// one that merely doubled from 350. Re-sorting it here would undo that.
class Seismograph extends StatelessWidget {
  const Seismograph({
    super.key,
    required this.changes,
    required this.tones,
    required this.selected,
    required this.onSelect,
    required this.currency,
  });

  final List<CategoryAnalytics> changes;
  final CategoryTones tones;

  /// The category the screen is filtered to, or null for no filter.
  final String? selected;

  /// Called with the tapped row's category, or null when the row that was
  /// already selected is tapped again -- the trace's own way back to
  /// everything, alongside the filter chips above it.
  final ValueChanged<String?> onSelect;
  final String currency;

  /// Below this many rows a silhouette has nothing to show: three points
  /// read exactly as well as three separate numbers would, so the section
  /// does not draw itself at all rather than draw something not worth its
  /// own weight. Mirrors the floor the Chronograph already draws for the
  /// same reason.
  static const _minCategories = 3;

  /// Past this many rows the whole point -- a shape recognised at a glance --
  /// stops being true, so the smallest tail (by the same money-moved order
  /// [changes] already arrives in) is folded into one aggregate row, the same
  /// rule Home already applies to its own category tail.
  static const _foldThreshold = 16;

  static const _namesWidth = 84.0;

  /// Reserved so a label near the lane's edge never collides with the next
  /// row's own text.
  static const _labelReserve = 48.0;
  static const _rowHeight = 25.0;
  static const _foldedRowHeight = 18.0;
  static const _verticalPad = 10.0;

  /// The swing that exactly reaches the lane's edge under the fixed scale.
  static const _referencePercent = 260.0;

  @override
  Widget build(BuildContext context) {
    if (changes.length < _minCategories) return const SizedBox.shrink();

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final folded = changes.length > _foldThreshold;
    final rowHeight = folded ? _foldedRowHeight : _rowHeight;
    final rows = _prepareRows(changes, selected: selected);
    final totalHeight = _verticalPad * 2 + rowHeight * rows.length;
    final targetFracs = {for (final row in rows) row.category: row.devFrac};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow(
          'What changed',
          trailing: Text('VS LAST PERIOD', style: SpendWiseType.eyebrow),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 360.0;
            final curveWidth = math.max(40.0, totalWidth - _namesWidth);
            final centerX = curveWidth / 2;
            final maxDeviation = math.max(6.0, centerX - _labelReserve);

            return SizedBox(
              height: totalHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _namesWidth,
                    child: Column(
                      children: [
                        for (final row in rows)
                          _NameCell(
                            row: row,
                            height: rowHeight,
                            selected: selected,
                            tone: row.isAggregate
                                ? SpendWiseColors.edge
                                : tones.of(row.category),
                            reduceMotion: reduceMotion,
                            currency: currency,
                            onTap: row.isAggregate
                                ? null
                                : () => _toggle(row.category),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TweenAnimationBuilder<Map<String, double>>(
                      tween: _DevFracTween(end: targetFracs),
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 800),
                      curve: Curves.easeOutQuint,
                      builder: (context, fracs, _) {
                        final geometry = _buildGeometry(
                          rows: rows,
                          fracs: fracs,
                          rowHeight: rowHeight,
                          centerX: centerX,
                          maxDeviation: maxDeviation,
                          curveWidth: curveWidth,
                        );
                        // First arrival draws the whole month in once,
                        // top to bottom, the way paper actually feeds
                        // through a real seismograph -- never touched
                        // again after that, so a later selection or a
                        // period switch does not replay it.
                        return TweenAnimationBuilder<double>(
                          tween: Tween(
                            begin: reduceMotion ? 1.0 : 0.0,
                            end: 1.0,
                          ),
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 1300),
                          curve: Curves.easeOutQuint,
                          builder: (context, reveal, _) {
                            // A quick, independent reply to a tap, not a
                            // value changing -- its own clock, sized like
                            // the sibling concepts' own selection replies
                            // rather than the long, settled entrance
                            // above it.
                            return TweenAnimationBuilder<double>(
                              tween: Tween(end: selected == null ? 0.0 : 1.0),
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              builder: (context, dim, _) => GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapUp: (details) {
                                  final index = geometry.rowIndexAt(
                                    details.localPosition,
                                  );
                                  if (index == null) return;
                                  final row = geometry.rows[index];
                                  if (row.isAggregate) return;
                                  _toggle(row.category);
                                },
                                child: CustomPaint(
                                  size: Size(curveWidth, totalHeight),
                                  painter: _SeismographPainter(
                                    rows: geometry.rows,
                                    centerX: centerX,
                                    maxDeviation: maxDeviation,
                                    reveal: reveal,
                                    dim: dim,
                                    selected: selected,
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  void _toggle(String category) =>
      onSelect(category == selected ? null : category);

  /// Every row this trace will draw, in display order: the categories that
  /// moved the most money, largest first, exactly as [changes] already
  /// arrives, with the smallest tail folded into one aggregate row once
  /// there are more than [_foldThreshold] of them.
  ///
  /// If the category the screen is filtered to would otherwise fall inside
  /// that folded tail, it is promoted into the visible head first -- a
  /// selection must never vanish into "+K more categories" out from under
  /// the reader who just tapped it.
  static List<_RowData> _prepareRows(
    List<CategoryAnalytics> changes, {
    required String? selected,
  }) {
    final head = changes.take(_foldThreshold).toList();
    final tail = changes.skip(_foldThreshold).toList();
    if (tail.isNotEmpty &&
        selected != null &&
        !head.any((item) => item.category == selected)) {
      final promotedIndex = tail.indexWhere(
        (item) => item.category == selected,
      );
      if (promotedIndex != -1) {
        final promoted = tail.removeAt(promotedIndex);
        final demoted = head.removeLast();
        tail.add(demoted);
        head.add(promoted);
      }
    }

    final entries = <_Entry>[
      for (final item in head)
        (
          category: item.category,
          amountMinor: item.amountMinor,
          previousAmountMinor: item.previousAmountMinor,
          isNew: item.isNew,
          isStopped: item.isStopped,
          pct: item.changePercent,
          isAggregate: false,
        ),
    ];
    if (tail.isNotEmpty) {
      final amount = tail.fold<int>(0, (sum, item) => sum + item.amountMinor);
      final previous = tail.fold<int>(
        0,
        (sum, item) => sum + item.previousAmountMinor,
      );
      entries.add((
        category: '+${tail.length} more categories',
        amountMinor: amount,
        previousAmountMinor: previous,
        isNew: previous == 0 && amount > 0,
        isStopped: amount == 0 && previous > 0,
        pct: previous == 0 ? null : (amount - previous) / previous * 100,
        isAggregate: true,
      ));
    }

    final totalNow = entries.fold<int>(0, (sum, e) => sum + e.amountMinor);
    final safeTotalNow = totalNow == 0 ? 1 : totalNow;
    var maxShare = 1e-9;
    for (final entry in entries) {
      maxShare = math.max(maxShare, entry.amountMinor / safeTotalNow);
    }

    return [
      for (final entry in entries)
        _rowFor(
          entry,
          share: entry.amountMinor / safeTotalNow,
          maxShare: maxShare,
        ),
    ];
  }

  static _RowData _rowFor(
    _Entry entry, {
    required double share,
    required double maxShare,
  }) {
    final shape = _shapeFor(
      isNew: entry.isNew,
      pct: entry.pct,
      share: share,
      maxShare: maxShare,
    );
    return _RowData(
      category: entry.category,
      devFrac: shape.devFrac,
      isFlat: shape.isFlat,
      isClamped: shape.isClamped,
      isNew: entry.isNew,
      isStopped: entry.isStopped,
      isAggregate: entry.isAggregate,
      pct: entry.pct,
      amountMinor: entry.amountMinor,
      previousAmountMinor: entry.previousAmountMinor,
    );
  }

  /// Where a row's deviation sits, as a signed fraction of the lane's half
  /// width -- independent of the widget's actual pixel width, so this can be
  /// tweened on its own and multiplied out to pixels once the real width is
  /// known.
  ///
  /// A brand-new category has no honest percentage to plot (its previous
  /// total is zero, so "now over previous" is division by zero, not
  /// infinity and not zero either) -- it is placed by its share of this
  /// period's spending instead, scaled into a modest sub-range that can
  /// never reach as far as a real percentage would, so it can never be
  /// mistaken for one. Everything else -- including a category that
  /// stopped entirely, which is a real, well-defined -100% -- goes through
  /// the same signed-square-root scale and clamp as any other change.
  static _RowShape _shapeFor({
    required bool isNew,
    required double? pct,
    required double share,
    required double maxShare,
  }) {
    if (isNew) {
      final shareNorm = maxShare <= 0
          ? 0.0
          : math.sqrt((share / maxShare).clamp(0.0, 1.0));
      return _RowShape(
        devFrac: 0.5 * (0.3 + 0.7 * shareNorm),
        isFlat: false,
        isClamped: false,
      );
    }
    if (pct == null || pct == 0) {
      return const _RowShape(devFrac: 0, isFlat: true, isClamped: false);
    }
    final capMagnitude = math.sqrt(_referencePercent);
    final raw = _signedSquareRoot(pct).abs();
    final magnitude = math.min(raw, capMagnitude);
    final clamped = raw > capMagnitude + 1e-9;
    final sign = pct > 0 ? 1.0 : -1.0;
    return _RowShape(
      devFrac: sign * (magnitude / capMagnitude),
      isFlat: false,
      isClamped: clamped,
    );
  }

  static double _signedSquareRoot(double v) =>
      v.isNegative ? -math.sqrt(-v) : math.sqrt(v);

  /// Builds every path, marker and label this frame paints, from the row
  /// data, the currently animated deviations and the layout this build was
  /// given -- used both to paint the trace and, given the same values, to
  /// test a tap against the shapes actually on screen. Mirrors
  /// `_buildFlowGeometry` in `shape_kit.dart` for exactly that reason.
  static _SeismographGeometry _buildGeometry({
    required List<_RowData> rows,
    required Map<String, double> fracs,
    required double rowHeight,
    required double centerX,
    required double maxDeviation,
    required double curveWidth,
  }) {
    final traceRows = <_TraceRow>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final y0 = _verticalPad + i * rowHeight;
      final y1 = _verticalPad + (i + 1) * rowHeight;
      final yMid = (y0 + y1) / 2;
      final frac = (fracs[row.category] ?? row.devFrac).clamp(-1.0, 1.0);
      final x = centerX + frac * maxDeviation;

      final path = _curvePath(
        centerX: centerX,
        x: x,
        y0: y0,
        y1: y1,
        yMid: yMid,
      );
      final areaPath = _curvePath(
        centerX: centerX,
        x: x,
        y0: y0,
        y1: y1,
        yMid: yMid,
      )..close();

      final tapRadius = math.min(rowHeight / 2 - 1, 14.0);
      final hitPath = Path()
        ..addPath(areaPath, Offset.zero)
        ..addOval(
          Rect.fromCircle(
            center: Offset(x, yMid),
            radius: math.max(tapRadius, 8.0),
          ),
        );

      final Path markerShape;
      if (row.isFlat) {
        const half = 4.0;
        markerShape = Path()
          ..moveTo(x, yMid - half)
          ..lineTo(x + half, yMid)
          ..lineTo(x, yMid + half)
          ..lineTo(x - half, yMid)
          ..close();
      } else if (row.isNew) {
        markerShape = Path()
          ..addOval(Rect.fromCircle(center: Offset(x, yMid), radius: 3.2));
      } else {
        markerShape = Path()
          ..addOval(Rect.fromCircle(center: Offset(x, yMid), radius: 2.6));
      }

      Path? chevronPath;
      if (row.isClamped) {
        final dir = (row.pct ?? 0) > 0 ? 1.0 : -1.0;
        final x1 = x + dir * 2, x2 = x + dir * 7;
        chevronPath = Path()
          ..moveTo(x1, yMid - 3.5)
          ..lineTo(x2, yMid)
          ..lineTo(x1, yMid + 3.5)
          ..close();
      }

      final color = row.isNew || row.isFlat
          ? SpendWiseColors.mine
          : ((row.pct ?? 0) > 0 ? SpendWiseColors.spend : SpendWiseColors.keep);
      final fillColor = (row.isNew || (row.pct ?? 0) > 0)
          ? SpendWiseColors.spend
          : SpendWiseColors.keep;

      final String labelText;
      if (row.isNew) {
        labelText = 'NEW';
      } else if (row.pct == 0) {
        labelText = '0%';
      } else {
        labelText =
            _formatPercent(row.pct!) + (row.isStopped ? ' · stopped' : '');
      }

      final Color labelColor;
      if (row.isClamped) {
        labelColor = color;
      } else if (row.isNew) {
        labelColor = SpendWiseColors.mine;
      } else {
        labelColor = (row.pct?.abs() ?? 0) >= 25
            ? _loudLabel
            : SpendWiseColors.dim;
      }

      final bool anchorEnd;
      final double labelX;
      if (row.isClamped) {
        final positive = (row.pct ?? 0) > 0;
        anchorEnd = positive;
        labelX = positive ? curveWidth - 4 : 4;
      } else {
        anchorEnd = x < centerX;
        final offset = row.isFlat ? 7.0 : 8.0;
        labelX = x >= centerX ? x + offset : x - offset;
      }

      traceRows.add(
        _TraceRow(
          category: row.category,
          path: path,
          areaPath: areaPath,
          hitPath: hitPath,
          markerShape: markerShape,
          chevronPath: chevronPath,
          color: color,
          fillColor: fillColor,
          labelText: labelText,
          labelColor: labelColor,
          labelX: labelX,
          anchorEnd: anchorEnd,
          yMid: yMid,
          deviation: x - centerX,
          isFlat: row.isFlat,
          isNew: row.isNew,
          isClamped: row.isClamped,
          isAggregate: row.isAggregate,
        ),
      );
    }
    return _SeismographGeometry(rows: traceRows);
  }

  static String _formatPercent(double pct) {
    final digits = pct.abs() >= 100 ? 0 : 1;
    final sign = pct > 0 ? '+' : '';
    return '$sign${pct.toStringAsFixed(digits)}%';
  }
}

/// A category the way `_prepareRows` needs it, whether it came straight off
/// [CategoryAnalytics] or was synthesised by summing a folded tail.
typedef _Entry = ({
  String category,
  int amountMinor,
  int previousAmountMinor,
  bool isNew,
  bool isStopped,
  double? pct,
  bool isAggregate,
});

/// Where a row's deviation and clamp state settle, before any pixel width is
/// known.
class _RowShape {
  const _RowShape({
    required this.devFrac,
    required this.isFlat,
    required this.isClamped,
  });

  final double devFrac;
  final bool isFlat;
  final bool isClamped;
}

/// Everything about one row that does not depend on the widget's current
/// width or on whether a selection is animating -- computed once per build
/// from the analytics alone, and fed into [_DevFracTween] to travel between
/// two datasets.
class _RowData {
  const _RowData({
    required this.category,
    required this.devFrac,
    required this.isFlat,
    required this.isClamped,
    required this.isNew,
    required this.isStopped,
    required this.isAggregate,
    required this.pct,
    required this.amountMinor,
    required this.previousAmountMinor,
  });

  final String category;
  final double devFrac;
  final bool isFlat;
  final bool isClamped;
  final bool isNew;
  final bool isStopped;
  final bool isAggregate;
  final double? pct;
  final int amountMinor;
  final int previousAmountMinor;
}

/// One row's paths and label, laid out at the widget's real width and at the
/// deviation this animation frame is currently showing.
class _TraceRow {
  const _TraceRow({
    required this.category,
    required this.path,
    required this.areaPath,
    required this.hitPath,
    required this.markerShape,
    required this.chevronPath,
    required this.color,
    required this.fillColor,
    required this.labelText,
    required this.labelColor,
    required this.labelX,
    required this.anchorEnd,
    required this.yMid,
    required this.deviation,
    required this.isFlat,
    required this.isNew,
    required this.isClamped,
    required this.isAggregate,
  });

  final String category;

  /// The open curve, for stroking -- never closed, or a stroke would draw a
  /// visible straight edge back to its own start.
  final Path path;

  /// The same curve, closed, for the light fill under it and as the base of
  /// [hitPath].
  final Path areaPath;

  /// What a tap is actually tested against: [areaPath] widened by a generous
  /// circle around the marker, so a row whose deviation sits right on the
  /// centre line -- a near-zero-area sliver -- is still comfortably tappable.
  final Path hitPath;
  final Path markerShape;
  final Path? chevronPath;
  final Color color;
  final Color fillColor;
  final String labelText;
  final Color labelColor;
  final double labelX;

  /// True when the label ends at [labelX] rather than starting there --
  /// mirrors an SVG `text-anchor` of `end`.
  final bool anchorEnd;
  final double yMid;

  /// This row's marker offset from the centre spine, in pixels -- signed,
  /// so a test can tell a fall from a rise without decoding a path. The one
  /// number that tells a calm row from a violent one.
  final double deviation;
  final bool isFlat;
  final bool isNew;
  final bool isClamped;
  final bool isAggregate;
}

Path _curvePath({
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
  return Path()
    ..moveTo(centerX, y0)
    ..cubicTo(centerX, c1y, x, c2y, x, yMid)
    ..cubicTo(x, c3y, centerX, c4y, centerX, y1);
}

/// Every path this frame painted, so a tap can be tested against the curve
/// actually on screen rather than against a fresh derivation of it -- the
/// same discipline `_FlowGeometry.branchAt` holds itself to in
/// `shape_kit.dart`.
class _SeismographGeometry {
  const _SeismographGeometry({required this.rows});

  final List<_TraceRow> rows;

  /// The row [point] landed on, if any. Tested in display order against each
  /// row's own [_TraceRow.hitPath] -- a real curved shape, not a bounding box.
  int? rowIndexAt(Offset point) {
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].hitPath.contains(point)) return i;
    }
    return null;
  }
}

/// A tone distinguishing a loud reading from an ordinary one on the printed
/// percentage labels. Not a palette colour -- this is a display-only nuance
/// scoped to this one file, not a semantic the rest of the app needs to
/// agree on the way it must agree on keep/spend/mine.
const _loudLabel = Color(0xFFA6ABAE);

/// Lerps a whole map of per-category deviations at once, walking the union
/// of both sides' keys and defaulting a key missing from either side to
/// zero -- a category that just appeared or just stopped moves from (or to)
/// the centre line like any other change, rather than popping into
/// existence at its final position.
class _DevFracTween extends Tween<Map<String, double>> {
  // `begin` is deliberately not a constructor parameter: TweenAnimationBuilder
  // sets it itself, on the instance it is handed, to wherever the animation
  // currently sits, every time `end` changes -- that is how "travel from
  // wherever I last was" works, and it needs the plain mutable field Tween
  // already declares, not a value threaded through here.
  _DevFracTween({required super.end});

  @override
  Map<String, double> lerp(double t) {
    final keys = <String>{...?begin?.keys, ...?end?.keys};
    return {
      for (final key in keys)
        key: lerpDouble(begin?[key] ?? 0, end?[key] ?? 0, t) ?? 0,
    };
  }
}

Path _dashPath(Path source, {required double dash, required double gap}) {
  final dashed = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    var draw = true;
    while (distance < metric.length) {
      final length = draw ? dash : gap;
      final next = math.min(distance + length, metric.length);
      if (draw) dashed.addPath(metric.extractPath(distance, next), Offset.zero);
      distance = next;
      draw = !draw;
    }
  }
  return dashed;
}

class _SeismographPainter extends CustomPainter {
  _SeismographPainter({
    required this.rows,
    required this.centerX,
    required this.maxDeviation,
    required this.reveal,
    required this.dim,
    required this.selected,
  });

  final List<_TraceRow> rows;
  final double centerX;

  /// The lane's own half-width under the fixed scale -- carried through only
  /// so a test can read it back beside [largestDeviation] and judge a calm
  /// month against a violent one without recomputing this build's layout math
  /// itself.
  final double maxDeviation;
  final double reveal;
  final double dim;
  final String? selected;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // The whole month draws itself in once, top to bottom -- a clip window
    // growing downward rather than a stroke-dashoffset trace, so every row's
    // own internal shape reveals in the order the page is read in, not in
    // the order its own curve happens to bow left or right.
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height * reveal));

    canvas.drawLine(
      Offset(centerX, 2),
      Offset(centerX, size.height - 2),
      Paint()
        ..color = SpendWiseColors.edge
        ..strokeWidth = 1,
    );

    for (final row in rows) {
      final isSelected = row.category == selected;
      final isDimmed = selected != null && !isSelected;
      final lineAlpha = (isDimmed ? 1.0 - 0.78 * dim : 1.0).clamp(0.0, 1.0);
      final labelAlpha = (isDimmed ? 1.0 - 0.70 * dim : 1.0).clamp(0.0, 1.0);
      final areaAlpha = (isDimmed ? 0.13 - 0.10 * dim : 0.13).clamp(0.0, 1.0);

      if (!row.isFlat) {
        canvas.drawPath(
          row.areaPath,
          Paint()
            ..style = PaintingStyle.fill
            ..color = row.fillColor.withValues(alpha: areaAlpha),
        );
      }

      final strokePath = row.isNew
          ? _dashPath(row.path, dash: 3, gap: 2)
          : row.path;
      canvas.drawPath(
        strokePath,
        Paint()
          ..style = PaintingStyle.stroke
          // Snapped, not tweened: the jump from 1.4 to 2.3 logical pixels is
          // under one physical pixel on most phones, so animating it is
          // motion nobody can actually see. Selection still reads plainly
          // through the dim applied to every other row.
          ..strokeWidth = isSelected ? 2.3 : 1.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = row.color.withValues(alpha: lineAlpha),
      );

      if (row.isFlat) {
        canvas.drawPath(
          row.markerShape,
          Paint()..color = SpendWiseColors.mine.withValues(alpha: lineAlpha),
        );
      } else if (row.isNew) {
        canvas.drawPath(
          _dashPath(row.markerShape, dash: 2, gap: 1.3),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = SpendWiseColors.mine.withValues(alpha: lineAlpha),
        );
      } else {
        canvas.drawPath(
          row.markerShape,
          Paint()..color = row.color.withValues(alpha: lineAlpha),
        );
      }

      if (row.chevronPath != null) {
        canvas.drawPath(
          row.chevronPath!,
          Paint()..color = row.color.withValues(alpha: lineAlpha),
        );
      }

      final labelPainter = TextPainter(
        text: TextSpan(
          text: row.labelText,
          style: TextStyle(
            fontFamily: SpendWiseType.mono,
            fontSize: 8.5,
            fontWeight: row.isClamped ? FontWeight.w700 : FontWeight.w400,
            color: row.labelColor.withValues(alpha: labelAlpha),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = row.anchorEnd ? row.labelX - labelPainter.width : row.labelX;
      labelPainter.paint(
        canvas,
        Offset(dx, row.yMid - labelPainter.height / 2),
      );
    }
    canvas.restore();
  }

  /// Carries the values this frame painted with, so a test can read the
  /// reveal and dim progress back the same way `motion_contract_test` reads
  /// `_FlowShapePainter`'s fields, and so a test can hold the fixed scale to
  /// account: the largest deviation actually drawn this frame, against the
  /// lane's own half-width, is what tells a calm month from a violent one.
  @override
  String toString() {
    final largest = rows.fold<double>(
      0,
      (best, row) => math.max(best, row.deviation.abs()),
    );
    return '_SeismographPainter(reveal: $reveal, dim: $dim, '
        'maxDeviation: $maxDeviation, largestDeviation: $largest)';
  }

  @override
  bool shouldRepaint(covariant _SeismographPainter old) =>
      old.rows != rows ||
      old.centerX != centerX ||
      old.maxDeviation != maxDeviation ||
      old.reveal != reveal ||
      old.dim != dim ||
      old.selected != selected;
}

class _NameCell extends StatelessWidget {
  const _NameCell({
    required this.row,
    required this.height,
    required this.selected,
    required this.tone,
    required this.reduceMotion,
    required this.currency,
    required this.onTap,
  });

  final _RowData row;
  final double height;
  final String? selected;
  final Color tone;
  final bool reduceMotion;
  final String currency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isSelected = row.category == selected;
    final isDimmed = selected != null && !isSelected;
    final loud =
        !row.isNew &&
        !row.isStopped &&
        !row.isAggregate &&
        (row.pct?.abs() ?? 0) >= 25;
    final color = isSelected || loud ? SpendWiseColors.fg : SpendWiseColors.dim;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return Semantics(
      button: onTap != null,
      selected: isSelected,
      label: _semanticsLabel(row, currency),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: height,
          child: AnimatedOpacity(
            duration: duration,
            curve: Curves.easeOutCubic,
            opacity: isDimmed ? 0.30 : 1.0,
            child: Row(
              children: [
                if (!row.isAggregate) ...[
                  Container(width: 6, height: 6, color: tone),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      fontFamily: SpendWiseType.sans,
                      fontSize: 10.5,
                      color: color,
                      fontWeight: (isSelected || loud)
                          ? FontWeight.w600
                          : FontWeight.w400,
                      decoration: row.isStopped
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      decorationColor: SpendWiseColors.edge,
                    ),
                    child: Text(
                      row.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _semanticsLabel(_RowData row, String currency) {
    final now = formatAmount(
      MoneyViewData(row.amountMinor, currency: currency),
      cents: false,
    );
    if (row.isNew) return '${row.category}, new this period, $now';
    if (row.isStopped) {
      final was = formatAmount(
        MoneyViewData(row.previousAmountMinor, currency: currency),
        cents: false,
      );
      return '${row.category}, stopped, was $was';
    }
    if (row.pct == 0) return '${row.category}, unchanged at $now';
    final pct = row.pct;
    if (pct == null) return '${row.category}, $now';
    final digits = pct.abs() >= 100 ? 0 : 1;
    final sign = pct > 0 ? '+' : '';
    return '${row.category}, $sign${pct.toStringAsFixed(digits)} percent, now $now';
  }
}
