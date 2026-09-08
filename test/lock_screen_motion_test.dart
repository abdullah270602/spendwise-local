import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/security/lock_screen.dart';
import 'package:spendwise/features/security/pin_pad.dart';
import 'package:spendwise/security/app_lock.dart';
import 'package:spendwise/security/pin_codec.dart';

/// A wrong PIN answers in four ways at once: a haptic, the dots turning, a
/// line of text, and a shake. Only the shake is purely movement, and it was
/// the one part that ran whatever the platform's reduced-motion flag said.
///
/// The test that matters is not that the shake stops -- it is that the
/// refusal is still unmistakable once it has. An animation that was carrying
/// the message on its own cannot simply be switched off.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppLockController controller() => AppLockController(
    preferences: MapLockPreferences({
      AppLockController.pinKey: PinHash.create(
        '4821',
        iterations: 200,
      ).encode(),
      AppLockController.lengthKey: '4',
    }),
  );

  Future<AppLockController> pump(
    WidgetTester tester, {
    required bool reduceMotion,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lock = controller();
    addTearDown(lock.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: MaterialApp(
          theme: SpendWiseTheme.dark,
          home: LockScreen(lock: lock),
        ),
      ),
    );
    await tester.pump();
    return lock;
  }

  /// Types a PIN that is not the stored one and stops partway through the
  /// jolt, which is the only moment the dots are displaced.
  Future<void> guessWrong(WidgetTester tester) async {
    for (final digit in '1111'.split('')) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    // The PIN is checked on a real isolate, deliberately, so that the
    // stretching never freezes the keypad. Nothing a widget test's fake
    // clock does will resolve that -- real time has to pass first.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    // Far enough into the 420ms jolt to be displaced, not far enough to have
    // settled back to where it started.
    await tester.pump(const Duration(milliseconds: 80));
  }

  /// Drains the pause the screen holds before clearing the entry, so the test
  /// does not end with a live timer.
  Future<void> settle(WidgetTester tester) =>
      tester.pumpAndSettle(const Duration(milliseconds: 100));

  double dotsX(WidgetTester tester) =>
      tester.getTopLeft(find.byType(PinDots)).dx;

  testWidgets('the dots jolt when a PIN is refused', (tester) async {
    await pump(tester, reduceMotion: false);
    final atRest = dotsX(tester);
    await guessWrong(tester);
    expect(
      dotsX(tester),
      isNot(closeTo(atRest, 0.5)),
      reason: 'the shake is what this test is measuring the absence of later',
    );
    await settle(tester);
  });

  testWidgets('and hold still when motion is turned off', (tester) async {
    await pump(tester, reduceMotion: true);
    final atRest = dotsX(tester);
    await guessWrong(tester);
    expect(dotsX(tester), closeTo(atRest, 0.01));
    await settle(tester);
  });

  testWidgets('but the refusal is still said in words', (tester) async {
    // Removing the movement must not remove the message. The line under the
    // dots is the part a person actually reads, and it has to survive.
    await pump(tester, reduceMotion: true);
    await guessWrong(tester);
    expect(find.textContaining('Wrong PIN'), findsOneWidget);
    await settle(tester);
  });
}
