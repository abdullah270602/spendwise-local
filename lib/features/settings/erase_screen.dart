import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/failure_text.dart';
import '../../app/theme.dart';
import '../../security/app_lock.dart';
import '../../widgets/shape_kit.dart';
import '../shell/spendwise_view_model.dart';

/// Erasing everything, made hard to do by accident.
///
/// This was a dialog with a Cancel and an Erase button: two taps from the
/// settings list to permanent, unrecoverable loss, with nothing in the way but
/// a sentence you could skim. There is no backup, no cloud copy and no export
/// unless the person happened to take one, so a mis-tap here is the worst
/// thing the app can do to somebody.
///
/// It is now four gates, and each one is there for a different reason:
///
///  * The PIN proves it is the owner, not somebody holding the phone. It is
///    deliberately PIN-only with no fingerprint path -- everywhere else in the
///    app a fingerprint is the convenient route, but a finger can be used on
///    someone asleep or unwilling, and a PIN has to be known.
///  * Typing the word cannot be done by brushing the screen.
///  * The countdown is the one that actually saves people, because regret
///    arrives a second after the decision, not before it.
///  * A full screen rather than a dialog, because a dialog dismisses when you
///    tap beside it, and this should not be a thing you can half-do.
///
/// Leaving the screen or closing the app during the countdown cancels it.
/// Resuming a pending destroy on next launch would take the data of somebody
/// who had already changed their mind, and it makes "close the app" a third
/// way out.
class EraseScreen extends StatefulWidget {
  const EraseScreen({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<EraseScreen> createState() => _EraseScreenState();
}

enum _Stage { pin, confirm, countdown, erasing }

class _EraseScreenState extends State<EraseScreen> {
  /// Short, unambiguous, and not a word anybody types by accident.
  static const _word = 'ERASE';

  /// Long enough for the decision to be reconsidered, short enough that
  /// somebody who means it is not left staring at a wall.
  static const _grace = Duration(seconds: 30);

  final _pin = TextEditingController();
  final _typed = TextEditingController();

  late _Stage _stage;
  String? _pinError;
  Timer? _ticker;
  Duration _left = _grace;

  AppLockController? get _lock => AppLockScope.maybeOf(context);

  @override
  void initState() {
    super.initState();
    // Resolved in didChangeDependencies, where the scope is readable.
    _stage = _Stage.pin;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stage == _Stage.pin && !(_lock?.enabled ?? false)) {
      _stage = _Stage.confirm;
    }
  }

  @override
  void dispose() {
    // The countdown does not outlive the screen. This is what makes leaving
    // an escape hatch rather than a delay.
    _ticker?.cancel();
    _pin.dispose();
    _typed.dispose();
    super.dispose();
  }

  Future<void> _checkPin() async {
    final lock = _lock;
    if (lock == null) return;
    final ok = await lock.verify(_pin.text);
    if (!mounted) return;
    setState(() {
      if (ok) {
        _stage = _Stage.confirm;
        _pinError = null;
      } else {
        _pinError = 'That is not the PIN.';
      }
      _pin.clear();
    });
  }

  void _begin() {
    HapticFeedback.heavyImpact();
    setState(() {
      _stage = _Stage.countdown;
      _left = _grace;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final left = _left - const Duration(seconds: 1);
      if (left <= Duration.zero) {
        timer.cancel();
        _erase();
      } else {
        setState(() => _left = left);
      }
    });
  }

  void _stop() {
    _ticker?.cancel();
    _ticker = null;
    setState(() {
      _stage = _Stage.confirm;
      _left = _grace;
      _typed.clear();
    });
  }

  Future<void> _erase() async {
    setState(() => _stage = _Stage.erasing);
    try {
      await widget.viewModel.eraseAllData();
      // Popping with a result rather than bare: the screen that destroyed
      // everything closes, and the list behind it looks exactly as it did
      // before, so the biggest action in the app was the only one that said
      // nothing about itself. The caller reports it.
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _stage = _Stage.confirm);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failureText('Could not erase data', error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // Backing out is allowed at every stage, and cancels. The only thing that
    // must not be interrupted is the erase itself, which is over in a moment.
    canPop: _stage != _Stage.erasing,
    child: Scaffold(
      appBar: AppBar(title: const Text('Erase all local data')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          SpendWiseTheme.gutter,
          20,
          SpendWiseTheme.gutter,
          32 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: switch (_stage) {
          _Stage.pin => _pinGate(),
          _Stage.confirm => _confirmGate(),
          _Stage.countdown || _Stage.erasing => _countdown(),
        },
      ),
    ),
  );

  List<Widget> _pinGate() => [
    const Eyebrow('First, your PIN'),
    const SizedBox(height: 12),
    Text(
      'Erasing cannot be undone once it runs, so it asks for the PIN rather '
      'than a fingerprint. A fingerprint can be used on somebody who is '
      'asleep or unwilling.',
      style: SpendWiseType.body.copyWith(fontSize: 13),
    ),
    const SizedBox(height: 20),
    TextField(
      controller: _pin,
      autofocus: true,
      obscureText: true,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: 'PIN', errorText: _pinError),
      onSubmitted: (_) => _checkPin(),
    ),
    const SizedBox(height: 18),
    PrimaryAction(label: 'Continue', onPressed: _checkPin),
  ];

  List<Widget> _confirmGate() => [
    const Eyebrow('What goes'),
    const SizedBox(height: 12),
    Text(
      'Every account, every transaction, every alert kept as evidence, the '
      'categories you taught it, the debts you recorded and every setting.',
      style: SpendWiseType.body.copyWith(fontSize: 13),
    ),
    const SizedBox(height: 12),
    Text(
      'There is no backup and no copy anywhere else. Nothing about this app '
      'has ever left the phone, which is the point of it, and it is also why '
      'nobody can get this back for you.',
      style: SpendWiseType.body.copyWith(
        fontSize: 13,
        color: SpendWiseColors.spend,
      ),
    ),
    const SizedBox(height: 24),
    const Eyebrow('Type $_word to continue'),
    const SizedBox(height: 10),
    TextField(
      controller: _typed,
      autofocus: true,
      autocorrect: false,
      textCapitalization: TextCapitalization.characters,
      decoration: const InputDecoration(hintText: _word),
      onChanged: (_) => setState(() {}),
    ),
    const SizedBox(height: 18),
    PrimaryAction(
      label: 'Erase everything',
      onPressed: _typed.text.trim().toUpperCase() == _word ? _begin : null,
    ),
  ];

  List<Widget> _countdown() {
    final erasing = _stage == _Stage.erasing;
    return [
      const Eyebrow('Erasing in'),
      const SizedBox(height: 14),
      Text(
        erasing ? 'now' : '${_left.inSeconds}',
        style: SpendWiseType.statement.copyWith(
          fontSize: 64,
          color: SpendWiseColors.spend,
        ),
      ),
      const SizedBox(height: 14),
      Text(
        erasing
            ? 'Removing everything from this device.'
            : 'Nothing has been deleted yet. Stopping now, leaving this '
                  'screen, or closing the app all cancel it.',
        style: SpendWiseType.body.copyWith(fontSize: 13),
      ),
      const SizedBox(height: 26),
      if (!erasing)
        PrimaryAction(label: 'Stop, keep my data', onPressed: _stop),
    ];
  }
}
