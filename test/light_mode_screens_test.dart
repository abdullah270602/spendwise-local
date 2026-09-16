import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/brightness_choice.dart';
import 'package:spendwise/app/ground.dart';
import 'package:spendwise/app/palette.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/shell/spendwise_shell.dart';
import 'package:spendwise/features/transactions/transaction_details_screen.dart';

import 'light_mode_fixture.dart';

/// The whole app, drawn on the other ground, on a phone.
///
/// Light mode is not a repaint. `SpendWiseColors.bg` stopped being a
/// compile-time constant to make it possible, four `SpendWiseType` styles
/// became getters, and every widget that used to be built once as a `const`
/// is now built per frame — which means a screen that has only ever been
/// looked at in graphite is a screen whose light form nobody has seen. The
/// cheapest way for that to go wrong is a layout that was fine and is now
/// throwing during build, and the second cheapest is an overflow nobody
/// notices because the tests all ran in the dark.
///
/// So this pumps all five screens on paper at the narrowest phone anyone
/// still carries and asserts the boring thing: nothing threw, and the ground
/// underneath really is paper rather than graphite with a light theme bolted
/// over it. Text scale stays at 1.0 here on purpose — `home_fits_test.dart`
/// holds the metrics at 2.0, and no metric in the app depends on the ground,
/// so repeating it would test the same layout twice.
void main() {
  const width = 360.0;
  const height = 800.0;

  setUp(() => brightnessChoice.value = BrightnessChoice.system);
  tearDown(() {
    brightnessChoice.value = BrightnessChoice.system;
    SpendWiseColors.apply(SpendWisePalette.sage, on: Ground.graphite);
  });

  void onAPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Widget onPaper(Widget home) {
    SpendWiseColors.apply(SpendWisePalette.sage, on: Ground.paper);
    return MaterialApp(theme: SpendWiseTheme.light, home: home);
  }

  testWidgets('every tab of the shell draws on paper without overflowing', (
    tester,
  ) async {
    onAPhone(tester);
    final fixture = LightModeFixture();
    addTearDown(fixture.ledger.close);

    await tester.pumpWidget(onPaper(SpendWiseShell(viewModel: fixture)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Home');

    for (final tab in ['Ledger', 'Review', 'Insights', 'Accounts']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
  });

  testWidgets('a transaction detail draws on paper without overflowing', (
    tester,
  ) async {
    onAPhone(tester);
    final fixture = LightModeFixture();
    addTearDown(fixture.ledger.close);

    await tester.pumpWidget(
      onPaper(
        TransactionDetailsScreen(
          viewModel: fixture,
          transaction: fixture.anEntry,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Chenab Grocers'), findsOneWidget);
  });

  testWidgets(
    'the light theme really is the paper ground, not a tinted dark one',
    (tester) async {
      // The failure worth naming: `ThemeData` and the `SpendWiseColors` statics
      // are two halves of one answer, and a screen where they disagree is one
      // where the scaffold is paper and everything painted on it is still
      // graphite. Asking the built theme rather than the constants is what makes
      // this a check on the wiring rather than on `Ground.paper`.
      onAPhone(tester);
      late ThemeData theme;
      await tester.pumpWidget(
        onPaper(
          Builder(
            builder: (context) {
              theme = Theme.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, Ground.paper.bg);
      expect(theme.colorScheme.onSurface, Ground.paper.fg);
      expect(SpendWiseColors.bg, Ground.paper.bg);
      expect(
        SpendWiseColors.keep,
        SpendWisePalette.sage.onPaper.keep,
        reason:
            'the semantic tones have to be the relit ones — the graphite trio '
            'on paper is three washes',
      );
    },
  );

  testWidgets('asking for the dark theme afterwards puts the ground back', (
    tester,
  ) async {
    // Both themes are asked for across one process — by these tests, and by
    // anyone who flips the setting twice — and the statics are global. A theme
    // that only applied its ground on the way out to light would leave the
    // app half-lit on the way back.
    onAPhone(tester);
    await tester.pumpWidget(onPaper(const SizedBox.shrink()));
    expect(SpendWiseColors.bg, Ground.paper.bg);

    await tester.pumpWidget(
      MaterialApp(theme: SpendWiseTheme.dark, home: const SizedBox.shrink()),
    );
    expect(SpendWiseColors.bg, Ground.graphite.bg);
    expect(SpendWiseColors.keep, SpendWisePalette.sage.keep);
  });
}
