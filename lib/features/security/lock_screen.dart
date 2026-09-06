import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../security/app_lock.dart';
import '../../widgets/spendwise_components.dart';
import 'pin_pad.dart';

/// The screen in front of everything.
///
/// It shows nothing about the ledger: no balance, no last transaction, no
/// count of anything. A lock screen that previews what it is protecting is
/// only theatre, and this app's whole claim is that the contents are yours.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.lock});

  final AppLockController lock;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen>
    with SingleTickerProviderStateMixin {
  String entry = '';
  bool checking = false;
  bool wrong = false;
  Timer? countdown;
  late final AnimationController shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  AppLockController get lock => widget.lock;

  @override
  void initState() {
    super.initState();
    // Offer the finger before the keypad: for anyone with biometrics on, the
    // fastest unlock is the one they never had to ask for.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && lock.biometricsEnabled) unawaited(lock.tryBiometrics());
    });
    _armCountdown();
  }

  @override
  void dispose() {
    countdown?.cancel();
    shake.dispose();
    super.dispose();
  }

  /// Only ticks while a wait is actually running, so a locked phone is not
  /// rebuilding a screen once a second forever.
  void _armCountdown() {
    countdown?.cancel();
    if (lock.lockoutRemaining == Duration.zero) return;
    countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() {});
      if (lock.lockoutRemaining == Duration.zero) timer.cancel();
    });
  }

  void _press(String digit) {
    if (checking || lock.lockoutRemaining > Duration.zero) return;
    if (entry.length >= lock.pinLength) return;
    setState(() {
      entry += digit;
      wrong = false;
    });
    if (entry.length == lock.pinLength) unawaited(_submit());
  }

  void _backspace() {
    if (checking || entry.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      entry = entry.substring(0, entry.length - 1);
      wrong = false;
    });
  }

  Future<void> _submit() async {
    setState(() => checking = true);
    final outcome = await lock.submit(entry);
    if (!mounted) return;
    switch (outcome) {
      case UnlockOutcome.unlocked:
        // The gate above swaps this screen out; clearing state here would
        // only repaint a screen on its way off.
        break;
      case UnlockOutcome.wrong:
      case UnlockOutcome.lockedOut:
        HapticFeedback.heavyImpact();
        setState(() {
          checking = false;
          wrong = true;
        });
        shake.forward(from: 0);
        _armCountdown();
        await Future<void>.delayed(const Duration(milliseconds: 420));
        if (mounted) setState(() => entry = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final waiting = lock.lockoutRemaining;
    final lockedOut = waiting > Duration.zero;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      // No back gesture, no app bar, nothing to dismiss.
      body: PopScope(
        canPop: false,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const Spacer(flex: 3),
              const SpendWiseMark(size: 46),
              const SizedBox(height: 16),
              Text('SpendWise', style: SpendWiseType.title),
              const SizedBox(height: 6),
              Text(
                lockedOut ? 'Too many attempts' : 'Locked',
                style: SpendWiseType.eyebrow,
              ),
              const Spacer(flex: 2),
              ShakeBox(
                animation: shake,
                child: PinDots(
                  length: lock.pinLength,
                  filled: entry.length,
                  error: wrong,
                  muted: checking,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 20,
                child: Text(
                  _statusLine(waiting),
                  textAlign: TextAlign.center,
                  style: SpendWiseType.body.copyWith(
                    fontSize: 12.5,
                    color: wrong || lockedOut
                        ? SpendWiseColors.spend
                        : SpendWiseColors.dim,
                  ),
                ),
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
                  enabled: !checking && !lockedOut,
                  onDigit: _press,
                  onBackspace: _backspace,
                  leading: lock.biometricsEnabled && !lockedOut
                      ? PinPadAction(
                          icon: Icons.fingerprint_rounded,
                          label: 'Unlock with your fingerprint',
                          onTap: () => unawaited(lock.tryBiometrics()),
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLine(Duration waiting) {
    if (waiting > Duration.zero) return 'Try again in ${_spell(waiting)}';
    if (wrong) {
      final left = AppLockController.freeAttempts - lock.failures;
      if (left <= 0) return 'Wrong PIN';
      return left == 1
          ? 'Wrong PIN. One more try before a wait.'
          : 'Wrong PIN. $left tries before a wait.';
    }
    if (checking) return 'Checking';
    return lock.biometricsEnabled
        ? 'Enter your PIN, or use your fingerprint'
        : '';
  }

  static String _spell(Duration value) {
    final seconds = value.inSeconds + 1;
    if (seconds < 60) return '${seconds}s';
    final minutes = (seconds / 60).ceil();
    return minutes == 1 ? 'a minute' : '$minutes minutes';
  }
}
