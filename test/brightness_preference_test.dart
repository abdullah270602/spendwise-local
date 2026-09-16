import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/brightness_choice.dart';
import 'package:spendwise/app/ground.dart';
import 'package:spendwise/app/palette.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/settings/brightness_screen.dart';

import 'light_mode_fixture.dart';

/// Four ways a light mode can look like it works and not work.
///
/// It can forget the choice when the app is closed, which is the difference
/// between a setting and a toggle. It can arrive on a fresh install already
/// overriding something nobody asked it to override. It can read the phone's
/// theme once at launch and then ignore the phone for the rest of the day,
/// which is exactly the case a person sees at dusk and cannot describe. And
/// it can follow the phone even after being told not to, which makes the
/// override the one thing in the app that does not stick.
///
/// Every one of those is invisible in a screenshot and obvious after ten
/// minutes of use, so none of them is caught by looking at the screen.
void main() {
  setUp(() => brightnessChoice.value = BrightnessChoice.system);
  tearDown(() {
    brightnessChoice.value = BrightnessChoice.system;
    SpendWiseColors.apply(SpendWisePalette.sage, on: Ground.graphite);
  });

  test('a fresh install follows the system, because nobody has said otherwise', () {
    final fixture = LightModeFixture();
    addTearDown(fixture.ledger.close);

    expect(
      fixture.viewPreference(BrightnessChoice.preferenceKey),
      isNull,
      reason: 'nothing has been stored yet',
    );
    expect(
      BrightnessChoice.fromId(
        fixture.viewPreference(BrightnessChoice.preferenceKey),
      ),
      BrightnessChoice.system,
    );
  });

  test('a ledger written before this setting existed also follows the system', () {
    // Upgrades are the other fresh install: an unknown id has to land
    // somewhere, and landing on an override would mean a person who never
    // opened Appearance gets a ground they never chose.
    expect(BrightnessChoice.fromId('twilight'), BrightnessChoice.system);
    expect(BrightnessChoice.fromId(''), BrightnessChoice.system);
  });

  test('each choice resolves the platform the way its name says', () {
    expect(BrightnessChoice.system.resolve(Brightness.light), Brightness.light);
    expect(BrightnessChoice.system.resolve(Brightness.dark), Brightness.dark);
    expect(BrightnessChoice.light.resolve(Brightness.dark), Brightness.light);
    expect(BrightnessChoice.dark.resolve(Brightness.light), Brightness.dark);
  });

  testWidgets('choosing a ground stores it, and a restart comes back on it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final fixture = LightModeFixture();
    addTearDown(fixture.ledger.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: BrightnessScreen(viewModel: fixture),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(
      fixture.viewPreference(BrightnessChoice.preferenceKey),
      BrightnessChoice.light.id,
      reason: 'the picker has to write through the ledger, not just repaint',
    );

    // The restart. Everything the process held is gone; the ledger is not.
    brightnessChoice.value = BrightnessChoice.system;
    final relaunched = BrightnessChoice.fromId(
      fixture.viewPreference(BrightnessChoice.preferenceKey),
    );
    expect(relaunched, BrightnessChoice.light);
    expect(relaunched.groundFor(Brightness.dark), Ground.paper);
  });

  testWidgets('in System, the phone changing its mind at dusk changes the app', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final grounds = <Ground>[];
    await tester.pumpWidget(
      BrightnessScope(
        builder: (context, ground) {
          grounds.add(ground);
          return const SizedBox.shrink();
        },
      ),
    );
    expect(grounds.last, Ground.paper);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    expect(
      grounds.last,
      Ground.graphite,
      reason:
          'the platform changed while the app was running and System did not '
          'follow it — which is the one thing System is for',
    );
  });

  testWidgets('an override does not drift back when the phone changes', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    brightnessChoice.value = BrightnessChoice.light;

    final grounds = <Ground>[];
    await tester.pumpWidget(
      BrightnessScope(
        builder: (context, ground) {
          grounds.add(ground);
          return const SizedBox.shrink();
        },
      ),
    );
    expect(grounds.last, Ground.paper);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pump();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();

    expect(
      grounds.every((ground) => ground == Ground.paper),
      isTrue,
      reason: 'Light was chosen over the platform; the platform does not win',
    );
  });
}
