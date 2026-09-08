import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/widgets/shape_kit.dart';

/// The Accounts map is one idea: the biggest balance is literally the biggest
/// thing on screen. A block used to snap straight to a new height the moment
/// a balance changed, which said a number moved without ever showing how
/// much -- the one thing a map like this exists to show.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool reduceMotion = false,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: MaterialApp(
          theme: SpendWiseTheme.dark,
          home: Scaffold(
            body: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      ),
    );
  }

  double heightOn(WidgetTester tester) =>
      tester.getSize(find.byType(AnimatedContainer)).height;

  Widget block(double height) => ProportionBlock(
    key: const ValueKey('block'),
    name: 'Everyday',
    amount: '10,000',
    height: height,
    filled: true,
  );

  testWidgets('a block travels to its new height instead of snapping to it', (
    tester,
  ) async {
    await pump(tester, block(40));
    await tester.pumpAndSettle();
    expect(heightOn(tester), closeTo(40, 0.5));

    // The account this block draws just took in a deposit.
    await pump(tester, block(160));
    await tester.pump(const Duration(milliseconds: 110));

    final travelling = heightOn(tester);
    expect(travelling, greaterThan(40), reason: 'it has left where it was');
    expect(
      travelling,
      lessThan(160),
      reason: 'and has not arrived yet -- if it had, it jumped',
    );

    await tester.pumpAndSettle();
    expect(heightOn(tester), closeTo(160, 0.5));
  });

  testWidgets('and arrives at once when motion is turned off', (tester) async {
    await pump(tester, block(40), reduceMotion: true);
    await tester.pump();
    await pump(tester, block(160), reduceMotion: true);
    await tester.pump();

    expect(heightOn(tester), closeTo(160, 0.5));
  });
}
