import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../features/shell/spendwise_view_model.dart';
import 'shape_kit.dart';

String formatMoney(MoneyViewData money, {bool signed = false}) {
  final value = money.majorUnits.abs();
  final fixed = value.toStringAsFixed(2);
  final pieces = fixed.split('.');
  final whole = pieces.first;
  final grouped = whole.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );
  final decimals = pieces.last == '00' ? '' : '.${pieces.last}';
  final prefix = signed
      ? (money.minorUnits < 0 ? '−' : '+')
      : (money.minorUnits < 0 ? '−' : '');
  return '$prefix${money.currency} $grouped$decimals';
}

String titleCase(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

/// The "Split" mark: one band of income enters, and leaves as a wide band that
/// is still yours plus a thin clay thread that is gone. It is the Home screen
/// compressed into a glyph, which is why it is the app icon too.
class SpendWiseMark extends StatelessWidget {
  const SpendWiseMark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'SpendWise',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _SplitMarkPainter()),
    ),
  );
}

class _SplitMarkPainter extends CustomPainter {
  /// Authored on the 64-unit grid used in `design/brand.html`; content spans
  /// x 10..52 and y 8..56, so it is fitted rather than simply scaled.
  static const _contentLeft = 10.0;
  static const _contentTop = 8.0;
  static const _contentWidth = 42.0;
  static const _contentHeight = 48.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale =
        size.shortestSide /
        (_contentHeight > _contentWidth ? _contentHeight : _contentWidth);
    final dx = (size.width - _contentWidth * scale) / 2 - _contentLeft * scale;
    final dy = (size.height - _contentHeight * scale) / 2 - _contentTop * scale;

    canvas
      ..save()
      ..translate(dx, dy)
      ..scale(scale);

    final kept = Path()
      ..moveTo(24, 8)
      ..lineTo(24, 20)
      ..cubicTo(24, 34, 10, 40, 10, 56)
      ..lineTo(22, 56)
      ..cubicTo(22, 40, 36, 34, 36, 20)
      ..lineTo(36, 8)
      ..close();
    final spent = Path()
      ..moveTo(36, 8)
      ..lineTo(36, 20)
      ..cubicTo(36, 34, 49, 40, 49, 56)
      ..lineTo(52, 56)
      ..cubicTo(52, 40, 39, 34, 39, 20)
      ..lineTo(39, 8)
      ..close();

    final paint = Paint()..style = PaintingStyle.fill;
    canvas
      ..drawPath(kept, paint..color = SpendWiseColors.fg)
      ..drawPath(spent, paint..color = SpendWiseColors.spend)
      ..restore();
  }

  @override
  bool shouldRepaint(_SplitMarkPainter oldDelegate) => false;
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: Eyebrow(title)),
        if (action != null)
          onAction == null
              ? Text(
                  action!,
                  style: SpendWiseType.rowStrong.copyWith(fontSize: 13),
                )
              : TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(action!),
                ),
      ],
    ),
  );
}

/// Left-aligned, rule-led, no circle-in-a-tint icon: the same rest state the
/// tab screens use, kept here for the routes pushed on top of them.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => RestState(
    headline: title,
    detail: message,
    action: action == null
        ? null
        : OutlinedButton(onPressed: onAction, child: Text(action!)),
  );
}

/// States the one promise the whole app is built on. Quiet by default -- it is
/// reassurance, not an advertisement.
class PrivacyBanner extends StatelessWidget {
  const PrivacyBanner({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.only(top: compact ? 10 : 13),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: SpendWiseColors.edge)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            Icons.lock_outline_rounded,
            color: SpendWiseColors.keep,
            size: 15,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            compact
                ? 'Encrypted on this device. No account, no cloud.'
                : 'Your ledger stays encrypted on this device. SpendWise has '
                      'no account, cloud, analytics, or hidden uploads.',
            style: SpendWiseType.body.copyWith(fontSize: 12.5),
          ),
        ),
      ],
    ),
  );
}
