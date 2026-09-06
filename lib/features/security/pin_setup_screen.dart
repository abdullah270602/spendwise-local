import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../security/app_lock.dart';
import 'pin_pad.dart';

/// Choosing a PIN, or proving you know the current one.
///
/// Returns the digits to the caller rather than storing anything itself: the
/// same screen sets a new PIN, confirms it, and unlocks the settings behind
/// the old one, and only the caller knows which of those it asked for.
///
/// Length is the person's business. Four is the floor because three is not a
/// PIN; above that there is no cutoff worth defending, and there is no opinion
/// here about which digits are allowed. A rule that rejects a birthday teaches
/// nobody anything and mostly produces a PIN that gets written down.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({
    super.key,
    required this.title,
    this.confirm = true,
    this.fixedLength,
    this.verify,
    this.prompt,
  });

  /// Ask twice and check the two agree. Off when proving an existing PIN.
  final bool confirm;

  /// Set when the length is already decided, i.e. an existing PIN.
  final int? fixedLength;

  /// Checks the digits against something. Returning false shows a wrong-PIN
  /// answer instead of accepting.
  final Future<bool> Function(String pin)? verify;

  final String title;
  final String? prompt;

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen>
    with SingleTickerProviderStateMixin {
  String entry = '';
  String? first;
  bool busy = false;
  String? problem;

  late final AnimationController shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  bool get confirming => first != null;

  /// The length being entered against, or null while it is still open.
  int? get expected =>
      widget.fixedLength ?? (confirming ? first!.length : null);

  /// How many slots to draw. While the length is still open the row grows
  /// with what has been typed, so it reads as a count rather than a target.
  int get slots =>
      expected ??
      entry.length.clamp(
        AppLockController.minPinLength,
        AppLockController.maxPinLength,
      );

  bool get canCommit =>
      expected == null && entry.length >= AppLockController.minPinLength;

  @override
  void dispose() {
    shake.dispose();
    super.dispose();
  }

  void _press(String digit) {
    if (busy) return;
    final limit = expected ?? AppLockController.maxPinLength;
    if (entry.length >= limit) return;
    setState(() {
      entry += digit;
      problem = null;
    });
    if (entry.length == expected) _commit();
  }

  void _backspace() {
    if (busy || entry.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      entry = entry.substring(0, entry.length - 1);
      problem = null;
    });
  }

  Future<void> _commit() async {
    final digits = entry;

    if (widget.verify case final check?) {
      setState(() => busy = true);
      final ok = await check(digits);
      if (!mounted) return;
      if (!ok) return _reject('Not your current PIN');
      setState(() => busy = false);
      if (mounted) Navigator.pop(context, digits);
      return;
    }

    if (!widget.confirm) return Navigator.pop(context, digits);

    if (!confirming) {
      setState(() {
        first = digits;
        entry = '';
      });
      return;
    }

    if (digits != first) {
      setState(() => first = null);
      return _reject('Those did not match');
    }
    Navigator.pop(context, digits);
  }

  void _reject(String message) {
    HapticFeedback.heavyImpact();
    shake.forward(from: 0);
    setState(() {
      busy = false;
      problem = message;
      entry = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 44),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SpendWiseTheme.gutter,
              ),
              child: Text(
                confirming
                    ? 'Once more'
                    : (widget.prompt ?? 'Four digits or more'),
                textAlign: TextAlign.center,
                style: SpendWiseType.lead,
              ),
            ),
            const SizedBox(height: 22),
            ShakeBox(
              animation: shake,
              child: PinDots(
                length: slots,
                filled: entry.length,
                error: problem != null,
                muted: busy,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 22,
              child: problem == null
                  ? const SizedBox.shrink()
                  : Text(
                      problem!,
                      textAlign: TextAlign.center,
                      style: SpendWiseType.body.copyWith(
                        fontSize: 12.5,
                        color: SpendWiseColors.spend,
                      ),
                    ),
            ),
            const Spacer(),
            Padding(
              padding: EdgeInsets.fromLTRB(
                SpendWiseTheme.gutter,
                0,
                SpendWiseTheme.gutter,
                bottomInset + 10,
              ),
              child: PinPad(
                enabled: !busy,
                onDigit: _press,
                onBackspace: _backspace,
                // The pad's spare key becomes "done" once the PIN is long
                // enough, so choosing your own length costs no extra chrome.
                leading: canCommit
                    ? PinPadAction(
                        icon: Icons.check_rounded,
                        label: 'Use this PIN',
                        onTap: _commit,
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
