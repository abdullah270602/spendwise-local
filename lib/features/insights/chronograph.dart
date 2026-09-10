import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../app/category_tones.dart';
import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../shell/spendwise_view_model.dart';
import 'spending_analytics.dart';

/// Where the money went, drawn as a dial that grows its ticks inward from a
/// fixed rim rather than as a donut whose arcs disagree with the eye about
/// what a share of a share looks like.
///
/// This replaces the old `_CategoryBreakdown` -- a donut beside a list that
/// stated the same six numbers twice, once through arc length (which reads
/// worse than a line's length) and once as text. The dial has to survive a
/// filter tap now instead of being removed from the tree: [categories] is
/// expected to already be computed unfiltered, so the reading never changes
/// shape underneath a reader mid-look, only its styling does.
class Chronograph extends StatefulWidget {
  const Chronograph({
    super.key,
    required this.categories,
    required this.tones,
    required this.selected,
    required this.onSelect,
    required this.currency,
  });

  /// Every category with spending in the period, largest first. Unfiltered:
  /// this list must not shrink or reorder when [selected] changes, or a tick
  /// would visibly move under a reader's finger.
  final List<CategoryAnalytics> categories;
  final CategoryTones tones;

  /// The category the screen is filtered to, or null for no filter.
  final String? selected;

  /// Called with the tapped category, or null to clear the filter. A tap on
  /// the currently selected tick or plate row clears it -- the dial's own
  /// answer to "how do I get back to everything" alongside the filter chips.
  final ValueChanged<String?> onSelect;
  final String currency;

  /// Below this many categories a dial has no spread to show: two points is
  /// just two ticks 180 degrees apart with nothing to compare them against,
  /// and one point is a single spoke stating "100%", which is true and
  /// useless. Below the floor the plate carries the whole reading alone.
  static const minForDial = 3;

  @override
  State<Chronograph> createState() => _ChronographState();
}

class _ChronographState extends State<Chronograph>
    with TickerProviderStateMixin {
  /// The one-shot entrance. Runs forward exactly once, on mount, and is never
  /// touched again -- rebuilding it on every filter tap would replay the
  /// whole entrance each time someone taps a category, which is the "two
  /// clocks fighting" trap the design brief calls out by name.
  ///
  /// Slower than the app's own 1300ms arrival on purpose: this is the one
  /// dial in the app with a needle sweeping a full circle while every tick
  /// grows in behind it, and at 1300ms that read on the device as arriving
  /// rather than gliding. 1700ms is the owner's own ceiling on this screen --
  /// past roughly two seconds a settle stops reading as unhurried and starts
  /// reading as a wait.
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );

  /// The independent, much shorter mechanism for dimming and undimming ticks
  /// when [Chronograph.selected] changes. Its duration is set right before
  /// each run rather than fixed at construction, so reduced motion can
  /// collapse it to zero without a second code path.
  late final AnimationController _selection = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  bool _reduce = false;
  bool _entryStarted = false;

  /// What was selected immediately before the change that is currently
  /// crossfading in. Null before the first change, which is exactly what an
  /// unselected dial should lerp from.
  String? _prevSelected;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Checked once, the same way FlowShape and AnimatedMinor already do --
    // MediaQuery can change later (a user can flip the OS setting while the
    // screen is open), but an entrance that already ran is not replayed
    // retroactively, only future selection crossfades honour the new value.
    _reduce = MediaQuery.disableAnimationsOf(context);
    if (!_entryStarted) {
      _entryStarted = true;
      if (_reduce) {
        _entry.value = 1;
      } else {
        _entry.forward();
      }
    }
  }

  @override
  void didUpdateWidget(covariant Chronograph old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      _prevSelected = old.selected;
      _selection
        ..duration = _reduce ? Duration.zero : const Duration(milliseconds: 220)
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    _selection.dispose();
    super.dispose();
  }

  void _toggle(String category) {
    widget.onSelect(widget.selected == category ? null : category);
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.categories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Where your money went'),
        const SizedBox(height: 12),
        if (categories.isEmpty)
          Text(
            'Categorised spending will appear here.',
            style: SpendWiseType.body.copyWith(fontSize: 13),
          )
        else if (categories.length == 1)
          _SingleCategoryFigure(
            category: categories.single,
            currency: widget.currency,
          )
        else if (categories.length < Chronograph.minForDial)
          _Plate(
            categories: categories,
            tones: widget.tones,
            selected: widget.selected,
            currency: widget.currency,
            reduce: _reduce,
            onTap: _toggle,
          )
        else ...[
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_entry, _selection]),
              builder: (context, _) => _Dial(
                categories: categories,
                tones: widget.tones,
                selected: widget.selected,
                prevSelected: _prevSelected,
                currency: widget.currency,
                entryValue: _entry.value,
                selectionValue: _selection.value,
                reduce: _reduce,
                onTap: _toggle,
              ),
            ),
          ),
          const SizedBox(height: 18),
          _Plate(
            categories: categories,
            tones: widget.tones,
            selected: widget.selected,
            currency: widget.currency,
            reduce: _reduce,
            onTap: _toggle,
          ),
        ],
      ],
    );
  }
}

