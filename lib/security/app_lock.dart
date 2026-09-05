import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';

import 'pin_codec.dart';

/// How long the app may sit in the background before it asks again.
///
/// Locking the instant a person taps away sounds strictest, but it punishes
/// the exact move this app invites: hopping to the SMS app to check the alert
/// you are filing. So the delay is theirs to set, and the honest default is a
/// minute -- long enough to glance at something else, short enough that a
/// phone left on a table re-locks before anyone picks it up.
enum LockDelay { immediately, oneMinute, fiveMinutes }

extension LockDelayCopy on LockDelay {
  Duration get duration => switch (this) {
    LockDelay.immediately => Duration.zero,
    LockDelay.oneMinute => const Duration(minutes: 1),
    LockDelay.fiveMinutes => const Duration(minutes: 5),
  };

  String get title => switch (this) {
    LockDelay.immediately => 'Immediately',
    LockDelay.oneMinute => 'After a minute',
    LockDelay.fiveMinutes => 'After five minutes',
  };

  String get blurb => switch (this) {
    LockDelay.immediately => 'Every time you leave the app.',
    LockDelay.oneMinute => 'Check your messages and come back unasked.',
    LockDelay.fiveMinutes => 'Only after a real gap.',
  };

  String get storageKey => switch (this) {
    LockDelay.immediately => '0',
    LockDelay.oneMinute => '60',
    LockDelay.fiveMinutes => '300',
  };

  static LockDelay decode(String? value) => switch (value) {
    '0' => LockDelay.immediately,
    '300' => LockDelay.fiveMinutes,
    _ => LockDelay.oneMinute,
  };
}

/// Where the lock keeps its few facts: the encrypted ledger in the app, a
/// plain map in tests.
abstract class LockPreferences {
  String? read(String key);
  void write(String key, String value);
}

class MapLockPreferences implements LockPreferences {
  MapLockPreferences([Map<String, String>? seed]) : _values = {...?seed};

  final Map<String, String> _values;

  @override
  String? read(String key) => _values[key];

  @override
  void write(String key, String value) => _values[key] = value;
}

/// The result of offering a PIN.
enum UnlockOutcome { unlocked, wrong, lockedOut }

/// The gate in front of the ledger.
///
/// Deliberately not wired to the database key. Deriving the SQLCipher key from
/// the PIN would sound stronger and be much worse: notification capture runs
/// while the app is locked and needs to write, and a forgotten PIN would mean
/// a permanently unreadable ledger rather than an inconvenience. The key stays
/// with the Android keystore; this decides who gets to look.
class AppLockController extends ChangeNotifier with WidgetsBindingObserver {
  AppLockController({
    required LockPreferences preferences,
    LocalAuthentication? auth,
    this.now = DateTime.now,
  }) : _prefs = preferences,
       _auth = auth ?? LocalAuthentication() {
    _locked = enabled;
  }

  static const pinKey = 'lock_pin';
  static const lengthKey = 'lock_pin_length';
  static const biometricsKey = 'lock_biometrics';
  static const delayKey = 'lock_after_seconds';
  static const failuresKey = 'lock_failures';
  static const failedAtKey = 'lock_failed_at';
  static const privacyKey = 'lock_hide_in_switcher';

  /// Wrong guesses allowed before the wait starts.
  static const freeAttempts = 4;

  static const _channel = MethodChannel('com.spendwise.app/notifications');

  final LockPreferences _prefs;
  final LocalAuthentication _auth;
  final DateTime Function() now;

  bool _locked = false;
  bool _biometricsAvailable = false;
  bool _authInProgress = false;
  DateTime? _leftAt;

