import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/category_tones.dart';
import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../shell/spendwise_view_model.dart';
import 'spending_analytics.dart';

/// How far a category has to move, up or down, before The Gate calls it out.
///
/// This is the one half of the loudness rule a person actually tunes -- the
/// other half, the 1%-of-spend materiality floor, is fixed. Naming these in
/// words rather than percentages is deliberate: the preview above the chooser
/// is what explains what a level does, and a raw "±25%" label would be asking
/// someone to simulate the rule in their head instead of just looking at what
/// moved.
enum GateSensitivity {
  everything(
    id: 'sensitive',
    percent: 15,
    title: 'Show me everything',
    detail:
        "Flags a category once it's ±15% off last period -- more rows will "
        'draw.',
  ),
  balanced(
    id: 'standard',
    percent: 25,
    title: 'Balanced',
    detail: "Flags a category once it's ±25% off last period.",
  ),
  bigMovesOnly(
    id: 'coarse',
    percent: 40,
    title: 'Only big moves',
    detail:
        "Flags a category once it's ±40% off last period -- only the "
        'sharpest swings draw.',
  );

  const GateSensitivity({
    required this.id,
    required this.percent,
    required this.title,
    required this.detail,
  });

  /// Stable across app versions -- this is what gets written to and read
  /// from the preference store, never the enum's Dart name.
  final String id;

  final double percent;
  final String title;
  final String detail;

  /// Falls back to [balanced] exactly the way `HomeCategories.fromId` falls
  /// back to `all`: an unrecognised or missing value is not an error, it is
  /// what a fresh install and an old preference written before a level was
  /// renamed both look like.
  static GateSensitivity fromId(String? id) =>
      values.firstWhere((value) => value.id == id, orElse: () => balanced);
}

/// Row height, matching `RegisterRow`'s density -- not invented for this
/// screen.
const double gateRowHeight = 26;

/// Height of a band header or an empty-band note.
const double gateBandHeight = 22;

/// Gap between the loud band and the quiet band.
const double gateBandGap = 8;

const double gateNameWidth = 108;
const double gateTrackWidth = 150;

/// Pixels a row's mark can travel off-centre before the scale clamps to it.
const double gateMaxDeviation = 68;

const double gateTickWidth = 3;
const double gateMinBarWidth = 2;

/// Past this many rows, "held steady" collapses behind a "+N more" line. A
/// guessed number, not a derived one -- see the design brief -- but a much
/// lower-stakes guess than the threshold itself: it only changes how far
/// someone scrolls, never what counts as loud.
const int gateQuietVisibleCount = 8;

/// The materiality floor, as a fraction of the period's total spending. Not a
/// preference: the corridor decides what is unusual, this floor decides what
/// is trivial, and a setting can only tune the first one.
const double gateMateriality = 0.01;

/// How long a row takes to glide to a new slot, or a bar to redraw. The same
/// duration `AnimatedMinor` and `FlowShape`'s morph use, so a row crossing the
/// corridor and a figure changing beside it never look like two different
/// systems disagreeing about how time passes.
const Duration gateChangeDuration = Duration(milliseconds: 800);

/// How long the highlight a row gets on crossing the corridor takes to decay
/// -- FlowShape's own tap-wobble duration, reused rather than invented.
const Duration gateFlashDuration = Duration(milliseconds: 760);

/// The centre of a 150px track.
const double _gateMid = gateTrackWidth / 2;

/// Signed square root: the same compression the rest of the Centre Line
/// family uses so a handful of huge moves cannot flatten every ordinary one
/// against the middle of the track.
double _ss(double value) => value.sign * math.sqrt(value.abs());

/// What a category's mark is placed by. A brand-new category has no real
/// percentage -- [CategoryAnalytics.changePercent] is null exactly when
/// [CategoryAnalytics.isNew] is true -- so it is handed a synthetic value far
/// past anything a real percentage reaches, purely to push its mark to the
/// far edge of the track. This number is never printed; [_gateLabel] never
/// reads it.
double _gateScaleValue(CategoryAnalytics category) =>
    category.changePercent ?? 300;

/// A category is loud only once both halves of the rule agree: the money
/// that moved has to clear the materiality floor, and -- for a category with
/// an honest percentage at all -- that percentage has to clear the chosen
/// corridor. A category with no honest percentage (new, having cleared the
/// floor) is always loud: there is no percentage to hold it to a corridor.
bool _gateIsLoud(
  CategoryAnalytics category,
  double thresholdPercent,
  double floor,
) {
  if (category.changeMinor.abs() < floor) return false;
  final percent = category.changePercent;
  if (percent == null) return true;
  return percent.abs() > thresholdPercent;
}

