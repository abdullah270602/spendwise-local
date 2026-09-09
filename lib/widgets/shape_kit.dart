import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../features/shell/spendwise_view_model.dart';

/// Amount without the currency code. Every dense surface in the redesign shows
/// bare figures -- the currency is stated once per screen, not once per row,
/// which is what let the register get twice as tight.
String formatAmount(
  MoneyViewData money, {
  bool signed = false,
  bool cents = true,
}) {
  final value = money.majorUnits.abs();
  final fixed = value.toStringAsFixed(2);
  final pieces = fixed.split('.');
  final grouped = pieces.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final decimals = !cents || pieces.last == '00' ? '' : '.${pieces.last}';
  final sign = signed ? (money.minorUnits < 0 ? '−' : '+') : '';
  return '$sign$grouped$decimals';
}

String formatMinor(int minorUnits, {bool signed = false, bool cents = true}) =>
    formatAmount(MoneyViewData(minorUnits), signed: signed, cents: cents);

/// Uppercase tracked label. The only kind of section header in the app.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color, this.trailing});

  final String text;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text.toUpperCase(),
      style: SpendWiseType.eyebrow.copyWith(color: color),
    );
    if (trailing == null) return label;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: label),
        trailing!,
      ],
    );
  }
}

/// The `Chart / Plain` and `Map / Plain` control. Two or three flat segments in
/// a single hairline box; the active one inverts. No radius, no shadow.
class ViewToggle extends StatelessWidget {
  const ViewToggle({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<String> options;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    // AnimatedContainer does not consult the platform's reduced-motion flag
    // by itself -- honouring it is opt-in, per widget -- so the fill sliding
    // from one segment to the other kept sliding for someone who had asked
    // the whole system to stop moving. Every other implicit animation in the
    // app already gates its duration on this; these two segments were the
    // only ones that opted out by saying nothing.
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 120);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: SpendWiseColors.edge),
      ),
      // Wraps rather than overflows. Three segments named honestly at twice
      // the default text size are wider than a 360dp phone on their own, and
      // a Row's answer to that is the yellow-and-black stripe. The screen
      // that hit it first could only shrink the whole control from outside,
      // which fixed the overflow by taking the tap targets back below the
      // minimum -- the fault has to be fixed here, where the layout is.
      child: Wrap(
        children: [
          for (var i = 0; i < options.length; i++)
            Semantics(
              selected: i == selected,
              button: true,
              child: InkWell(
                onTap: i == selected ? null : () => onSelected(i),
                child: AnimatedContainer(
                  duration: duration,
                  // Deliberately compact, and deliberately under the 48dp
                  // Android tap-target guideline.
                  //
                  // Raising it to 48 was tried and reverted: it is a control
                  // in a header beside a screen title, and at 48 it reads as
                  // a slab rather than a switch. The owner made that call
                  // knowing the guideline. Do not raise it again without
                  // asking -- and if it is raised, the segments must be
                  // centred with an Align, never with the Container's own
                  // `alignment`, which makes a Container with no explicit
                  // width expand to every pixel it is offered: that turned
                  // three segments into three stacked full-width rows.
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  color: i == selected
                      ? SpendWiseColors.fg
                      : Colors.transparent,
                  child: Align(
                    alignment: Alignment.center,
                    widthFactor: 1,
                    heightFactor: 1,
                    child: Text(
                      options[i].toUpperCase(),
                      style: TextStyle(
                        fontFamily: SpendWiseType.sans,
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: i == selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: i == selected
                            ? SpendWiseColors.bg
                            : SpendWiseColors.dim,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The Home screen in one object: a bar of everything that came in, splitting
/// into the share still yours and the share that left. True proportion -- the
/// thin clay thread is thin because 11% is thin.
/// Where the saved slice is drawn, when there is one.
enum SavedTreatment {
  /// Not drawn at all.
  none,

  /// Its own branch, beside kept and spent.
  branch,

  /// A division marked inside the kept footing, which keeps "still yours"
  /// meaning what it already means.
  inset,

  /// The same division, shaded along the inner edge of the kept ribbon.
  seam,
}

/// An amount that travels to its new value instead of jumping to it.
///
/// The figure and the shape are the same statement, so they have to move
/// together -- a ribbon that redraws beside a number that snaps reads as two
/// unrelated things happening at once. First build sets the value outright;
/// only a change animates.
class AnimatedMinor extends StatelessWidget {
  const AnimatedMinor(
    this.minorUnits, {
    super.key,
    this.style,
    this.cents = true,
    // Deliberately the same duration and curve as FlowShape's morph -- this
    // is the only place it is used unconditionally (MonthLegend), and that
    // is exactly the figure the ribbon travels beside. Change one, change
    // both, or the shape and the number arrive at different times.
    this.duration = const Duration(milliseconds: 800),
  });

  final int minorUnits;
  final TextStyle? style;
  final bool cents;
  final Duration duration;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<int>(
    tween: IntTween(end: minorUnits),
    // A raw TweenAnimationBuilder gets none of the help Flutter gives the
    // Animated* widgets, so reduced motion has to be honoured by hand or it
    // is not honoured at all.
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : duration,
    curve: Curves.easeOutQuint,
    builder: (context, value, _) =>
        Text(formatMinor(value, cents: cents), style: style),
  );
}

class FlowShape extends StatefulWidget {
  const FlowShape({
    super.key,
    required this.receivedMinor,
    required this.keptMinor,
    required this.spentMinor,
    this.savedMinor = 0,
    this.saved = SavedTreatment.none,
    this.height = 168,
    this.animate = true,
    this.duration = const Duration(milliseconds: 1300),
    this.wobble = false,
  });

  final int receivedMinor;
  final int keptMinor;
  final int spentMinor;

  /// Money moved into savings over the same period. Never more than what was
  /// kept: it came out of that, not out of thin air.
  final int savedMinor;
  final SavedTreatment saved;
  final double height;
  final bool animate;

  /// How long the ribbon takes to draw itself in. Shorter where the drawing
  /// is a response to a tap rather than an arrival: a settings preview that
  /// takes the better part of a second and a half to answer feels broken,
  /// not considered -- Home gets the long, settled pour (see the default
  /// above); the settings previews pass something quicker of their own.
  final Duration duration;

  /// Whether a tap disturbs the ribbon with a small, damped settle -- liquid
  /// nudged, not a button pressed. Off by default: the settings previews
  /// already replay their own draw-in on every choice, and a wobble on top of
  /// that would be a second reason to touch a figure someone is trying to
  /// read carefully, which is exactly the gimmick to avoid there. Home turns
  /// it on.
  final bool wobble;

  /// How long the ribbon takes to travel between two sets of proportions.
  /// Deliberately the same as [AnimatedMinor]'s, so the shape and the figures
  /// beside it read as one movement rather than two that happen to coincide.
  static const _morphDuration = Duration(milliseconds: 800);

  /// How long a tap's wobble takes to settle back to rest. Long enough to
  /// read as a considered, physical settle rather than a flinch, short
  /// enough that a second tap never has to wait it out.
  static const _wobbleDuration = Duration(milliseconds: 760);

  @override
  State<FlowShape> createState() => _FlowShapeState();
}

class _FlowShapeState extends State<FlowShape>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wobbleController = AnimationController(
    duration: FlowShape._wobbleDuration,
    vsync: this,
  );

  /// Which branch the most recent tap landed on -- null before any tap, and
  /// null again whenever one misses every branch. The wobble ticker below
  /// reads this, so only this one branch's paths are ever displaced.
  _FlowBranch? _wobbleBranch;

  // The geometry a tap needs to test itself against is the geometry that was
  // actually last painted, not a fresh derivation from the raw money fields
  // -- so each build caches the values the deepest builder below hands to
  // the painter, and a later tap rebuilds the identical paths from them.
  double _lastKeptFraction = 0;
  double _lastSavedOfKept = 0;
  SavedTreatment _lastSaved = SavedTreatment.none;
  double _lastReveal = 1;

  @override
  void dispose() {
    _wobbleController.dispose();
    super.dispose();
  }

  void _onTapUp(TapUpDetails details) {
    // A tap that lands while reduced motion is on gets no reply -- the whole
    // point of that setting is that nothing moves without being asked to
    // settle again, and a wobble is exactly that.
    if (MediaQuery.disableAnimationsOf(context)) return;
    final size = context.size;
    if (size == null) return;
    final geometry = _buildFlowGeometry(
      size: size,
      keptFraction: _lastKeptFraction,
      savedOfKept: _lastSavedOfKept,
      saved: _lastSaved,
      reveal: _lastReveal,
    );
    final branch = geometry.branchAt(details.localPosition);
    // A tap that lands between the branches, or out in the margin beside
    // them, is not a poke at anything -- it gets no reply, rather than
    // nudging whichever branch happened to be nearest.
    if (branch == null) return;
    setState(() => _wobbleBranch = branch);
    _wobbleController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final total = math.max(1, widget.keptMinor.abs() + widget.spentMinor.abs());
    final keptFraction = (widget.keptMinor.abs() / total).clamp(0.0, 1.0);
    // Saving is a slice of what was kept, so it is measured against that and
    // can never exceed it -- a shape where the part is bigger than the whole
    // is worse than one that omits the part.
    final savedOfKept = widget.keptMinor.abs() == 0
        ? 0.0
        : (widget.savedMinor.clamp(0, widget.keptMinor.abs()) /
                  widget.keptMinor.abs())
              .clamp(0.0, 1.0);
    final treatment = widget.savedMinor <= 0
        ? SavedTreatment.none
        : widget.saved;
    final reduce = MediaQuery.disableAnimationsOf(context);
    // Two motions, not one. `reveal` draws the ribbon in once and then stays
    // at 1 forever. The proportions were passed to the painter raw, so when
    // the real figures changed the shape jumped to its new split while the
    // legend beneath it was still counting -- the two halves of one sentence
    // disagreeing for half a second. They now travel together, on the same
    // duration and curve the figures use.
    final morph = reduce ? Duration.zero : FlowShape._morphDuration;
    final shape = TweenAnimationBuilder<double>(
      tween: Tween(end: keptFraction),
      duration: morph,
      curve: Curves.easeOutQuint,
      builder: (context, kept, _) => TweenAnimationBuilder<double>(
        tween: Tween(end: savedOfKept),
        duration: morph,
        curve: Curves.easeOutQuint,
        builder: (context, savedShare, _) => TweenAnimationBuilder<double>(
          tween: Tween(begin: widget.animate && !reduce ? 0 : 1, end: 1),
          duration: reduce ? Duration.zero : widget.duration,
          // Liquid filling a shape does not bounce past full -- the pour
          // gets a long, soft-tailed curve with no overshoot, never a
          // springy one.
          curve: Curves.easeOutQuint,
          builder: (context, t, _) {
            // Cached so `_onTapUp`, which runs outside of build, can rebuild
            // exactly this frame's geometry later.
            _lastKeptFraction = kept;
            _lastSavedOfKept = savedShare;
            _lastSaved = treatment;
            _lastReveal = t;

            Widget paintAt(double wobbleOffset) => CustomPaint(
              size: Size.infinite,
              painter: _FlowShapePainter(
                keptFraction: kept,
                savedOfKept: savedShare,
                saved: treatment,
                reveal: t,
                wobbleBranch: _wobbleBranch,
                wobbleOffset: wobbleOffset,
              ),
              child: SizedBox(height: widget.height, width: double.infinity),
            );

            if (!widget.wobble) return paintAt(0);

            return AnimatedBuilder(
              animation: _wobbleController,
              builder: (context, _) {
                final wt = _wobbleController.value;
                // A decaying sine: it starts at rest, is nudged, and rings
                // itself out within the one pass -- liquid settling, not a
                // spring bounce. Three-ish cycles land back on (near) zero
                // exactly at t = 1, so there is no visible snap when the
                // controller stops ticking.
                final settle = math.exp(-3.5 * wt) * math.sin(wt * math.pi * 6);
                // 2 logical pixels at the peak -- enough to read as
                // disturbed, never enough to blur a figure or misplace a
                // tap target. Applied to one branch's paths only, inside the
                // painter -- the trunk above it never moves.
                return paintAt(settle * 2.0);
              },
            );
          },
        ),
      ),
    );

    if (!widget.wobble) return shape;

    return GestureDetector(
      // The wobble is a reply to a poke, not a control -- it does nothing a
      // screen reader user needs announced, so it stays out of the semantics
      // tree rather than making the ribbon read as a button.
      excludeFromSemantics: true,
      behavior: HitTestBehavior.opaque,
      onTapUp: _onTapUp,
      child: shape,
    );
  }
}

/// Which of the ribbon's branches a tap landed on, and which one a wobble is
/// currently allowed to move. The top bar is deliberately not one of these --
/// it is the trunk they hang from, and never moves.
enum _FlowBranch { kept, spend, saved }

/// One filled shape and the colour it is painted in. A branch is one or more
/// of these -- a curved body, sometimes a flat footing beneath it -- that
/// always move together.
class _FlowPiece {
  const _FlowPiece(this.path, this.color);
  final Path path;
  final Color color;
}

/// Every path the ribbon is made of, grouped by which branch it belongs to.
/// Built once from the same numbers the painter would otherwise recompute
/// inline, so painting and hit-testing can never quietly disagree about
/// where a branch actually is.
class _FlowGeometry {
  const _FlowGeometry({
    required this.trunk,
    required this.kept,
    required this.spend,
    required this.saved,
  });

  final _FlowPiece trunk;
  final List<_FlowPiece> kept;
  final List<_FlowPiece> spend;
  final List<_FlowPiece> saved;

  /// Which branch, if any, contains [point]. Checked against the real curved
  /// paths -- not their bounding boxes -- so a tap near the waist of a curve
  /// lands on the branch it actually touches. Saved is checked first because,
  /// where it is drawn at all, it sits visually on top of (or carved out of)
  /// kept.
  _FlowBranch? branchAt(Offset point) {
    if (saved.any((piece) => piece.path.contains(point))) {
      return _FlowBranch.saved;
    }
    if (kept.any((piece) => piece.path.contains(point))) {
      return _FlowBranch.kept;
    }
    if (spend.any((piece) => piece.path.contains(point))) {
      return _FlowBranch.spend;
    }
    return null;
  }
}

/// Builds every path and colour the ribbon is made of, at the given size and
/// proportions. Used both to paint the ribbon and, given the same values, to
/// test a tap against the shapes actually on screen.
_FlowGeometry _buildFlowGeometry({
  required Size size,
  required double keptFraction,
  required double savedOfKept,
  required SavedTreatment saved,
  required double reveal,
}) {
  final w = size.width;
  final h = size.height;
  // Named rather than inlined because the Home-screen widget draws this same
  // static shape (reveal at 1, no wobble, no saved branch) again in Kotlin --
  // the ledger cannot be reached from a widget's process, so there is no way
  // to hand it a live Flutter render, only these numbers. That is a second
  // implementation of one geometry, which drifts the moment someone tunes a
  // curve here and forgets the other file exists. `flow_shape_geometry_ports_test.dart`
  // reads both files' constants back out as text and fails the moment they
  // stop matching, which is the only reason it is safe to keep two copies at
  // all. See `android/app/src/main/kotlin/com/spendwise/app/SpendWiseHomeWidgetRenderer.kt`.
  const barH = 10.0;
  const topY = 6.0;
  const topWidthFraction = .46;
  const marginFraction = .075;
  const control1Fraction = .42;
  const control2Fraction = .60;
  // The seventh geometry constant the widget's renderer has to mirror --
  // named, like the six above, because the Home-screen widget also draws the
  // three-branch "siblings" split, and a gap tuned here without a matching
  // change there is exactly the silent drift `flow_shape_geometry_ports_test.dart`
  // exists to catch.
  const siblingGapDp = 6.0;

  // The source bar is deliberately narrower than the canvas so the ribbon has
  // room to fan outward -- the widening is what reads as "this became these".
  final topW = w * topWidthFraction;
  final topX = (w - topW) / 2;
  final botY = h - barH - 2;
  final margin = w * marginFraction;

  final keptW = topW * keptFraction;
  final spentW = topW - keptW;

  // Bottom bars grow toward the two edges as the reveal runs.
  final keptBotX = topX - (topX - margin) * reveal;
  final spentBotRight = topX + topW + (w - margin - topX - topW) * reveal;
  final spentBotX = spentBotRight - spentW;

  final splitX = topX + keptW;
  final c1 = topY + barH + (botY - topY - barH) * control1Fraction;
  final c2 = topY + barH + (botY - topY - barH) * control2Fraction;
  final yTop = topY + barH;

  Path ribbon(double aTop, double bTop, double aBot, double bBot) => Path()
    ..moveTo(aTop, yTop)
    ..cubicTo(aTop, c1, aBot, c2, aBot, botY)
    ..lineTo(bBot, botY)
    ..cubicTo(bBot, c2, bTop, c1, bTop, yTop)
    ..close();

  // A branch of its own comes out of the kept side, because that is where
  // the money actually came from -- so kept narrows by exactly the saved
  // slice and the two still add up to what was kept before.
  final asBranch = saved == SavedTreatment.branch;
  final savedTopW = asBranch ? keptW * savedOfKept : 0.0;
  final liveKeptW = keptW - savedTopW;
  final savedBotW = asBranch ? keptW * savedOfKept : 0.0;
  final gap = (asBranch && savedBotW > 0) ? siblingGapDp * reveal : 0.0;

  final kept = <_FlowPiece>[
    _FlowPiece(
      ribbon(topX, topX + liveKeptW, keptBotX, keptBotX + liveKeptW),
      SpendWiseColors.keep.withValues(alpha: .30),
    ),
  ];
  final savedPieces = <_FlowPiece>[];
  if (asBranch) {
    savedPieces.add(
      _FlowPiece(
        ribbon(
          topX + liveKeptW,
          splitX,
          keptBotX + liveKeptW + gap,
          keptBotX + liveKeptW + gap + savedBotW,
        ),
        SpendWiseColors.mine.withValues(alpha: .34),
      ),
    );
  }
  final spend = <_FlowPiece>[
    _FlowPiece(
      ribbon(splitX, topX + topW, spentBotX, spentBotX + spentW),
      SpendWiseColors.spend.withValues(alpha: .48),
    ),
  ];

  // A seam shades the inner edge of the kept ribbon rather than dividing it,
  // so "still yours" is still one shape and still one number -- but it is
  // its own path, drawn on top, and so its own branch to tap.
  if (saved == SavedTreatment.seam) {
    final seamW = keptW * savedOfKept;
    savedPieces.add(
      _FlowPiece(
        ribbon(
          topX + keptW - seamW,
          splitX,
          keptBotX + keptW - seamW,
          keptBotX + keptW,
        ),
        SpendWiseColors.mine.withValues(alpha: .30),
      ),
    );
  }

  final trunk = _FlowPiece(
    Path()..addRect(Rect.fromLTWH(topX, topY, topW, barH)),
    SpendWiseColors.fg,
  );

  if (asBranch) {
    kept.add(
      _FlowPiece(
        Path()..addRect(Rect.fromLTWH(keptBotX, botY, liveKeptW, barH)),
        SpendWiseColors.keep,
      ),
    );
    savedPieces.add(
      _FlowPiece(
        Path()..addRect(
          Rect.fromLTWH(keptBotX + liveKeptW + gap, botY, savedBotW, barH),
        ),
        SpendWiseColors.mine,
      ),
    );
  } else {
    kept.add(
      _FlowPiece(
        Path()..addRect(Rect.fromLTWH(keptBotX, botY, keptW, barH)),
        SpendWiseColors.keep,
      ),
    );
    // The inset marks the saved part of the footing itself: same bar, same
    // total, a shaded portion and a tick where it divides -- a real, separate
    // rectangle, so a real, separate branch to tap.
    if (saved == SavedTreatment.inset) {
      final insetW = keptW * savedOfKept;
      savedPieces.add(
        _FlowPiece(
          Path()..addRect(
            Rect.fromLTWH(keptBotX + keptW - insetW, botY, insetW, barH),
          ),
          SpendWiseColors.mine,
        ),
      );
      savedPieces.add(
        _FlowPiece(
          Path()..addRect(
            Rect.fromLTWH(keptBotX + keptW - insetW - 1, botY, 1, barH),
          ),
          SpendWiseColors.background,
        ),
      );
    }
  }
  spend.add(
    _FlowPiece(
      Path()..addRect(Rect.fromLTWH(spentBotX, botY, spentW, barH)),
      SpendWiseColors.spend,
    ),
  );

  return _FlowGeometry(
    trunk: trunk,
    kept: kept,
    spend: spend,
    saved: savedPieces,
  );
}

class _FlowShapePainter extends CustomPainter {
  _FlowShapePainter({
    required this.keptFraction,
    required this.savedOfKept,
    required this.saved,
    required this.reveal,
    this.wobbleBranch,
    this.wobbleOffset = 0,
  });

  final double keptFraction;
  final double savedOfKept;
  final SavedTreatment saved;
  final double reveal;

  /// Which branch a tap has set wobbling, if any.
  final _FlowBranch? wobbleBranch;

  /// How far [wobbleBranch] is displaced right now, in logical pixels. Every
  /// other branch, and the trunk, always draw at zero.
  final double wobbleOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const barH = 10.0;
    const topY = 6.0;

    // `reveal` already widens the bottom bars out from the top one; clipping
    // to a window that grows downward over the same value turns that widen
    // into a pour -- the fill visibly travels from the received bar into its
    // branches, rather than the branches simply arriving at full width. The
    // window's top edge never rises above the bottom of the top bar, so the
    // bar itself is never clipped, only what is still below it.
    final pourTo = (topY + barH) + (h - (topY + barH)) * reveal;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, pourTo));

    final geometry = _buildFlowGeometry(
      size: size,
      keptFraction: keptFraction,
      savedOfKept: savedOfKept,
      saved: saved,
      reveal: reveal,
    );

    final paint = Paint()..style = PaintingStyle.fill;
    void drawBranch(List<_FlowPiece> pieces, _FlowBranch branch) {
      final offset = branch == wobbleBranch
          ? Offset(0, wobbleOffset)
          : Offset.zero;
      for (final piece in pieces) {
        canvas.drawPath(
          offset == Offset.zero ? piece.path : piece.path.shift(offset),
          paint..color = piece.color,
        );
      }
    }

    drawBranch(geometry.kept, _FlowBranch.kept);
    drawBranch(geometry.saved, _FlowBranch.saved);
    drawBranch(geometry.spend, _FlowBranch.spend);
    // The trunk they all hang from -- it never wobbles, so it is drawn
    // straight from the geometry with no offset applied.
    canvas.drawPath(geometry.trunk.path, paint..color = geometry.trunk.color);
    canvas.restore();
  }

  /// Carries the values it was built with, so the proportions the ribbon is
  /// currently painting can be read back -- by a debugger, and by the tests
  /// that hold it to travelling between two splits rather than jumping, and
  /// to wobbling one branch at a time.
  @override
  String toString() =>
      '_FlowShapePainter(keptFraction: $keptFraction, '
      'savedOfKept: $savedOfKept, reveal: $reveal, saved: ${saved.name}, '
      'wobbleBranch: ${wobbleBranch?.name}, wobbleOffset: $wobbleOffset)';

  @override
  bool shouldRepaint(_FlowShapePainter old) =>
      old.keptFraction != keptFraction ||
      old.savedOfKept != savedOfKept ||
      old.saved != saved ||
      old.reveal != reveal ||
      old.wobbleBranch != wobbleBranch ||
      old.wobbleOffset != wobbleOffset;
}

/// A month of running balance, drawn as steps: money does not drift, it lands
/// and then steps down. The largest single rise gets a marker because that is
/// almost always the moment salary arrived.
class BalanceLine extends StatelessWidget {
  const BalanceLine({
    super.key,
    required this.points,
    this.height = 84,
    this.color,
  });

  /// Running balance in minor units, one entry per day, oldest first.
  final List<int> points;
  final double height;

  /// Defaults to the palette's "kept" tone, which is not a compile-time
  /// constant because the palette is a user choice.
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(
      painter: _BalanceLinePainter(points, color ?? SpendWiseColors.keep),
    ),
  );
}

class _BalanceLinePainter extends CustomPainter {
  _BalanceLinePainter(this.points, this.color);

  final List<int> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rule = Paint()
      ..color = SpendWiseColors.line
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, 4), Offset(size.width, 4), rule);
    canvas.drawLine(
      Offset(0, size.height - 4),
      Offset(size.width, size.height - 4),
      rule,
    );
    if (points.length < 2) return;

    final lo = points.reduce(math.min).toDouble();
    final hi = points.reduce(math.max).toDouble();
    final span = math.max(1.0, hi - lo);
    const top = 10.0;
    final bottom = size.height - 10;

    double x(int i) => size.width * (i / (points.length - 1));
    double y(int i) => bottom - ((points[i] - lo) / span) * (bottom - top);

    final path = Path()..moveTo(0, y(0));
    for (var i = 1; i < points.length; i++) {
      path.lineTo(x(i), y(i - 1));
      path.lineTo(x(i), y(i));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );

    // Biggest single-day rise: the salary landing.
    var jump = 0;
    var jumpAt = -1;
    for (var i = 1; i < points.length; i++) {
      final delta = points[i] - points[i - 1];
      if (delta > jump) {
        jump = delta;
        jumpAt = i;
      }
    }
    final dot = Paint()..style = PaintingStyle.fill;
    if (jumpAt > 0 && jump > 0) {
      canvas.drawCircle(
        Offset(x(jumpAt), y(jumpAt)),
        2.6,
        dot..color = SpendWiseColors.fg,
      );
    }
    canvas.drawCircle(
      Offset(size.width, y(points.length - 1)),
      3.2,
      dot..color = color,
    );
  }

  @override
  bool shouldRepaint(_BalanceLinePainter old) =>
      old.points != points || old.color != color;
}

