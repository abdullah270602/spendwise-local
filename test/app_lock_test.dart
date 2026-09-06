import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/security/app_lock.dart';
import 'package:spendwise/security/pin_codec.dart';

/// The lock is the one screen a person cannot work around, so the parts that
/// decide "yes", "no" and "wait" are pinned down here rather than trusted to
/// a walk through the UI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hashing a PIN', () {
    test('the right digits verify and the wrong ones do not', () {
      final hash = PinHash.create('4821', iterations: 1000);
      expect(hash.matches('4821'), isTrue);
      expect(hash.matches('4822'), isFalse);
      expect(hash.matches('482'), isFalse);
    });

    test('the same PIN twice produces different stored bytes', () {
      // Otherwise two people with the same PIN share a hash, and one leaked
      // rainbow table covers every install.
      final a = PinHash.create('4821', iterations: 1000);
      final b = PinHash.create('4821', iterations: 1000);
      expect(a.key, isNot(b.key));
      expect(a.salt, isNot(b.salt));
    });

    test('it survives a round trip through storage', () {
      final hash = PinHash.create('482173', iterations: 1000);
      final restored = PinHash.decode(hash.encode())!;
      expect(restored.iterations, 1000);
      expect(restored.matches('482173'), isTrue);
      expect(restored.matches('482174'), isFalse);
    });

    test('the cost travels with the hash', () {
      // So raising the default later re-checks an old PIN at its own cost
      // instead of locking someone out of their own ledger.
      final hash = PinHash.create('4821', iterations: 1500);
      expect(PinHash.decode(hash.encode())!.iterations, 1500);
    });

    test('anything unreadable decodes to nothing rather than to a match', () {
      expect(PinHash.decode(null), isNull);
      expect(PinHash.decode(''), isNull);
      expect(PinHash.decode('4821'), isNull);
      expect(PinHash.decode('bcrypt:1:aa:bb'), isNull);
      expect(PinHash.decode('pbkdf2-sha256:0:aa:bb'), isNull);
      expect(PinHash.decode('pbkdf2-sha256:1000:not base64:!!'), isNull);
    });

    test('it matches the RFC 6070 style vector for PBKDF2-HMAC-SHA256', () {
      // Password "password", salt "salt", one round: the published answer
      // starts 120fb6cf. A home-rolled derivation that nobody checked against
      // a known vector is just an expensive random number generator.
      final key = pbkdf2(
        password: 'password'.codeUnits,
        salt: 'salt'.codeUnits,
        iterations: 1,
        length: 32,
      );
      expect(
        key.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        '120fb6cf',
      );
    });
  });

  group('the lockout', () {
    test('the first few wrong guesses cost nothing', () {
      for (var i = 0; i <= AppLockController.freeAttempts; i++) {
        expect(AppLockController.penaltyFor(i), Duration.zero, reason: '$i');
      }
    });

    test('after that each guess costs more', () {
      expect(AppLockController.penaltyFor(5), const Duration(seconds: 30));
      expect(AppLockController.penaltyFor(6), const Duration(minutes: 1));
      expect(AppLockController.penaltyFor(7), const Duration(minutes: 5));
      expect(AppLockController.penaltyFor(8), const Duration(minutes: 15));
      expect(AppLockController.penaltyFor(40), const Duration(minutes: 30));
    });

    test('it counts down, and a wrong guess restarts it', () async {
      var clock = DateTime(2026, 9, 6, 12);
      final lock = AppLockController(
        preferences: MapLockPreferences({
          AppLockController.pinKey: PinHash.create(
            '4821',
            iterations: 200,
          ).encode(),
          AppLockController.lengthKey: '4',
          AppLockController.failuresKey: '5',
          AppLockController.failedAtKey: '${clock.millisecondsSinceEpoch}',
        }),
        now: () => clock,
      );

      expect(lock.lockoutRemaining, const Duration(seconds: 30));
      clock = clock.add(const Duration(seconds: 20));
      expect(lock.lockoutRemaining, const Duration(seconds: 10));

      // The right PIN is still refused while the wait is running, or the wait
      // would only be costing an attacker one extra keystroke.
      expect(await lock.submit('4821'), UnlockOutcome.lockedOut);

      clock = clock.add(const Duration(seconds: 11));
      expect(lock.lockoutRemaining, Duration.zero);
      expect(await lock.submit('4821'), UnlockOutcome.unlocked);
    });

    test('a wrong guess is remembered across a restart', () async {
      final storage = MapLockPreferences({
        AppLockController.pinKey: PinHash.create(
          '4821',
          iterations: 200,
        ).encode(),
        AppLockController.lengthKey: '4',
      });
      var clock = DateTime(2026, 9, 6, 12);
      final first = AppLockController(preferences: storage, now: () => clock);
      for (var i = 0; i < 5; i++) {
        expect(await first.submit('0000'), UnlockOutcome.wrong);
      }

      // Killing the app must not buy a fresh set of free guesses.
      final second = AppLockController(preferences: storage, now: () => clock);
      expect(second.failures, 5);
      expect(second.lockoutRemaining, const Duration(seconds: 30));
      expect(second.locked, isTrue);
    });

    test('winding the clock back does not shorten the wait', () {
      var clock = DateTime(2026, 9, 6, 12);
      final lock = AppLockController(
        preferences: MapLockPreferences({
          AppLockController.pinKey: 'pbkdf2-sha256:1:AA==:AA==',
          AppLockController.failuresKey: '6',
          AppLockController.failedAtKey: '${clock.millisecondsSinceEpoch}',
        }),
        now: () => clock,
      );
      clock = clock.subtract(const Duration(days: 1));
      expect(lock.lockoutRemaining, const Duration(minutes: 1));
    });

    test('unlocking clears the tally', () async {
      final lock = AppLockController(
        preferences: MapLockPreferences({
          AppLockController.pinKey: PinHash.create(
            '4821',
            iterations: 200,
          ).encode(),
        }),
      );
      expect(await lock.submit('0000'), UnlockOutcome.wrong);
      expect(lock.failures, 1);
      expect(await lock.submit('4821'), UnlockOutcome.unlocked);
      expect(lock.failures, 0);
    });
  });

  group('turning it on and off', () {
    test('an app with no PIN set is not locked', () {
      final lock = AppLockController(preferences: MapLockPreferences());
      expect(lock.enabled, isFalse);
      expect(lock.locked, isFalse);
      lock.lockNow();
      expect(lock.locked, isFalse);
    });

    test('setting a PIN stores its length and leaves the app open', () async {
      final storage = MapLockPreferences();
      final lock = AppLockController(preferences: storage);
      await lock.enable('482173');
      expect(lock.enabled, isTrue);
      expect(lock.pinLength, 6);
      expect(lock.locked, isFalse, reason: 'you just proved you know it');
      expect(storage.read(AppLockController.pinKey), startsWith('pbkdf2-'));
      expect(
        storage.read(AppLockController.pinKey),
        isNot(contains('482173')),
        reason: 'the digits themselves must never be written down',
      );
    });

    test('a fresh start with a PIN set opens locked', () async {
      final storage = MapLockPreferences();
      await AppLockController(preferences: storage).enable('4821');
      expect(AppLockController(preferences: storage).locked, isTrue);
    });

    test('turning it off blanks the stored PIN', () async {
      final storage = MapLockPreferences();
      final lock = AppLockController(preferences: storage);
      await lock.enable('4821');
      await lock.disable();
      expect(lock.enabled, isFalse);
      expect(lock.locked, isFalse);
      // Blank, not merely falsy: the ledger key/value store has no delete.
      expect(storage.read(AppLockController.pinKey), isEmpty);
    });

    test('verifying does not unlock', () async {
      final storage = MapLockPreferences();
      await AppLockController(preferences: storage).enable('4821');
      final lock = AppLockController(preferences: storage);
      expect(lock.locked, isTrue);
      expect(await lock.verify('4821'), isTrue);
      expect(await lock.verify('0000'), isFalse);
      expect(lock.locked, isTrue, reason: 'verify is for settings, not entry');
    });
  });

  _scopeReach();
  _corruptPin();

  group('when it decides to re-lock', () {
    // An app that has just been opened and unlocked, which is the only state
    // from which re-locking is a question at all.
    Future<AppLockController> open(
      LockDelay delay,
      DateTime Function() now,
    ) async {
      final storage = MapLockPreferences({
        AppLockController.pinKey: PinHash.create(
          '4821',
          iterations: 200,
        ).encode(),
        AppLockController.delayKey: delay.storageKey,
      });
      final lock = AppLockController(preferences: storage, now: now);
      expect(await lock.submit('4821'), UnlockOutcome.unlocked);
      return lock;
    }

    test('a shade pull or a permission dialog does not lock it', () async {
      final lock = await open(LockDelay.immediately, DateTime.now);
      lock.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(
        lock.locked,
        isFalse,
        reason: 'inactive fires for a call banner; locking on it feels broken',
      );
    });

    test('leaving locks immediately when that is the choice', () async {
      final lock = await open(LockDelay.immediately, DateTime.now);
      lock.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(lock.locked, isTrue);
    });

    test('a quick glance elsewhere is forgiven', () async {
      var clock = DateTime(2026, 9, 6, 12);
      final lock = await open(LockDelay.oneMinute, () => clock);
      lock.didChangeAppLifecycleState(AppLifecycleState.paused);
      clock = clock.add(const Duration(seconds: 20));
      lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(lock.locked, isFalse);
    });

    test('a real gap is not', () async {
      var clock = DateTime(2026, 9, 6, 12);
      final lock = await open(LockDelay.oneMinute, () => clock);
      lock.didChangeAppLifecycleState(AppLifecycleState.paused);
      clock = clock.add(const Duration(minutes: 3));
      lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(lock.locked, isTrue);
    });

    test('the delay round-trips through storage, and junk means a minute', () {
      for (final delay in LockDelay.values) {
        expect(LockDelayCopy.decode(delay.storageKey), delay);
      }
      expect(LockDelayCopy.decode(null), LockDelay.oneMinute);
      expect(LockDelayCopy.decode('wat'), LockDelay.oneMinute);
    });
  });
}