/// What a row prints where its percentage would go. New and stopped
/// categories get named instead of quoting a percentage that would either be
/// undefined or, for a stopped category, technically -100% but meaningless as
/// a "move" -- the category did not shrink, it ended.
String _gateLabel(CategoryAnalytics category) {
  if (category.isNew) return 'New';
  if (category.isStopped) return 'Stopped';
  final percent = category.changePercent!;
  final sign = percent > 0 ? '+' : '';
  final decimals = percent == 0 || percent.abs() >= 100 ? 0 : 1;
  return '$sign${percent.toStringAsFixed(decimals)}%';
}

/// The corridor rule, drawn.
///
/// Every category that moved between two periods, split into what crossed
/// the threshold and what did not -- ranked by the money involved, not by
/// percentage, because a percentage-first ranking is the exact failure this
/// widget exists to prevent: it would put a Rs 350 category's dramatic swing
/// above a Rs 41,000 category's real one.
///
/// A [StatefulWidget] because the crossing itself has to be remembered, not
/// recomputed: without state of its own, every rebuild this screen already
/// does for unrelated reasons (a new transaction, a filter change) would look
/// exactly like every category just crossed the corridor at once.
class Gate extends StatelessWidget {
  const Gate({
    super.key,
    required this.changes,
    required this.tones,
    required this.sensitivity,
    required this.totalSpendingMinor,
    required this.selected,
    required this.onSelect,
    required this.currency,
  });

  /// The same categories seen against the period before, largest movement of
  /// money first -- `analytics.categoryChanges`. This board trusts that
  /// ordering for the loud band rather than re-deriving it: re-sorting here
  /// too would be two places that have to agree about what "largest" means.
  final List<CategoryAnalytics> changes;

  final CategoryTones tones;
  final GateSensitivity sensitivity;

  /// The period's total spending, in minor units -- what the fixed 1%
  /// materiality floor is a fraction of.
  final int totalSpendingMinor;

  /// The category the rest of the screen is filtered to, or null for
  /// everything. The Gate does not own a selection of its own -- Insights
  /// already has a category filter, and tapping a row here sets that same
  /// field rather than inventing a second one.
  final String? selected;
  final ValueChanged<String?> onSelect;

  final String currency;

  @override
  Widget build(BuildContext context) => _GateBoard(
    changes: changes,
    tones: tones,
    sensitivity: sensitivity,
    totalSpendingMinor: totalSpendingMinor,
    selected: selected,
    onSelect: onSelect,
    currency: currency,
  );
}

/// The stateful board underneath [Gate]. Split out only so the public widget
/// stays a plain, documented contract while the truncation state -- "held
/// steady" expanded or not -- lives somewhere.
class _GateBoard extends StatefulWidget {
  const _GateBoard({
    required this.changes,
    required this.tones,
    required this.sensitivity,
    required this.totalSpendingMinor,
    required this.selected,
    required this.onSelect,
    required this.currency,
  });

  final List<CategoryAnalytics> changes;
  final CategoryTones tones;
  final GateSensitivity sensitivity;
  final int totalSpendingMinor;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final String currency;

  @override
  State<_GateBoard> createState() => _GateBoardState();
}