/// Proportional stacked bar. Segments carry the category ramp in order, so the
/// bar and the list beneath it are the same reading.
class SegmentBar extends StatelessWidget {
  const SegmentBar({
    super.key,
    required this.weights,
    required this.colors,
    this.height = 34,
    this.gap = 2,
    this.ids,
  });

  final List<double> weights;
  final List<Color> colors;
  final double height;
  final double gap;

  /// Identifies each segment across rebuilds, so a category's own slice
  /// travels to its new width when the figures change rather than whichever
  /// segment now happens to sit at the same position -- two categories
  /// swapping rank would otherwise read as a segment's colour snapping
  /// mid-animation while its width kept sliding toward the wrong target.
  /// Left null by callers whose segments never change rank against
  /// each other.
  final List<Object>? ids;

  @override
  Widget build(BuildContext context) {
    if (weights.isEmpty) return SizedBox(height: height);
    // The same travel FlowShape gives its own kept/spent split, so a category
    // taking a bigger bite of the month reads as the same kind of movement as
    // the ribbon above it, not an unrelated jump cut beneath it.
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : FlowShape._morphDuration;
    final total = weights.fold<double>(0, (sum, w) => sum + math.max(0.0, w));
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final usable = math.max(
            0.0,
            constraints.maxWidth - gap * (weights.length - 1),
          );
          double widthFor(int i) => total <= 0
              ? usable / weights.length
              : usable * (math.max(0.0, weights[i]) / total);
          // Stretch is load-bearing: a bare ColoredBox sized only by width
          // would collapse to zero height and draw nothing.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < weights.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                TweenAnimationBuilder<double>(
                  key: ids == null ? null : ValueKey(ids![i]),
                  tween: Tween(end: widthFor(i)),
                  duration: duration,
                  curve: Curves.easeOutQuint,
                  builder: (context, width, _) => SizedBox(
                    width: width,
                    child: ColoredBox(color: colors[i % colors.length]),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// The mono day header inside the register: weekday, day number, day net.
class RegisterDay extends StatelessWidget {
  const RegisterDay({super.key, required this.label, required this.total});

  final String label;
  final String total;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 15, 0, 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        // The date carries the sage tone the rest of the register never uses,
        // so the eye finds the day boundary without a heavier rule or a gap.
        Text(
          label.toUpperCase(),
          style: SpendWiseType.metaTight.copyWith(
            color: SpendWiseColors.keep,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: SpendWiseColors.line)),
        const SizedBox(width: 10),
        Text(total, style: SpendWiseType.metaTight),
      ],
    ),
  );
}