/// How much of the whole entrance the stagger spreads its first-tick-to-
/// last-tick delay across, and how much of it one tick's own growth takes --
/// both as a fraction of `_ChronographState._entry`'s full length, not as
/// literal milliseconds. The two were originally 550ms and 750ms of a
/// 1300ms entrance; kept as that same ratio (550/1300, 750/1300) here so
/// slowing the entrance down stretches every tick's own glide along with it
/// instead of leaving the stagger's shape tied to a duration that moved on
/// without it.
const _staggerSpanFraction = 550 / 1300;
const _tickGrowthFraction = 750 / 1300;

/// The fixed geometry the dial and its hit-testing are both built from, so
/// painting and tapping can never quietly disagree about where a tick is.
/// Kept exactly to the numbers the design settled on: a canvas this size has
/// already been proven clip-free at the 360px stage this ships inside.
abstract final class _Geo {
  static const size = 280.0;
  static const center = Offset(140, 140);
  static const rimRadius = 118.0;
  static const outerRadius = 114.0;
  static const minLen = 7.0;
  static const maxLen = 41.0;
  static const hubRadius = 58.0;
  static const labelInset = 13.0;
}

/// 12 o'clock is index 0; the rest follow clockwise, matching the order
/// [SpendingAnalytics.categories] already sorts in and the order the plate
/// states its rows in -- a finger tracing the rim and a finger reading down
/// the plate land on the same category at the same time.
double _angleRad(int index, int count) =>
    (-90 + index * (360 / count)) * math.pi / 180;

Offset _pointAt(double angleRad, double radius) =>
    _Geo.center + Offset(math.cos(angleRad), math.sin(angleRad)) * radius;

/// Anchored at the fixed outer radius and grown inward, so nothing can ever
/// reach past the rim regardless of how large a share gets. Scaled against
/// the largest share actually being drawn, not against a fixed 100%, or one
/// dominant category would flatten every other tick to the floor.
double _tickLength(double fraction, double maxFraction) {
  if (maxFraction <= 0) return _Geo.minLen;
  final t = (fraction / maxFraction).clamp(0.0, 1.0);
  return _Geo.minLen + t * (_Geo.maxLen - _Geo.minLen);
}

/// One donut-shaped wedge per category, spanning from the hub out to the rim
/// and half the angle to each neighbour -- the tappable area, not the drawn
/// tick. A tick can be as thin as 2.5 logical pixels; nobody should have to
/// land on it exactly. Built with the same technique `shape_kit.dart` already
/// uses for the ribbon's per-branch hit-testing: a real path, tested with
/// `Path.contains`, not a bounding box.
List<Path> _wedgePaths(int count) {
  final halfWidth = math.pi / count;
  final outerRect = Rect.fromCircle(
    center: _Geo.center,
    radius: _Geo.rimRadius,
  );
  final innerRect = Rect.fromCircle(
    center: _Geo.center,
    radius: _Geo.hubRadius,
  );
  return [
    for (var i = 0; i < count; i++)
      () {
        final angle = _angleRad(i, count);
        final start = angle - halfWidth;
        final sweep = halfWidth * 2;
        return Path()
          ..arcTo(outerRect, start, sweep, true)
          ..arcTo(innerRect, start + sweep, -sweep, false)
          ..close();
      }(),
  ];
}

class _Dial extends StatelessWidget {
  const _Dial({
    required this.categories,
    required this.tones,
    required this.selected,
    required this.prevSelected,
    required this.currency,
    required this.entryValue,
    required this.selectionValue,
    required this.reduce,
    required this.onTap,
  });

