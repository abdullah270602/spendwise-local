import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../features/shell/spendwise_view_model.dart';

/// Amount without the currency code. Every dense surface in the redesign shows
/// bare figures -- the currency is stated once per screen, not once per row,
/// which is what let the register get twice as tight.
String formatAmount(MoneyViewData money, {bool signed = false, bool cents = true}) {
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
    formatAmount(
      MoneyViewData(minorUnits),
      signed: signed,
      cents: cents,
    );

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
      children: [Expanded(child: label), trailing!],
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
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: SpendWiseColors.edge),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < options.length; i++)
          Semantics(
            selected: i == selected,
            button: true,
            child: InkWell(
              onTap: i == selected ? null : () => onSelected(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                color: i == selected
                    ? SpendWiseColors.fg
                    : Colors.transparent,
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
      ],
    ),
  );
}

/// The Home screen in one object: a bar of everything that came in, splitting
/// into the share still yours and the share that left. True proportion -- the
/// thin clay thread is thin because 11% is thin.
class FlowShape extends StatelessWidget {
  const FlowShape({
    super.key,
    required this.receivedMinor,
    required this.keptMinor,
    required this.spentMinor,
    this.height = 168,
    this.animate = true,
  });

  final int receivedMinor;
  final int keptMinor;
  final int spentMinor;
  final double height;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final total = math.max(1, keptMinor.abs() + spentMinor.abs());
    final keptFraction = (keptMinor.abs() / total).clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: animate ? 0 : 1, end: 1),
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => CustomPaint(
        size: Size.infinite,
        painter: _FlowShapePainter(keptFraction: keptFraction, reveal: t),
        child: SizedBox(height: height, width: double.infinity),
      ),
    );
  }
}

class _FlowShapePainter extends CustomPainter {
  _FlowShapePainter({required this.keptFraction, required this.reveal});

  final double keptFraction;
  final double reveal;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const barH = 10.0;

    // The source bar is deliberately narrower than the canvas so the ribbon has
    // room to fan outward -- the widening is what reads as "this became these".
    final topW = w * .46;
    final topX = (w - topW) / 2;
    const topY = 6.0;
    final botY = h - barH - 2;
    final margin = w * .075;

    final keptW = topW * keptFraction;
    final spentW = topW - keptW;

    // Bottom bars grow toward the two edges as the reveal runs.
    final keptBotX = topX - (topX - margin) * reveal;
    final spentBotRight = topX + topW + (w - margin - topX - topW) * reveal;
    final spentBotX = spentBotRight - spentW;

    final splitX = topX + keptW;
    final c1 = topY + barH + (botY - topY - barH) * .42;
    final c2 = topY + barH + (botY - topY - barH) * .60;
    final yTop = topY + barH;

    Path ribbon(double aTop, double bTop, double aBot, double bBot) => Path()
      ..moveTo(aTop, yTop)
      ..cubicTo(aTop, c1, aBot, c2, aBot, botY)
      ..lineTo(bBot, botY)
      ..cubicTo(bBot, c2, bTop, c1, bTop, yTop)
      ..close();

    final paint = Paint()..style = PaintingStyle.fill;

    canvas.drawPath(
      ribbon(topX, splitX, keptBotX, keptBotX + keptW),
      paint..color = SpendWiseColors.keep.withValues(alpha: .30),
    );
    canvas.drawPath(
      ribbon(splitX, topX + topW, spentBotX, spentBotX + spentW),
      paint..color = SpendWiseColors.spend.withValues(alpha: .48),
    );

    canvas.drawRect(
      Rect.fromLTWH(topX, topY, topW, barH),
      paint..color = SpendWiseColors.fg,
    );
    canvas.drawRect(
      Rect.fromLTWH(keptBotX, botY, keptW, barH),
      paint..color = SpendWiseColors.keep,
    );
    canvas.drawRect(
      Rect.fromLTWH(spentBotX, botY, spentW, barH),
      paint..color = SpendWiseColors.spend,
    );
  }

  @override
  bool shouldRepaint(_FlowShapePainter old) =>
      old.keptFraction != keptFraction || old.reveal != reveal;
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
  });

  final List<double> weights;
  final List<Color> colors;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (weights.isEmpty) return SizedBox(height: height);
    return SizedBox(
      height: height,
      // Stretch is load-bearing: an Expanded child only gets a tight width,
      // so a bare ColoredBox would size to zero height and draw nothing.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < weights.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(
              flex: math.max(1, (weights[i] * 10000).round()),
              child: ColoredBox(color: colors[i % colors.length]),
            ),
          ],
        ],
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
        Expanded(
          child: Container(height: 1, color: SpendWiseColors.line),
        ),
        const SizedBox(width: 10),
        Text(total, style: SpendWiseType.metaTight),
      ],
    ),
  );
}

/// One dense register row: name over metadata on the left, amount right, one
/// hairline underneath and no other ornament.
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

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
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
          Text(
            amount,
            style: SpendWiseType.rowStrong.copyWith(color: amountColor),
          ),
        ],
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        onTap: onTap,
        child: Container(
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