/// A pushed route is a sibling of `home` under the app's Navigator, not a
/// descendant of it. A scope placed inside `home` is therefore invisible to
/// every screen the user navigates to -- which is all of them, including the
/// settings screen that turns the lock on. It has to wrap MaterialApp.
void _scopeReach() {
  testWidgets('a pushed route can still reach the lock', (tester) async {
    final lock = AppLockController(preferences: MapLockPreferences());
    await tester.pumpWidget(
      AppLockScope(
        lock: lock,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (routeContext) => Text(
                    AppLockScope.maybeOf(routeContext) == null
                        ? 'unreachable'
                        : 'reachable',
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('reachable'), findsOneWidget);
  });
}

/// A stored PIN that cannot be decoded is the one state where a lock can fail
/// in either direction: refuse its owner forever, or open for anybody. It has
/// to read as "off" -- true, visible in Settings, and fixable.
void _corruptPin() {
  group('an unreadable stored PIN', () {
    for (final junk in ['x', 'pbkdf2-sha256:oops', 'pbkdf2-sha256:1:!!:!!']) {
      test('"$junk" leaves the lock off rather than open', () async {
        final lock = AppLockController(
          preferences: MapLockPreferences({AppLockController.pinKey: junk}),
        );
        expect(lock.enabled, isFalse);
        expect(lock.locked, isFalse, reason: 'no keypad it cannot verify');
        lock.lockNow();
        expect(lock.locked, isFalse);
      });
    }

    test('a good PIN still works after one has been repaired', () async {
      final storage = MapLockPreferences({AppLockController.pinKey: 'junk'});
      final lock = AppLockController(preferences: storage);
      expect(lock.enabled, isFalse);
      await lock.enable('4821');
      expect(lock.enabled, isTrue);
      expect(await lock.submit('0000'), UnlockOutcome.wrong);
      expect(await lock.submit('4821'), UnlockOutcome.unlocked);
    });
  });
}
