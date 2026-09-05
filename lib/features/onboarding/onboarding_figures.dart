import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';

/// Brings a card's parts in one after another.
///
/// Motion here is doing a job rather than decorating: an onboarding card that
/// simply exists reads as a static poster, and one whose pieces arrive in
/// order reads as an explanation. The stagger is short enough that anyone
/// tapping straight through never waits for it.
class Stagger extends StatelessWidget {
  const Stagger({
    super.key,
    required this.children,
    this.step = const Duration(milliseconds: 90),
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final List<Widget> children;
  final Duration step;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: crossAxisAlignment,
    children: [
      for (var index = 0; index < children.length; index++)
        _Enter(delay: step * index, child: children[index]),
    ],
  );
}

class _Enter extends StatefulWidget {
  const _Enter({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_Enter> createState() => _EnterState();
}

class _EnterState extends State<_Enter> with SingleTickerProviderStateMixin {
  static const _travel = Duration(milliseconds: 380);

  /// The wait is part of the curve rather than a Timer that fires later. A
  /// pending timer outlives a widget test and fails it, and more importantly
  /// it can fire into a disposed card when someone pages through quickly.
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: widget.delay + _travel,
  );

  late final Animation<double> entrance = CurvedAnimation(
    parent: controller,
    curve: Interval(
      widget.delay.inMilliseconds /
          (widget.delay + _travel).inMilliseconds.clamp(1, 1 << 30),
      1,
      curve: Curves.easeOut,
    ),
  );

  @override
  void initState() {
    super.initState();
    // Someone who turned animations off is usually telling you they make
    // them ill, so land on the finished frame straight away.
    if (WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
        .disableAnimations) {
      controller.value = 1;
    } else {
      controller.forward();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: entrance,
    builder: (context, child) => Opacity(
      opacity: entrance.value,
      child: Transform.translate(
        offset: Offset(0, 14 * (1 - entrance.value)),
        child: child,
      ),
    ),
    child: widget.child,
  );
}

/// What notification access actually buys, drawn.
///
/// The claim on this card is that alerts come in and nothing goes out. That
/// is a shape before it is a sentence, and the shape is checkable at a glance
/// in a way three bullet points are not.
class ClosedCircuit extends StatelessWidget {
  const ClosedCircuit({super.key, this.granted = false});

  final bool granted;

  static const _sources = ['Bank', 'Wallet', 'Messages'];

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          for (final label in _sources) ...[
            if (label != _sources.first) const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  border: Border.all(color: SpendWiseColors.edge),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: SpendWiseType.metaTight.copyWith(
                    color: granted
                        ? SpendWiseColors.fg
                        : SpendWiseColors.dim,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      SizedBox(
        height: 46,
        child: CustomPaint(
          size: Size.infinite,
          painter: _FunnelPainter(lit: granted),
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: granted ? SpendWiseColors.fg : SpendWiseColors.edge,
            width: granted ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SpendWiseMark(size: 20),
            const SizedBox(width: 10),
            Text(
              'SpendWise',
              style: SpendWiseType.rowStrong.copyWith(fontSize: 14),
            ),
          ],
        ),
      ),
      SizedBox(
        height: 34,
        child: CustomPaint(
          size: Size.infinite,
          painter: _BlockedPainter(),
        ),
      ),
      Text(
        'Nothing leaves the phone',
        style: SpendWiseType.metaTight.copyWith(color: SpendWiseColors.keep),
      ),
    ],
  );
}

/// Three lines converging into one, with an arrow at the bottom.
class _FunnelPainter extends CustomPainter {
  const _FunnelPainter({required this.lit});

  final bool lit;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = lit ? SpendWiseColors.dim : SpendWiseColors.edge;

    final third = size.width / 3;
    final joinY = size.height * .55;
    final centre = size.width / 2;

    for (var index = 0; index < 3; index++) {
      final x = third * index + third / 2;
      canvas
        ..drawLine(Offset(x, 0), Offset(x, joinY), paint)
        ..drawLine(Offset(x, joinY), Offset(centre, joinY), paint);
    }
    canvas.drawLine(
      Offset(centre, joinY),
      Offset(centre, size.height - 6),
      paint,
    );
    // Arrowhead.
    final head = Path()
      ..moveTo(centre - 4, size.height - 7)
      ..lineTo(centre, size.height)
      ..lineTo(centre + 4, size.height - 7);
    canvas.drawPath(head, paint);
  }

  @override
  bool shouldRepaint(_FunnelPainter old) => old.lit != lit;
}

/// A line that runs into a wall.
class _BlockedPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.width / 2;
    final wallY = size.height - 12;
    canvas
      ..drawLine(
        Offset(centre, 0),
        Offset(centre, wallY),
        Paint()
          ..strokeWidth = 1
          ..color = SpendWiseColors.edge,
      )
      ..drawLine(
        Offset(centre - 34, wallY),
        Offset(centre + 34, wallY),
        Paint()
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.square
          ..color = SpendWiseColors.keep,
      );
  }

  @override
  bool shouldRepaint(_BlockedPainter old) => false;
}

/// The apps being watched, as their own icons.
///
/// A list of names is a list of words; the icons are the thing the person
/// actually recognises on their home screen, and seeing exactly three of them
/// is the whole trust argument on this card.
class SourceGrid extends StatelessWidget {
  const SourceGrid({super.key, required this.sources});

  final List<SourceViewData> sources;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) {
      return Row(
        children: [
          for (var index = 0; index < 4; index++) ...[
            if (index > 0) const SizedBox(width: 10),
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: SpendWiseColors.line),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final source in sources.take(8))
          _SourceTile(label: source.label, icon: source.iconPng),
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.label, required this.icon});

  final String label;
  final Uint8List? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 72,
    child: Column(
      children: [
        Container(
          width: 46,
          height: 46,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: SpendWiseColors.edge),
          ),
          child: icon == null
              ? const Icon(
                  Icons.apps_rounded,
                  size: 18,
                  color: SpendWiseColors.dim,
                )
              : Image.memory(icon!, filterQuality: FilterQuality.medium),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: SpendWiseType.body.copyWith(fontSize: 10.5),
        ),
      ],
    ),
  );
}

/// How an alert finds its way to the right account.
class RoutingFigure extends StatelessWidget {
  const RoutingFigure({super.key, required this.suffix});

  /// What the person has typed so far, so the figure is about their account.
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final digits = suffix.isEmpty ? '4821' : suffix;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        border: Border.all(color: SpendWiseColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              style: SpendWiseType.meta.copyWith(fontSize: 11.5),
              children: [
                const TextSpan(text: 'Rs 2,450.00 debited from A/C '),
                TextSpan(
                  text: '****$digits',
                  style: TextStyle(
                    color: SpendWiseColors.mine,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                    decorationColor: SpendWiseColors.mine,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Container(width: 14, height: 2, color: SpendWiseColors.mine),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'lands in the account ending $digits',
                  style: SpendWiseType.body.copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