class _GateBoardState extends State<_GateBoard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final duration = reduce ? Duration.zero : gateChangeDuration;

    if (widget.changes.isEmpty) {
      return Text(
        'Nothing to compare yet.',
        style: SpendWiseType.body.copyWith(
          fontSize: 12,
          color: SpendWiseColors.dim,
        ),
      );
    }

    final floor = widget.totalSpendingMinor * gateMateriality;
    final thresholdPercent = widget.sensitivity.percent;

    final loud = <CategoryAnalytics>[];
    final quietAll = <CategoryAnalytics>[];
    for (final category in widget.changes) {
      (_gateIsLoud(category, thresholdPercent, floor) ? loud : quietAll).add(
        category,
      );
    }
    // "What moved" keeps the money-first order it arrived in. "Held steady"
    // answers a different question -- which quiet category is biggest, not
    // which one moved least -- so it earns its own sort, current spend
    // descending, the same ranking it had before The Gate existed.
    quietAll.sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    final quiet = _expanded
        ? quietAll
        : quietAll.take(gateQuietVisibleCount).toList();
    final hidden = quietAll.length - quiet.length;

    // The scale is fixed across both bands and every row on screen -- Stage D
    // in the design brief calls this out explicitly -- so the corridor walls
    // stay at a meaningful position instead of being redrawn per row.
    final scaleMax = widget.changes.fold<double>(
      1,
      (best, category) => math.max(best, _ss(_gateScaleValue(category)).abs()),
    );
    final k = gateMaxDeviation / scaleMax;
    final wall = _ss(thresholdPercent) * k;

    var top = 0.0;
    final children = <Widget>[];

    void addFixed(String key, double height, Widget child) {
      children.add(
        AnimatedPositioned(
          key: ValueKey(key),
          duration: duration,
          curve: Curves.easeOutQuint,
          left: 0,
          right: 0,
          top: top,
          height: height,
          child: child,
        ),
      );
      top += height;
    }

    void addRow(CategoryAnalytics category, bool isLoud) {
      children.add(
        AnimatedPositioned(
          // Keyed by category, not by index or band -- this is the one
          // decision that makes a category crossing bands glide rather than
          // snap. A `Stack` reconciles its children by key, so the same
          // element (and the same row-level `AnimationController`, if one is
          // running) survives the move and only its position tweens.
          key: ValueKey(category.category),
          duration: duration,
          curve: Curves.easeOutQuint,
          left: 0,
          right: 0,
          top: top,
          height: gateRowHeight,
          child: _GateRow(
            data: category,
            loud: isLoud,
            k: k,
            wall: wall,
            tone: widget.tones.of(category.category),
            selected: widget.selected == category.category,
            dimmed:
                widget.selected != null && widget.selected != category.category,
            duration: duration,
            reduce: reduce,
            currency: widget.currency,
            onTap: () => widget.onSelect(
              widget.selected == category.category ? null : category.category,
            ),
          ),
        ),
      );
      top += gateRowHeight;
    }

    addFixed(
      '__loud_head__',
      gateBandHeight,
      loud.isEmpty
          ? const _GateEmptyNote(
              text: 'Nothing moved more than usual this period.',
            )
          : const _GateBandHeader(label: 'What moved'),
    );
    for (final category in loud) {
      addRow(category, true);
    }
    top += gateBandGap;
    addFixed(
      '__quiet_head__',
      gateBandHeight,
      quietAll.isEmpty
          ? const _GateEmptyNote(
              text: 'Nothing held steady — every category moved this period.',
            )
          : const _GateBandHeader(label: 'Held steady'),
    );
    for (final category in quiet) {
      addRow(category, false);
    }
    if (hidden > 0) {
      addFixed(
        '__more__',
        gateRowHeight,
        _GateMoreLine(
          count: hidden,
          onTap: () => setState(() => _expanded = true),
        ),
      );
    }

    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutQuint,
      width: double.infinity,
      height: top,
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }
}

/// A titled rule: a small uppercase label with a hairline trailing off to the
/// right, matching the app's one kind of section header.
class _GateBandHeader extends StatelessWidget {
  const _GateBandHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          label.toUpperCase(),
          style: SpendWiseType.eyebrow.copyWith(fontSize: 10),
        ),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Container(height: 1, color: SpendWiseColors.line),
        ),
      ),
    ],
  );
}

/// What a band says instead of a header when it has nothing to head. Both
/// extremes -- everything held steady, or nothing did -- have to read as an
/// answer this widget is giving, not as a section that failed to load.
class _GateEmptyNote extends StatelessWidget {
  const _GateEmptyNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomLeft,
    child: Text(
      text,
      style: SpendWiseType.body.copyWith(
        fontSize: 11,
        color: SpendWiseColors.dim,
      ),
    ),
  );
}

/// The truncation line. Tapping it is the only interaction The Gate has that
/// is not a selection -- it asks to see the rest of a band that never stopped
/// existing, just stopped being drawn.
class _GateMoreLine extends StatelessWidget {
  const _GateMoreLine({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: InkWell(
      onTap: onTap,
      child: Text(
        '+$count more held steady',
        style: TextStyle(
          fontFamily: SpendWiseType.sans,
          fontSize: 10,
          letterSpacing: .4,
          fontWeight: FontWeight.w600,
          color: SpendWiseColors.keep,
        ),
      ),
    ),
  );
}

/// One category: its name, its mark on the corridor track, and what it says
/// where a percentage would go.
///
/// Owns exactly one piece of state that is not implicit -- the flash that
/// marks the moment this row's own `loud` classification changed, which
/// [Gate]'s board keys past correctly but has no reason to know about a
/// single row's most recent classification. Its position is not this
/// widget's concern at all: the parent's `AnimatedPositioned` handles that,
/// which is what lets a row glide to a new slot with no controller of its
/// own.
class _GateRow extends StatefulWidget {
  const _GateRow({
    required this.data,
    required this.loud,
    required this.k,
    required this.wall,
    required this.tone,
    required this.selected,
    required this.dimmed,
    required this.duration,
    required this.reduce,
    required this.currency,
    required this.onTap,
  });