/// Which way the money went, for the one row that has to say so.
enum RegisterDirection {
  /// It arrived: the register's income.
  incoming,

  /// It left: the register's spending.
  outgoing,

  /// It only crossed between two accounts the same person already owns, so it
  /// neither arrived nor left.
  ownTransfer,
}

/// One dense register row: name over metadata on the left, amount right, one
/// hairline underneath and no other ornament.
///
/// Direction used to be carried by [amountColor] and by nothing else, so
/// income and expense printed the identical glyphs and differed only in a
/// hue. That is unreadable twice over -- to a screen reader, which cannot see
/// a colour at all, and to anyone who cannot separate sage from clay -- and
/// this row is both the ledger and the review inbox, the densest surface in
/// the app. It now states the direction in a sign, and once again in words
/// for the reader who is being read to.
class RegisterRow extends StatelessWidget {
  const RegisterRow({
    super.key,
    required this.name,
    required this.meta,
    required this.amount,
    required this.amountColor,
    this.ownTransfer = false,
    this.onTap,
    this.pending = false,
  });

  final String name;
  final String meta;
  final String amount;
  final Color amountColor;
  final bool ownTransfer;
  final bool pending;
  final VoidCallback? onTap;

  /// A leading sign, in any of the forms the app writes one.
  static const _signs = ['+', '−', '-'];

