import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/shell/spendwise_shell.dart';

import 'light_mode_fixture.dart';

/// The only sign the app gives that it is doing something.
///
/// The shell has no app bar, so the Scaffold does not push its body down,
/// and the status bar is drawn transparent. Every page carries its own
/// SafeArea; this indicator sits in the shell's Stack, outside all of them.
/// Positioned at zero it was drawn behind the clock — invisible on every
/// path except the tray scan, which happens to have a spinner of its own,
/// which is why nobody noticed a progress bar that never appeared.
void main() {
  testWidgets('it is drawn below the status bar, not under it', (tester) async {
    const statusBar = 48.0;
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.viewPadding = const FakeViewPadding(top: statusBar * 3);
    tester.view.padding = const FakeViewPadding(top: statusBar * 3);
    addTearDown(tester.view.reset);

    final fixture = LightModeFixture()..busyNow = true;
    addTearDown(fixture.ledger.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: SpendWiseShell(viewModel: fixture),
      ),
    );
    await tester.pump();

    final bar = find.byType(LinearProgressIndicator);
    expect(bar, findsOneWidget);
    expect(
      tester.getTopLeft(bar).dy,
      greaterThanOrEqualTo(statusBar),
      reason: 'a progress bar under the clock is a progress bar nobody sees',
    );
  });
}
