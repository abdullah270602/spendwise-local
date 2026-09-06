import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/tour/spotlight.dart';

/// The walkthrough sits above every other route in the app, which makes it
/// exactly the kind of thing that leaks an overlay or eats the back button.
void main() {
  Future<List<String>> start(
    WidgetTester tester, {
    int stops = 3,
    VoidCallback? onDone,
  }) async {
    final entered = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Spotlight.run(context, [
                  for (var i = 0; i < stops; i++)
                    SpotlightStop(
                      title: 'Stop $i',
                      body: 'What stop $i is for.',
                      rect: () => const Rect.fromLTWH(10, 500, 80, 60),
                      onEnter: () => entered.add('Stop $i'),
                    ),
                ], onDone: onDone),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return entered;
  }

  testWidgets('it walks the stops in order and counts them honestly', (
    tester,
  ) async {
    final entered = await start(tester);
    expect(find.text('1 OF 3'), findsOneWidget);
    expect(find.text('Stop 0'), findsOneWidget);
    expect(entered, ['Stop 0']);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('2 OF 3'), findsOneWidget);
    expect(entered, ['Stop 0', 'Stop 1']);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    // The last stop offers to finish rather than promising another.
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
  });

  testWidgets('finishing removes the overlay and reports back', (tester) async {
    var done = false;
    await start(tester, stops: 2, onDone: () => done = true);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(done, isTrue);
    expect(Spotlight.isRunning, isFalse);
    expect(find.text('Stop 0'), findsNothing);
    expect(find.text('go'), findsOneWidget, reason: 'the app is back');
  });

  testWidgets('skip is on every stop, not just the first', (tester) async {
    await start(tester);
    expect(find.text('Skip'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Skip'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(Spotlight.isRunning, isFalse);
  });

  testWidgets('a tap anywhere advances', (tester) async {
    // The whole reason the scrim never has to pass a tap through: the visible
    // hole and the touchable hole cannot disagree if nothing is touchable.
    await start(tester);
    await tester.tapAt(const Offset(200, 120));
    await tester.pumpAndSettle();
    expect(find.text('2 OF 3'), findsOneWidget);
  });

  testWidgets('back leaves the tour instead of the screen under it', (
    tester,
  ) async {
    var done = false;
    await start(tester, onDone: () => done = true);
    final widgetsBinding = tester.binding;
    await widgetsBinding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(done, isTrue);
    expect(Spotlight.isRunning, isFalse);
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('starting a second tour replaces the first', (tester) async {
    // Not two stacked scrims, each eating the other's taps. The launching
    // button is under the first scrim by then, so this asks directly.
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Builder(
          builder: (context) {
            captured = context;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );

    List<SpotlightStop> stops(String label) => [
      SpotlightStop(title: label, body: 'body'),
      SpotlightStop(title: '$label two', body: 'body'),
    ];

    Spotlight.run(captured, stops('First'));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    Spotlight.run(captured, stops('Second'));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('1 OF 2'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
  });
}