  /// Which way the money went, read back out of [amountColor].
  ///
  /// Every caller already derives that colour from the transaction's kind
  /// against the palette's three semantic tones, so the fact was always here
  /// -- it was simply being stated in the one form a screen reader cannot
  /// repeat. Reading it back is what lets the row say it properly without
  /// five call sites having to remember a new argument. A colour from outside
  /// the three means the caller is not talking about direction at all, and
  /// the row then says nothing about it rather than guessing.
  RegisterDirection? get _direction {
    if (ownTransfer || amountColor == SpendWiseColors.mine) {
      return RegisterDirection.ownTransfer;
    }
    if (amountColor == SpendWiseColors.keep) return RegisterDirection.incoming;
    if (amountColor == SpendWiseColors.spend) {
      return RegisterDirection.outgoing;
    }
    return null;
  }

  /// [amount] with its leading sign stripped, whoever put it there.
  String get _magnitude => amount.isNotEmpty && _signs.contains(amount[0])
      ? amount.substring(1)
      : amount;

  /// The figure as printed.
  ///
  /// Callers hand over a bare magnitude because `formatAmount` is unsigned
  /// everywhere else in the app, and making it signed by default would put a
  /// `+` in front of every debt balance and every category total. The sign
  /// belongs to the row that knows which way the money went. A caller that
  /// already signed its own figure -- the help and onboarding examples write
  /// theirs out by hand -- keeps exactly what it wrote.
  String get _printedAmount {
    if (amount.isEmpty || _signs.contains(amount[0])) return amount;
    return switch (_direction) {
      RegisterDirection.incoming => '+$amount',
      RegisterDirection.outgoing => '−$amount',
      // Money crossing between a person's own accounts neither arrived nor
      // left, so either sign would be a claim that is not true. The ⇄ before
      // the name is what marks it.
      RegisterDirection.ownTransfer || null => amount,
    };
  }

