import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';

/// The keypad and the row of slots above it.
///
/// Round keys are the phone convention, but this app has no rounded corner
/// anywhere else, so the pad is a ruled grid instead: hairlines, square slots,
/// figures set in the same face as every other number in the ledger. It also
/// happens to give bigger targets than circles of the same footprint.
class PinDots extends StatelessWidget {
  const PinDots({
    super.key,
    required this.length,
    required this.filled,
    this.error = false,
    this.muted = false,
  });

  final int length;
  final int filled;
  final bool error;

  /// While the PIN is being checked: entered, but not yet answered.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final tone = error ? SpendWiseColors.spend : SpendWiseColors.fg;
    // A long PIN must not run off the edge of a narrow phone, so the slots
    // tighten rather than wrap.
    final size = length > 6 ? 12.0 : 15.0;
    final gap = length > 6 ? 4.0 : 7.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < length; index++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            margin: EdgeInsets.symmetric(horizontal: gap),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: index < filled
                  ? tone.withValues(alpha: muted ? .45 : 1)
                  : Colors.transparent,
              border: Border.all(
                color: index < filled ? tone : SpendWiseColors.dim,
                width: 1.4,
              ),
            ),
          ),
      ],
    );
  }
}

/// One entry in the bottom-left slot: biometrics, a cancel, or nothing.
class PinPadAction {
  const PinPadAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.leading,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final PinPadAction? leading;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final row in const [
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7', '8', '9'],
      ])
        _PadRow(
          children: [
            for (final digit in row)
              _PadKey(
                enabled: enabled,
                onTap: () => onDigit(digit),
                child: Text(digit, style: _digitStyle),
              ),
          ],
        ),
      _PadRow(
        children: [
          if (leading case final action?)
            _PadKey(
              enabled: enabled,
              onTap: action.onTap,
              semanticLabel: action.label,
              child: Icon(action.icon, size: 24, color: SpendWiseColors.keep),
            )
          else
            const _PadKey.blank(),
          _PadKey(
            enabled: enabled,
            onTap: () => onDigit('0'),
            child: const Text('0', style: _digitStyle),
          ),
          _PadKey(
            enabled: enabled,
            onTap: onBackspace,
            semanticLabel: 'Delete',
            child: const Icon(
              Icons.backspace_outlined,
              size: 21,
              color: SpendWiseColors.dim,
            ),
          ),
        ],
      ),
    ],
  );

  static const _digitStyle = TextStyle(
    fontFamily: SpendWiseType.sans,
    fontSize: 25,
    fontWeight: FontWeight.w600,
    height: 1,
    color: SpendWiseColors.fg,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

class _PadRow extends StatelessWidget {
  const _PadRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: SpendWiseColors.line)),
    ),
    child: IntrinsicHeight(
      child: Row(
        children: [for (final child in children) Expanded(child: child)],
      ),
    ),
  );
}

class _PadKey extends StatelessWidget {
  const _PadKey({
    required this.child,
    required this.onTap,
    this.enabled = true,
    this.semanticLabel,
  });

  const _PadKey.blank()
    : child = const SizedBox.shrink(),
      onTap = null,
      enabled = false,
      semanticLabel = null;

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label: semanticLabel,
    child: InkWell(
      // Feedback is off because the tap already answers with a haptic and a
      // slot filling in; a ripple on top reads as lag.
      onTap: enabled && onTap != null
          ? () {
              HapticFeedback.selectionClick();
              onTap!();
            }
          : null,
      child: Opacity(
        opacity: enabled ? 1 : .35,
        child: SizedBox(height: 72, child: Center(child: child)),
      ),
    ),
  );
}

/// A brief left-right jolt, used only to answer a wrong PIN.
class ShakeBox extends StatelessWidget {
  const ShakeBox({super.key, required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, inner) {
      final t = animation.value;
      // Three decaying swings: enough to read as "no", short enough not to
      // delay the next attempt.
      final offset = t == 0 ? 0.0 : (1 - t) * 9 * math.sin(t * math.pi * 6);
      return Transform.translate(offset: Offset(offset, 0), child: inner);
    },
    child: child,
  );
}