  /// Blank counts as unset: the ledger key/value store has no delete, so
  /// turning the lock off writes an empty string.
  bool get enabled => (_prefs.read(pinKey) ?? '').isNotEmpty;
  bool get locked => _locked && enabled;
  bool get biometricsEnabled =>
      enabled && _biometricsAvailable && _prefs.read(biometricsKey) == 'true';
  bool get biometricsAvailable => _biometricsAvailable;
  bool get hideInSwitcher => _prefs.read(privacyKey) == 'true';
  LockDelay get delay => LockDelayCopy.decode(_prefs.read(delayKey));
  int get failures => int.tryParse(_prefs.read(failuresKey) ?? '') ?? 0;

  /// How many digits this person chose. Kept so the keypad can draw the right
  /// number of slots and submit on the last one, instead of making everyone
  /// press an extra confirm key. The dots reveal the length anyway, so storing
  /// it gives nothing away.
  static const minPinLength = 4;
  static const maxPinLength = 8;
  int get pinLength =>
      int.tryParse(_prefs.read(lengthKey) ?? '')?.clamp(
        minPinLength,
        maxPinLength,
      ) ??
      minPinLength;

  /// Ask the platform what it actually has, once, at startup. A device with no
  /// enrolled fingerprint must not be offered the option at all: a button that
  /// always fails is worse than no button.
  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    await refreshBiometricSupport();
    await applyScreenPrivacy();
  }

  Future<void> refreshBiometricSupport() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final enrolled = supported
          ? (await _auth.getAvailableBiometrics()).isNotEmpty
          : false;
      if (_biometricsAvailable == enrolled) return;
      _biometricsAvailable = enrolled;
      notifyListeners();
    } on PlatformException {
      _biometricsAvailable = false;
    } on MissingPluginException {
      _biometricsAvailable = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ---- Setup ------------------------------------------------------------

  Future<void> enable(String pin, {bool useBiometrics = false}) async {
    final hash = await Isolate.run(() => PinHash.create(pin).encode());
    _prefs.write(pinKey, hash);
    _prefs.write(lengthKey, '${pin.length}');
    _prefs.write(biometricsKey, useBiometrics ? 'true' : 'false');
    _clearFailures();
    _locked = false;
    notifyListeners();
    await applyScreenPrivacy();
  }

  Future<void> disable() async {
    _prefs.write(pinKey, '');
    _prefs.write(biometricsKey, 'false');
    _clearFailures();
    _locked = false;
    notifyListeners();
    await applyScreenPrivacy();
  }

  void setBiometricsEnabled(bool value) {
    _prefs.write(biometricsKey, value ? 'true' : 'false');
    notifyListeners();
  }

  void setDelay(LockDelay value) {
    _prefs.write(delayKey, value.storageKey);
    notifyListeners();
  }

  Future<void> setHideInSwitcher(bool value) async {
    _prefs.write(privacyKey, value ? 'true' : 'false');
    notifyListeners();
    await applyScreenPrivacy();
  }

  // ---- Unlocking --------------------------------------------------------

  void lockNow() {
    if (!enabled || _locked) return;
    _locked = true;
    notifyListeners();
  }

  /// How long is left before another guess is accepted.
  Duration get lockoutRemaining {
    final penalty = penaltyFor(failures);
    if (penalty == Duration.zero) return Duration.zero;
    final stampedAt = int.tryParse(_prefs.read(failedAtKey) ?? '');
    if (stampedAt == null || stampedAt == 0) return Duration.zero;
    final failedAt = DateTime.fromMillisecondsSinceEpoch(stampedAt);
    final current = now();
    // A clock moved backwards must not shorten the wait, so a stamp in the
    // future is treated as if the last wrong guess had just happened.
    if (current.isBefore(failedAt)) return penalty;
    final elapsed = current.difference(failedAt);
    return elapsed >= penalty ? Duration.zero : penalty - elapsed;
  }

  /// Wrong guesses cost nothing for a few tries, then cost time. The count is
  /// stored, so killing the app does not buy a fresh set.
  static Duration penaltyFor(int failures) {
    if (failures <= freeAttempts) return Duration.zero;
    return switch (failures - freeAttempts) {
      1 => const Duration(seconds: 30),
      2 => const Duration(minutes: 1),
      3 => const Duration(minutes: 5),
      4 => const Duration(minutes: 15),
      _ => const Duration(minutes: 30),
    };
  }

  Future<UnlockOutcome> submit(String pin) async {
    if (lockoutRemaining > Duration.zero) return UnlockOutcome.lockedOut;
    final stored = PinHash.decode(_prefs.read(pinKey));
    if (stored == null) {
      _locked = false;
      notifyListeners();
      return UnlockOutcome.unlocked;
    }
    // Off the main isolate: the stretching is deliberately expensive, and a
    // frozen keypad is how a lock screen earns a reputation for being slow
    // even when it is fast.
    final ok = await Isolate.run(() => stored.matches(pin));
    if (!ok) {
      _prefs.write(failuresKey, '${failures + 1}');
      _prefs.write(failedAtKey, '${now().millisecondsSinceEpoch}');
      notifyListeners();
      return UnlockOutcome.wrong;
    }
    _clearFailures();
    _locked = false;
    notifyListeners();
    return UnlockOutcome.unlocked;
  }

  /// Checks a PIN without unlocking, for changing or removing it.
  Future<bool> verify(String pin) async {
    final stored = PinHash.decode(_prefs.read(pinKey));
    if (stored == null) return false;
    return Isolate.run(() => stored.matches(pin));
  }

  Future<bool> tryBiometrics() async {
    if (!biometricsEnabled || _authInProgress) return false;
    if (lockoutRemaining > Duration.zero) return false;
    _authInProgress = true;
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock SpendWise',
        // The system sheet backgrounds the app on some devices; without this
        // the lifecycle handler and the sheet fight, and the sheet dies the
        // moment it appears.
        persistAcrossBackgrounding: true,
        biometricOnly: true,
      );
      if (ok) {
        _clearFailures();
        _locked = false;
        notifyListeners();
      }
      return ok;
    } on PlatformException {
      return false;
    } finally {
      // A beat of grace: the lifecycle events from dismissing the system sheet
      // arrive after this future completes.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      _authInProgress = false;
      _leftAt = null;
    }
  }

  void _clearFailures() {
    _prefs.write(failuresKey, '0');
    _prefs.write(failedAtKey, '0');
  }

  // ---- Lifecycle --------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!enabled || _authInProgress) return;
    switch (state) {
      // `inactive` is not backgrounding: it fires for a notification shade
      // pull, a permission dialog, even a call banner. Locking on it makes the
      // app feel broken.
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _leftAt = now();
        if (delay == LockDelay.immediately) lockNow();
      case AppLifecycleState.resumed:
        final left = _leftAt;
        _leftAt = null;
        if (left == null) return;
        if (now().difference(left) >= delay.duration) lockNow();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Blanks the window in the app switcher and blocks screenshots while the
  /// lock is on. Without it the lock is a door with a window beside it: the
  /// task switcher still shows the last frame of the ledger.
  Future<void> applyScreenPrivacy() async {
    try {
      await _channel.invokeMethod<void>('setScreenPrivacy', {
        'enabled': enabled && hideInSwitcher,
      });
    } on PlatformException {
      // The lock still works; only the switcher preview does not.
    } on MissingPluginException {
      // Tests and non-Android hosts.
    }
  }
}

/// Reaches the lock from anywhere without threading it through Home and the
/// shell, neither of which has any business knowing about it.
class AppLockScope extends InheritedWidget {
  const AppLockScope({
    super.key,
    required this.lock,
    required super.child,
  });

  final AppLockController lock;

  static AppLockController of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppLockScope>()!
      .lock;

  static AppLockController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppLockScope>()
      ?.lock;

  @override
  bool updateShouldNotify(AppLockScope oldWidget) => oldWidget.lock != lock;
}
