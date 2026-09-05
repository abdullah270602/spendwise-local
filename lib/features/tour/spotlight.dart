import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';

/// One stop on the walkthrough.
@immutable
class SpotlightStop {
  const SpotlightStop({
    required this.title,
    required this.body,
    this.rect,
    this.onEnter,
  });

  final String title;
  final String body;

  /// What to cut out of the scrim, in global coordinates. Null dims the whole
  /// screen, which is right for a stop that is about the screen itself.
  final Rect Function()? rect;

  /// Run before the stop is drawn, e.g. to switch to the tab being described.
  final VoidCallback? onEnter;
}

/// A spotlight walkthrough over the live app.
///
/// Deliberately opt-in and short. The measured record for tours that fire on
/// their own is poor -- a controlled study found people who took one no more
/// successful than those who skipped it, and more likely to call the task
/// hard -- but a tour someone asked for, of four stops on one screen, is the
/// configuration that actually gets finished.
///
/// Tapping anywhere advances. That is the one simplification that removes
/// most of the difficulty: the scrim never has to pass a tap through to the
/// thing underneath, so the visible hole and the touchable hole can never
/// disagree.
class Spotlight with WidgetsBindingObserver {
  Spotlight._(this._stops, this._onDone);

  final List<SpotlightStop> _stops;
  final VoidCallback? _onDone;
  OverlayEntry? _entry;
  int _index = 0;

  static Spotlight? _current;

  /// Starts a walkthrough, replacing any that is already running.
  static void run(
    BuildContext context,
    List<SpotlightStop> stops, {
    VoidCallback? onDone,
  }) {
    if (stops.isEmpty) return;
    _current?._dismiss();
    final tour = Spotlight._(stops, onDone);
    _current = tour;
    tour._show(context);
  }

  static bool get isRunning => _current != null;

  /// System back leaves the tour rather than the screen underneath it.
  ///
  /// A PopScope would be the obvious way and does nothing here: an overlay
  /// entry is not a route, so the Navigator never consults it and back pops
  /// whatever is beneath, leaving an orphaned scrim over a screen the user
  /// did not expect. Answering the pop at the binding is what actually
  /// intercepts it.
  @override
  Future<bool> didPopRoute() async {
    if (_entry == null) return false;
    _dismiss();
    return true;
  }

  void _show(BuildContext context) {
    final overlay = Overlay.of(context, rootOverlay: true);
    WidgetsBinding.instance.addObserver(this);
    _stops[_index].onEnter?.call();
    _entry = OverlayEntry(
      builder: (overlayContext) => _SpotlightLayer(
        stop: _stops[_index],
        index: _index,
        total: _stops.length,
        onNext: _next,
        onSkip: _dismiss,
      ),
    );
    // After the frame, so a stop that switched tabs is measuring the tab it
    // actually landed on rather than the one it left.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_entry case final entry?) overlay.insert(entry);
    });
  }

  void _next() {
    if (_index >= _stops.length - 1) return _dismiss();
    _index++;
    _stops[_index].onEnter?.call();
    // One frame for the tab switch to lay out before the hole is measured.
    WidgetsBinding.instance.addPostFrameCallback((_) => _entry?.markNeedsBuild());
    _entry?.markNeedsBuild();
  }

  void _dismiss() {
    WidgetsBinding.instance.removeObserver(this);
    _entry?.remove();
    _entry = null;
    if (identical(_current, this)) _current = null;
    _onDone?.call();
  }
}

class _SpotlightLayer extends StatelessWidget {
  const _SpotlightLayer({
    required this.stop,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onSkip,
  });

  final SpotlightStop stop;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final hole = stop.rect?.call();
    final last = index == total - 1;

    // Put the card on the roomier side of the hole, and out of its way.
    final above = hole != null && hole.top > size.height - hole.bottom;

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onNext,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _ScrimPainter(hole)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: above ? null : (hole?.bottom ?? size.height * .34) + 22,
              bottom: above ? size.height - hole.top + 22 : null,
              child: _Card(
                stop: stop,
                index: index,
                total: total,
                last: last,
                onNext: onNext,
                onSkip: onSkip,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The scrim, with a square hole in it.
///
/// One path with an even-odd fill rather than a saveLayer and BlendMode.clear:
/// no offscreen layer per frame, and any number of holes for free.
class _ScrimPainter extends CustomPainter {
  const _ScrimPainter(this.hole);

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRect(Offset.zero & size);
    if (hole case final rect?) {
      path.addRect(rect.inflate(4));
      path.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(
      path,
      Paint()..color = SpendWiseColors.bg.withValues(alpha: .78),
    );
    if (hole case final rect?) {
      canvas.drawRect(
        rect.inflate(4),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = SpendWiseColors.fg,
      );
    }
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.hole != hole;
}

class _Card extends StatelessWidget {
  const _Card({
    required this.stop,
    required this.index,
    required this.total,
    required this.last,
    required this.onNext,
    required this.onSkip,
  });

  final SpotlightStop stop;
  final int index;
  final int total;
  final bool last;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: SpendWiseTheme.gutter),
    child: Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      decoration: BoxDecoration(
        color: SpendWiseColors.bg,
        border: Border.all(color: SpendWiseColors.fg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('${index + 1} of $total'),
          const SizedBox(height: 10),
          Text(stop.title, style: SpendWiseType.lead),
          const SizedBox(height: 5),
          Text(stop.body, style: SpendWiseType.body.copyWith(fontSize: 13.5)),
          const SizedBox(height: 14),
          Row(
            children: [
              // Skip stays on every stop, not just the first.
              TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: SpendWiseColors.dim,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Skip'),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onNext();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Text(
                    last ? 'Done' : 'Next',
                    style: SpendWiseType.rowStrong.copyWith(
                      color: SpendWiseColors.keep,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Asking for the walkthrough from somewhere that is not the shell.
///
/// The guide sits two routes above the tabs it wants to point at, so it
/// raises this instead of reaching down through the tree; the shell listens,
/// unwinds back to itself, and runs the tour.
final walkthroughRequested = ValueNotifier<int>(0);
