import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/widgets/shape_kit.dart';

/// Two promises the app makes about motion, neither of which it kept.
///
/// The ribbon only ever tweened its draw-in. The proportions went to the
/// painter raw, so when the real figures changed the shape jumped to its new
/// split while the figures beside it were still counting -- the two halves of
/// one sentence disagreeing for half a second.
///
/// And nothing outside onboarding honoured reduced motion. A raw
/// TweenAnimationBuilder gets none of the help Flutter gives the Animated*
/// widgets, so it had to be done by hand or not at all.
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
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );
  }

  double keptFractionOn(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(FlowShape),
        matching: find.byType(CustomPaint),
      ),
    );
    // The painter's fields are private; its toString carries them, which is
    // enough to assert the value is travelling rather than jumping.
    return double.parse(
      RegExp(r'keptFraction: ([0-9.]+)')
              .firstMatch('${paint.painter}')
              ?.group(1) ??
          '-1',
    );
  }

  Widget shape(int kept, int spent) => FlowShape(
    key: const ValueKey('ribbon'),
    receivedMinor: kept + spent,
    keptMinor: kept,
    spentMinor: spent,
    animate: false,
  );

  group('the ribbon', () {
    testWidgets('travels to a new split instead of jumping to it', (
      tester,
    ) async {
      await pump(tester, shape(8000, 2000));
      await tester.pumpAndSettle();
      expect(keptFractionOn(tester), closeTo(0.8, 0.001));

      // The same ribbon, new figures: a scan landed, or an entry was edited.
      await pump(tester, shape(2000, 8000));
      await tester.pump(const Duration(milliseconds: 120));

      final travelling = keptFractionOn(tester);
      expect(travelling, lessThan(0.8), reason: 'it has left where it was');
      expect(
        travelling,
        greaterThan(0.2),
        reason: 'and has not arrived yet -- if it had, it jumped',
      );

      await tester.pumpAndSettle();
      expect(keptFractionOn(tester), closeTo(0.2, 0.001));
    });

    testWidgets('and arrives at once when motion is turned off', (
      tester,
    ) async {
      await pump(tester, shape(8000, 2000), reduceMotion: true);
      await tester.pump();
      await pump(tester, shape(2000, 8000), reduceMotion: true);
      await tester.pump();

      expect(keptFractionOn(tester), closeTo(0.2, 0.001));
    });
  });

  group('the figures', () {
    testWidgets('count to a new value', (tester) async {
      await pump(tester, const AnimatedMinor(100000, cents: false));
      await tester.pumpAndSettle();
      expect(find.text('1,000'), findsOneWidget);

      await pump(tester, const AnimatedMinor(900000, cents: false));
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('9,000'), findsNothing, reason: 'still on its way');

      await tester.pumpAndSettle();
      expect(find.text('9,000'), findsOneWidget);
    });

    testWidgets('and arrive at once when motion is turned off', (tester) async {
      await pump(
        tester,
        const AnimatedMinor(100000, cents: false),
        reduceMotion: true,
      );
      await tester.pump();
      await pump(
        tester,
        const AnimatedMinor(900000, cents: false),
        reduceMotion: true,
      );
      await tester.pump();

      expect(find.text('9,000'), findsOneWidget);
    });

    testWidgets('and never count up from nothing on a first build', (
      tester,
    ) async {
      // A figure that climbs from zero every time Home is opened would be
      // decoration, and would make the number unreadable while it climbed.
      await pump(tester, const AnimatedMinor(543210, cents: false));
      await tester.pump();
      expect(find.text('5,432'), findsOneWidget);
    });
  });
}