  final CategoryAnalytics data;
  final bool loud;
  final double k;
  final double wall;
  final Color tone;
  final bool selected;
  final bool dimmed;
  final Duration duration;
  final bool reduce;
  final String currency;
  final VoidCallback onTap;

  @override
  State<_GateRow> createState() => _GateRowState();
}

class _GateRowState extends State<_GateRow> with TickerProviderStateMixin {
  // Two independent controllers can be alive at once here -- the one-shot
  // entrance and the crossing flash -- so this needs a provider that can mint
  // more than one ticker. `SingleTickerProviderStateMixin` throws the moment
  // a second is requested while the first is still alive, which the entrance
  // controller always is for a row's entire lifetime.
  /// The crossing flash. Idle at 1 (fully decayed, so the highlight it drives
  /// paints at zero alpha) and reset to 0 to bloom again the moment this
  /// row's own `loud` classification changes.
  ///
  /// Used to be minted fresh on every crossing and dropped once it finished,
  /// on the reasoning that a completed controller left alive was a ticker
  /// running for no visible effect -- true, but it is not what a finished
  /// `AnimationController` does: it stops ticking on its own once its status
  /// is `completed`, exactly like `_enter` below already sits idle for the
  /// rest of a row's life. The dropping was the actual fault. Wrapping
  /// `content` in the highlight only while a flash controller existed meant
  /// the wrapper's own widget subtree changed shape the instant a crossing
  /// began -- from a bare `Semantics` tree to an `AnimatedBuilder` wrapping
  /// that same tree -- and Flutter answers a changed subtree by discarding
  /// the old one and mounting a fresh one. Everything living inside that
  /// subtree lost whatever it was mid-flight through on exactly that frame:
  /// the corridor walls reset to their new positions outright, and so did
  /// this row's own mark, which is the one thing a crossing is actually
  /// supposed to show travelling. The row's *position* across bands still
  /// glided -- that animation lives one level up, in `_GateBoardState`,
  /// untouched by this -- which is what let the fault hide behind a passing
  /// "the row glides" reading for as long as it did.
  late final AnimationController _crossFlash = AnimationController(
    vsync: this,
    duration: gateFlashDuration, // FlowShape's own wobble duration
    value: 1,
  );

  /// A one-shot entrance: a row that has just appeared -- a category with no
  /// spending last time it was drawn -- fades in rather than popping onto the
  /// track fully formed. Reduced motion snaps it straight to visible instead
  /// of animating a fade nobody asked to see.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: gateChangeDuration,
  )..value = widget.reduce ? 1 : 0;

  @override
  void initState() {
    super.initState();
    if (!widget.reduce) _enter.forward();
  }

