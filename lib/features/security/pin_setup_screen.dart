import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import 'pin_pad.dart';

/// Choosing a PIN, or proving you know the current one.
///
/// Returns the digits to the caller rather than storing anything itself: the
/// same screen sets a new PIN, confirms it, and unlocks the settings behind
/// the old one, and only the caller knows which of those it asked for.
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
  late int length = widget.fixedLength ?? 4;
  String entry = '';
  String? first;
  bool busy = false;
  String? problem;

  late final AnimationController shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  bool get confirming => first != null;

  @override
  void dispose() {
    shake.dispose();
    super.dispose();
  }

  void _press(String digit) {
    if (busy || entry.length >= length) return;
    setState(() {
      entry += digit;
      problem = null;
    });
    if (entry.length == length) _advance();
  }

  void _backspace() {
    if (busy || entry.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      entry = entry.substring(0, entry.length - 1);
      problem = null;
    });
  }

  Future<void> _advance() async {
    final digits = entry;

    if (widget.verify case final check?) {
      setState(() => busy = true);
      final ok = await check(digits);
      if (!mounted) return;
      if (!ok) return _reject('That is not your current PIN');
      setState(() => busy = false);
      if (mounted) Navigator.pop(context, digits);
      return;
    }

    if (!widget.confirm) {
      Navigator.pop(context, digits);
      return;
    }

    if (!confirming) {
      // A PIN made of one repeated digit or a straight run is the first thing
      // anyone tries. Say so at the moment of choosing, not afterwards.
      if (_tooObvious(digits)) {
        return _reject('Pick something less guessable than $digits');
      }
      setState(() {
        first = digits;
        entry = '';
      });
      return;
    }

    if (digits != first) {
      setState(() => first = null);
      return _reject('Those did not match. Start again.');
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

  static bool _tooObvious(String pin) {
    if (pin.split('').toSet().length == 1) return true;
    final codes = pin.codeUnits;
    var ascending = true, descending = true;
    for (var i = 1; i < codes.length; i++) {
      if (codes[i] != codes[i - 1] + 1) ascending = false;
      if (codes[i] != codes[i - 1] - 1) descending = false;
    }
    return ascending || descending;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final canChooseLength = widget.fixedLength == null && !confirming;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Spacer(flex: 2),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SpendWiseTheme.gutter,
              ),
              child: Text(
                confirming
                    ? 'Enter it once more'
                    : (widget.prompt ?? 'Choose a PIN'),
                textAlign: TextAlign.center,
                style: SpendWiseType.lead,
              ),
            ),
            const SizedBox(height: 22),
            ShakeBox(
              animation: shake,
              child: PinDots(
                length: length,
                filled: entry.length,
                error: problem != null,
                muted: busy,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 34,
              child: problem != null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SpendWiseTheme.gutter,
                      ),
                      child: Text(
                        problem!,
                        textAlign: TextAlign.center,
                        style: SpendWiseType.body.copyWith(
                          fontSize: 12.5,
                          color: SpendWiseColors.spend,
                        ),
                      ),
                    )
                  : canChooseLength
                  ? _LengthChoice(
                      length: length,
                      onChanged: (value) => setState(() {
                        length = value;
                        entry = '';
                      }),
                    )
                  : const SizedBox.shrink(),
            ),
            const Spacer(flex: 2),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Four digits or six. Not a free-form field: every extra option here is one
/// more thing to decide before the app has done anything for you yet.
class _LengthChoice extends StatelessWidget {
  const _LengthChoice({required this.length, required this.onChanged});

  final int length;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (final option in const [4, 6])
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: InkWell(
            onTap: option == length ? null : () => onChanged(option),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                border: Border.all(
                  color: option == length
                      ? SpendWiseColors.fg
                      : SpendWiseColors.edge,
                ),
              ),
              child: Text(
                '$option digits',
                style: SpendWiseType.body.copyWith(
                  fontSize: 12,
                  color: option == length
                      ? SpendWiseColors.fg
                      : SpendWiseColors.dim,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