  /// What one row sounds like: what it was, which way the money went, how
  /// much, and whether it is still waiting to be confirmed.
  ///
  /// The direction is spoken as a word rather than left to the sign, because
  /// a screen reader meeting `−` either says "minus" or skips it, and neither
  /// of those is the sentence. The metadata is spoken as it was given, not as
  /// it is drawn, because the row draws it in capitals and a capitalised word
  /// is liable to be spelled out letter by letter.
  String get _semanticLabel {
    final amountSpoken = switch (_direction) {
      RegisterDirection.incoming => '$_magnitude in',
      RegisterDirection.outgoing => '$_magnitude out',
      RegisterDirection.ownTransfer =>
        '$_magnitude moved between your own accounts',
      null => _magnitude,
    };
    return [
      name,
      amountSpoken,
      if (meta.isNotEmpty) meta,
      // The pending mark is a five-pixel dot with no text anywhere near it,
      // so this sentence is the only way anyone hears that the row is still
      // an alert waiting to be confirmed rather than a settled entry.
      if (pending) 'Not confirmed yet',
    ].join('. ');
  }

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      label: _semanticLabel,
      button: onTap != null,
      // The row's own Text nodes are dropped rather than merged into the
      // label above them: read out as they are drawn they would shout the
      // metadata in capitals, give the amount without saying which way it
      // went, and say nothing whatsoever about the pending dot.
      child: InkWell(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: SpendWiseColors.line)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (ownTransfer)
                            Padding(
                              padding: const EdgeInsets.only(right: 5),
                              child: Text(
                                '⇄',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: SpendWiseColors.mine,
                                ),
                              ),
                            ),
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SpendWiseType.row,
                            ),
                          ),
                          if (pending)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: SpendWiseColors.spend,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SpendWiseType.metaTight,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Deliberately not flexible. It is laid out at its natural
                // width first and the name takes whatever is left, because a
                // figure is the one thing on this row that must never be
                // abbreviated -- an ellipsised amount is a wrong amount,
                // while a clipped shop name is still the same shop.
                Text(
                  _printedAmount,
                  style: SpendWiseType.rowStrong.copyWith(color: amountColor),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// A block in the Accounts map. Height carries the share of the total, so the
/// biggest account is literally the biggest thing on screen.
class ProportionBlock extends StatelessWidget {
  const ProportionBlock({
    super.key,
    required this.name,
    required this.amount,
    required this.height,
    required this.filled,
    this.detail = '',
    this.onTap,
  });

  final String name;
  final String amount;
  final String detail;
  final double height;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? SpendWiseColors.bg : SpendWiseColors.fg;
    final compact = height < 44;
    // The map's whole idea is that a bigger balance is a bigger block, so a
    // balance that actually changes has to be seen changing size -- snapping
    // straight to a new height said the same thing a bar chart with no axis
    // does: a number moved, with no sense of how much.
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutQuint,
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            // A held-back block is money too, so it gets a tinted ground and a
            // solid left rule -- at 7% on a graphite screen it read as a hole.
            color: filled
                ? SpendWiseColors.keep
                : SpendWiseColors.keep.withValues(alpha: .11),
            border: filled
                ? null
                : Border(
                    left: BorderSide(color: SpendWiseColors.keep, width: 2),
                    top: BorderSide(color: SpendWiseColors.edge),
                    right: BorderSide(color: SpendWiseColors.edge),
                    bottom: BorderSide(color: SpendWiseColors.edge),
                  ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SpendWiseType.row.copyWith(
                        color: fg,
                        fontSize: compact ? 13 : 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (detail.isNotEmpty && !compact) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SpendWiseType.metaTight.copyWith(
                          color: fg.withValues(alpha: .72),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                amount,
                style: SpendWiseType.rowStrong.copyWith(
                  color: fg,
                  fontSize: compact ? 13 : 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-width inverted action bar. Used where one tap resolves a whole rule --
/// it is the loudest object in the app and there is never more than one per
/// decision.
class PrimaryAction extends StatelessWidget {
  const PrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.tone,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final background = tone ?? SpendWiseColors.fg;
    return Semantics(
      button: true,
      enabled: onPressed != null && !busy,
      child: InkWell(
        onTap: busy ? null : onPressed,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          color: onPressed == null
              ? background.withValues(alpha: .32)
              : background,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: SpendWiseType.rowStrong.copyWith(
                    color: SpendWiseColors.bg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: SpendWiseColors.bg,
                  ),
                )
              else
                const Text(
                  '→',
                  style: TextStyle(
                    fontSize: 16,
                    color: SpendWiseColors.bg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quiet full-bleed state for "there is nothing here, and that is fine".
class RestState extends StatelessWidget {
  const RestState({
    super.key,
    required this.headline,
    required this.detail,
    this.action,
  });

  final String headline;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: SpendWiseTheme.gutter,
      vertical: 44,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 34, height: 2, color: SpendWiseColors.edge),
        const SizedBox(height: 18),
        Text(headline, style: SpendWiseType.statement),
        const SizedBox(height: 10),
        Text(detail, style: SpendWiseType.body),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}