  final List<CategoryAnalytics> categories;
  final CategoryTones tones;
  final String? selected;
  final String? prevSelected;
  final String currency;
  final double entryValue;
  final double selectionValue;
  final bool reduce;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final wedges = _wedgePaths(categories.length);
    return GestureDetector(
      // The same action -- selecting a category -- is reachable, with a
      // proper Semantics label, from the plate row directly below. The dial
      // is a second, visual way to reach it, not a second thing to announce.
      excludeFromSemantics: true,
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        for (var i = 0; i < categories.length; i++) {
          if (wedges[i].contains(details.localPosition)) {
            onTap(categories[i].category);
            return;
          }
        }
      },
      child: SizedBox(
        width: _Geo.size,
        height: _Geo.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size(_Geo.size, _Geo.size),
              painter: _ChronographPainter(
                categories: categories,
                tones: tones,
                selected: selected,
                prevSelected: prevSelected,
                entryValue: entryValue,
                selectionValue: selectionValue,
                reduce: reduce,
              ),
            ),
            // Nothing in the hub rotates or is positioned by angle, so it is
            // ordinary text, not a painter -- Flutter's own layout already
            // handles the ellipsis and two-line cases better than a
            // hand-rolled TextPainter would. Pointer-events pass through it,
            // exactly like the CSS source: a tap meant for the tick behind
            // the hub's transparent corners must not be swallowed here (the
            // hub itself sits entirely inside the un-tappable centre anyway).
            IgnorePointer(
              child: _Hub(
                categories: categories,
                selected: selected,
                currency: currency,
                reduce: reduce,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChronographPainter extends CustomPainter {
  _ChronographPainter({
    required this.categories,
    required this.tones,
    required this.selected,
    required this.prevSelected,
    required this.entryValue,
    required this.selectionValue,
    required this.reduce,
  });

  final List<CategoryAnalytics> categories;
  final CategoryTones tones;
  final String? selected;
  final String? prevSelected;
  final double entryValue;
  final double selectionValue;
  final bool reduce;

  static double _dimAlpha(String? selectedName, String category) =>
      selectedName == null ? 1.0 : (selectedName == category ? 1.0 : 0.22);

  static double _strokeWidth(String? selectedName, String category) =>
      selectedName == category ? 3.5 : 2.5;

  /// A label keeps the normal >=6% cutoff except for the selected tick, which
  /// states its own reading regardless -- the one thing a tap is actually
  /// asking for. A label that already cleared the cutoff dims to .3 rather
  /// than disappearing when some other category is selected instead.
  static double _labelOpacity(String? selectedName, CategoryAnalytics data) {
    if (data.category == selectedName) return 1.0;
    if (data.fraction < 0.06) return 0.0;
    return selectedName == null ? 1.0 : 0.3;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = categories.length;
    if (n == 0) return;
    final maxFraction = categories.fold<double>(
      0,
      (best, data) => math.max(best, data.fraction),
    );
    final selectionT = Curves.easeOutCubic.transform(
      selectionValue.clamp(0.0, 1.0),
    );

    // The rim, the hub ring and the centre pin are the case-back, not the
    // reading -- they are always drawn and take no part in either motion.
    canvas.drawCircle(
      _Geo.center,
      _Geo.rimRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = SpendWiseColors.edge,
    );
    canvas.drawCircle(
      _Geo.center,
      _Geo.hubRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = SpendWiseColors.line,
    );

    for (var i = 0; i < n; i++) {
      final data = categories[i];
      final angle = _angleRad(i, n);
      final len = _tickLength(data.fraction, maxFraction);
      final outer = _pointAt(angle, _Geo.outerRadius);
      final inner = _pointAt(angle, _Geo.outerRadius - len);
      final mid = Offset.lerp(outer, inner, 0.5)!;

      // The bounded stagger: tick i's delay grows with its index but the
      // whole window is capped at a fixed share of the entrance regardless of
      // how many categories there are, so twenty-five ticks finish in the
      // same sweep three do. Expressed as a fraction of the entrance rather
      // than as literal milliseconds over a hardcoded total, so retuning
      // `_entry`'s own duration can never silently throw this out of
      // proportion again.
      final start = (i / math.max(1, n - 1) * _staggerSpanFraction).clamp(
        0.0,
        1.0,
      );
      final end = (start + _tickGrowthFraction).clamp(start, 1.0);
      final tickT = reduce
          ? 1.0
          : Interval(
              start,
              end,
              curve: Curves.easeOutQuint,
            ).transform(entryValue.clamp(0.0, 1.0));

      // A tick grows in from half its length, anchored on its own midpoint --
      // the canvas equivalent of the source's `transform: scale(.5)`. Once
      // the entrance has settled this is 1 and the tick sits exactly at
      // (outer, inner), which selection never moves.
      final growth = 0.5 + 0.5 * tickT;
      final p0 = Offset.lerp(mid, outer, growth)!;
      final p1 = Offset.lerp(mid, inner, growth)!;

      final dimAlpha =
          lerpDouble(
            _dimAlpha(prevSelected, data.category),
            _dimAlpha(selected, data.category),
            selectionT,
          ) ??
          1.0;
      final opacity = (tickT * dimAlpha).clamp(0.0, 1.0);
      final strokeWidth =
          lerpDouble(
            _strokeWidth(prevSelected, data.category),
            _strokeWidth(selected, data.category),
            selectionT,
          ) ??
          2.5;

      final color = tones.of(data.category);
      canvas.drawLine(
        p0,
        p1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = strokeWidth
          ..color = color.withValues(alpha: opacity),
      );
      canvas.drawCircle(
        p1,
        2.6,
        Paint()..color = color.withValues(alpha: opacity),
      );

      final labelOpacity =
          (lerpDouble(
                _labelOpacity(prevSelected, data),
                _labelOpacity(selected, data),
                selectionT,
              ) ??
              0.0) *
          tickT;
      if (labelOpacity > 0.01) {
        final isSelectedTick = data.category == selected;
        final labelPainter = TextPainter(
          text: TextSpan(
            text: (data.fraction * 100).toStringAsFixed(1),
            style: TextStyle(
              fontFamily: SpendWiseType.mono,
              fontSize: 8,
              fontWeight: isSelectedTick ? FontWeight.w600 : FontWeight.w400,
              color: (isSelectedTick ? SpendWiseColors.fg : SpendWiseColors.dim)
                  .withValues(alpha: labelOpacity),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        // Rotated position, not rotated text -- the label always sits
        // upright at the angle its own tick points at, at that tick's own
        // inner radius, never a radius shared with every other label.
        final labelCenter = _pointAt(
          angle,
          _Geo.outerRadius - len - _Geo.labelInset,
        );
        labelPainter.paint(
          canvas,
          labelCenter - Offset(labelPainter.width / 2, labelPainter.height / 2),
        );
      }
    }

    // The pin only has to say where the hands come from. Drawn at full [dim]
    // it was the brightest thing inside the hub ring and pulled the eye to the
    // middle of a dial whose reading is all at the rim, so it is held back to
    // something nearer the hairlines it sits among.
    canvas.drawCircle(
      _Geo.center,
      2,
      Paint()..color = SpendWiseColors.dim.withValues(alpha: 0.35),
    );

    if (!reduce) {
      final raw = entryValue.clamp(0.0, 1.0);
      final eased = Curves.easeOutQuint.transform(raw);
      final needleAngle = (-90 + 360 * eased) * math.pi / 180;
      final needleOpacity = raw <= 0.82
          ? 1.0
          : (1 - (raw - 0.82) / 0.18).clamp(0.0, 1.0);
      // A needle frozen mid-arc reads as a rendering bug, not a choice, which
      // is exactly why reduced motion omits it entirely (the branch above)
      // rather than drawing it stopped at rest.
      if (needleOpacity > 0) {
        canvas.drawLine(
          _Geo.center,
          _pointAt(needleAngle, _Geo.rimRadius * 0.92),
          Paint()
            ..strokeWidth = 1
            ..color = SpendWiseColors.fg.withValues(alpha: needleOpacity),
        );
      }
    }
  }

  /// Carries the values this frame painted with, so a test can read the
  /// entrance and reduced-motion state back the same way `motion_contract_test`
  /// already reads `_FlowShapePainter`'s fields through its own `toString`.
  @override
  String toString() =>
      '_ChronographPainter(entryValue: $entryValue, '
      'selectionValue: $selectionValue, reduce: $reduce)';

  @override
  bool shouldRepaint(_ChronographPainter old) =>
      old.categories != categories ||
      old.selected != selected ||
      old.prevSelected != prevSelected ||
      old.entryValue != entryValue ||
      old.selectionValue != selectionValue ||
      old.reduce != reduce;
}

class _Hub extends StatelessWidget {
  const _Hub({
    required this.categories,
    required this.selected,
    required this.currency,
    required this.reduce,
  });

  final List<CategoryAnalytics> categories;
  final String? selected;
  final String currency;
  final bool reduce;

  @override
  Widget build(BuildContext context) {
    final duration = reduce ? Duration.zero : const Duration(milliseconds: 220);
    // The selected category may not be in this period's spread at all -- a
    // filter chip lists every category the ledger has ever seen, not only
    // the ones with spending this period, so a tap can name a category this
    // dial has nothing to show for. Stated honestly as zero rather than
    // thrown on.
    final data = selected == null
        ? null
        : categories.firstWhere(
            (item) => item.category == selected,
            orElse: () => CategoryAnalytics(
              category: selected!,
              amountMinor: 0,
              fraction: 0,
            ),
          );
    return SizedBox(
      width: 104,
      height: 104,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        child: data == null
            ? _HubDefault(
                key: const ValueKey('default'),
                count: categories.length,
              )
            : _HubSelected(
                key: ValueKey(data.category),
                data: data,
                currency: currency,
              ),
      ),
    );
  }
}

class _HubDefault extends StatelessWidget {
  const _HubDefault({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Text(
    count == 1 ? '1 CATEGORY' : '$count CATEGORIES',
    textAlign: TextAlign.center,
    style: SpendWiseType.metaTight,
  );
}

class _HubSelected extends StatelessWidget {
  const _HubSelected({super.key, required this.data, required this.currency});

  final CategoryAnalytics data;
  final String currency;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        data.category.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: SpendWiseType.metaTight,
      ),
      const SizedBox(height: 3),
      RichText(
        text: TextSpan(
          text: (data.fraction * 100).toStringAsFixed(1),
          style: SpendWiseType.amount.copyWith(fontSize: 21),
          children: [
            TextSpan(
              text: '%',
              style: SpendWiseType.metaTight.copyWith(
                fontSize: 11,
                color: SpendWiseColors.dim,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 3),
      Text(
        formatAmount(
          MoneyViewData(data.amountMinor, currency: currency),
          cents: false,
        ),
        style: SpendWiseType.metaTight,
      ),
    ],
  );
}

/// One category, stated once, plainly -- a dial needs a spread to compare and
/// one point cannot have one, so below three categories nothing is painted
/// at all.
class _SingleCategoryFigure extends StatelessWidget {
  const _SingleCategoryFigure({required this.category, required this.currency});

  final CategoryAnalytics category;
  final String currency;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        formatAmount(
          MoneyViewData(category.amountMinor, currency: currency),
          cents: false,
        ),
        style: SpendWiseType.figure.copyWith(fontSize: 30),
      ),
      const SizedBox(height: 6),
      Text(
        '${(category.fraction * 100).toStringAsFixed(1)}% · '
        '${category.category.toUpperCase()}',
        style: SpendWiseType.metaTight,
      ),
    ],
  );
}

/// The single-column reading: name, amount and percentage, tied to its tick
/// by colour rather than by an index nobody can hold in their head. Read on
/// its own it is a strict superset of both the old plate (which had no
/// amount) and the old list widget (which had no percentage).
class _Plate extends StatelessWidget {
  const _Plate({
    required this.categories,
    required this.tones,
    required this.selected,
    required this.currency,
    required this.reduce,
    required this.onTap,
  });

  final List<CategoryAnalytics> categories;
  final CategoryTones tones;
  final String? selected;
  final String currency;
  final bool reduce;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final category in categories)
        _PlateRow(
          data: category,
          color: tones.of(category.category),
          isSelected: category.category == selected,
          dimmed: selected != null && category.category != selected,
          showDivider: category != categories.last,
          currency: currency,
          duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
          onTap: () => onTap(category.category),
        ),
    ],
  );
}

class _PlateRow extends StatelessWidget {
  const _PlateRow({
    required this.data,
    required this.color,
    required this.isSelected,
    required this.dimmed,
    required this.showDivider,
    required this.currency,
    required this.duration,
    required this.onTap,
  });

  final CategoryAnalytics data;
  final Color color;
  final bool isSelected;
  final bool dimmed;
  final bool showDivider;
  final String currency;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = isSelected ? SpendWiseColors.bg : SpendWiseColors.fg;
    final amount = formatAmount(
      MoneyViewData(data.amountMinor, currency: currency),
      cents: false,
    );
    final percent = '${(data.fraction * 100).toStringAsFixed(1)}%';
    return Semantics(
      button: true,
      selected: isSelected,
      label: '${data.category}, $amount, $percent',
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: isSelected ? SpendWiseColors.fg : Colors.transparent,
            border: showDivider
                ? const Border(bottom: BorderSide(color: SpendWiseColors.line))
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: AnimatedOpacity(
              duration: duration,
              curve: Curves.easeOutCubic,
              opacity: dimmed ? 0.36 : 1.0,
              child: Row(
                children: [
                  Container(width: 9, height: 9, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      data.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SpendWiseType.row.copyWith(color: fg),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    amount,
                    style: SpendWiseType.rowStrong.copyWith(color: fg),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 40,
                    child: Text(
                      percent,
                      textAlign: TextAlign.right,
                      style: SpendWiseType.metaTight.copyWith(
                        color: isSelected
                            ? SpendWiseColors.bg
                            : SpendWiseColors.dim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