  @override
  void didUpdateWidget(_GateRow old) {
    super.didUpdateWidget(old);
    if (old.loud != widget.loud && !widget.reduce) {
      _crossFlash.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _crossFlash.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.data;
    final scaleValue = _gateScaleValue(category);
    final x = _gateMid + _ss(scaleValue) * widget.k;

    final Widget mark;
    final Color markColor;
    if (widget.loud) {
      final reach = (_ss(scaleValue) * widget.k).abs();
      final width = math.max(gateMinBarWidth, reach - widget.wall);
      final left = scaleValue >= 0
          ? _gateMid + widget.wall
          : _gateMid - widget.wall - width;
      // A category's own real percentage decides the mark's colour, even
      // where its position is decided by the synthetic stand-in above -- a
      // brand-new category is drawn as spending that appeared, which is an
      // increase by any honest reading.
      final realPercent = category.changePercent ?? 1;
      markColor = realPercent > 0
          ? SpendWiseColors.spend
          : (realPercent < 0 ? SpendWiseColors.keep : SpendWiseColors.dim);
      mark = AnimatedPositioned(
        // Keyed by category, not left implicit -- the tick this replaces
        // when a row first crosses into "what moved" carries the same key,
        // so a test (and Flutter's own reconciliation) can hold this one
        // element to account across that exact frame rather than treating it
        // as a fresh mark with nothing to travel from.
        key: ValueKey('${category.category}-mark'),
        duration: widget.duration,
        curve: Curves.easeOutQuint,
        left: left,
        top: 10,
        width: width,
        height: 6,
        child: AnimatedContainer(
          duration: widget.duration,
          curve: Curves.easeOutQuint,
          color: markColor,
        ),
      );
    } else {
      markColor = SpendWiseColors.dim;
      mark = AnimatedPositioned(
        key: ValueKey('${category.category}-mark'),
        duration: widget.duration,
        curve: Curves.easeOutQuint,
        left: x - gateTickWidth / 2,
        top: 10,
        width: gateTickWidth,
        height: 6,
        child: ColoredBox(color: markColor.withValues(alpha: .55)),
      );
    }

    // The label's colour follows the real percentage, not the synthetic
    // stand-in -- a new category has no honest percentage to colour by, so
    // its "New" tag stays neutral even though its mark sits at the loud
    // edge of the track.
    final realPercent = category.changePercent;
    final labelColor = !widget.loud
        ? SpendWiseColors.dim
        : (realPercent == null
              ? SpendWiseColors.dim
              : (realPercent > 0
                    ? SpendWiseColors.spend
                    : (realPercent < 0
                          ? SpendWiseColors.keep
                          : SpendWiseColors.dim)));

    final nameColor = widget.selected
        ? SpendWiseColors.fg
        : (widget.loud ? SpendWiseColors.fg : SpendWiseColors.dim);
    final nameWeight = widget.selected ? FontWeight.w700 : FontWeight.w400;

    final amount = formatAmount(
      MoneyViewData(category.amountMinor, currency: widget.currency),
      cents: false,
    );
    final changeDescription = category.isNew
        ? 'new this period'
        : category.isStopped
        ? 'stopped this period'
        : '${_gateLabel(category)} versus last period';

    Widget content = Semantics(
      button: true,
      selected: widget.selected,
      // A `Stack`'s paint order is not a screen reader's traversal order, and
      // mid-glide two rows can be visually passing through each other. The
      // parent hands every row a `_GateBoard`-assigned position in its own
      // logical list (loud rows in money order, then quiet rows in spend
      // order) through this same tree order, so the order a screen reader
      // walks in only ever reflects that logical order, never a mid-animation
      // pixel position.
      label:
          '${category.category}, $changeDescription, now $amount'
          '${widget.selected ? ', selected' : ''}',
      child: InkWell(
        onTap: widget.onTap,
        child: SizedBox(
          height: gateRowHeight,
          child: Row(
            children: [
              SizedBox(
                width: gateNameWidth,
                child: Row(
                  children: [
                    Container(width: 8, height: 8, color: widget.tone),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        category.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: SpendWiseType.sans,
                          fontSize: 11,
                          color: nameColor,
                          fontWeight: nameWeight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: gateTrackWidth,
                height: gateRowHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: _gateMid,
                      top: 9,
                      bottom: 9,
                      width: 1,
                      child: ColoredBox(color: SpendWiseColors.line),
                    ),
                    // The corridor itself, not just the row inside it -- a
                    // sensitivity change moves these two walls, and a wall
                    // that jumps while the row and its own mark glide is the
                    // one part of "the corridor just widened" a reader would
                    // see happen without being shown it happening.
                    AnimatedPositioned(
                      key: ValueKey('${category.category}-wall-lo'),
                      duration: widget.duration,
                      curve: Curves.easeOutQuint,
                      left: _gateMid - widget.wall,
                      top: 3,
                      bottom: 3,
                      width: 1,
                      child: ColoredBox(color: SpendWiseColors.edge),
                    ),
                    AnimatedPositioned(
                      key: ValueKey('${category.category}-wall-hi'),
                      duration: widget.duration,
                      curve: Curves.easeOutQuint,
                      left: _gateMid + widget.wall,
                      top: 3,
                      bottom: 3,
                      width: 1,
                      child: ColoredBox(color: SpendWiseColors.edge),
                    ),
                    mark,
                  ],
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _gateLabel(category),
                    style: TextStyle(
                      fontFamily: SpendWiseType.mono,
                      fontSize: widget.loud ? 10.5 : 9.5,
                      color: labelColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Always wrapped, at zero alpha when idle -- see `_crossFlash`'s own
    // comment for why this cannot be conditional on a flash actually being in
    // progress. The flash a row gets the moment it crosses the corridor is a
    // soft highlight that blooms and decays, on FlowShape's own wobble
    // duration rather than a number invented for this one purpose.
    content = AnimatedBuilder(
      animation: _crossFlash,
      builder: (context, child) => ColoredBox(
        color: SpendWiseColors.fg.withValues(
          alpha: .10 * (1 - _crossFlash.value),
        ),
        child: child,
      ),
      child: content,
    );

    return FadeTransition(
      opacity: _enter,
      child: AnimatedOpacity(
        opacity: widget.dimmed ? .32 : 1,
        duration: widget.duration,
        curve: Curves.easeOutQuint,
        child: content,
      ),
    );
  }
}
