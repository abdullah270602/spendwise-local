import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/security/pin_setup_screen.dart';
import 'package:spendwise/security/app_lock.dart';

/// The PIN a person picks is theirs. Four digits is the floor because three
/// is not a PIN; past that the app has no business having an opinion about
/// the length or about which digits are allowed.
void main() {
  Future<String?> runSetup(
    WidgetTester tester,
    Future<void> Function(WidgetTester tester) act, {
    Widget Function()? screen,
  }) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.push<String>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      screen?.call() ??
                      const PinSetupScreen(title: 'Set a PIN'),
                ),
              );
            },
            child: const Text('start'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    await act(tester);
    return result;
  }

  Future<void> type(WidgetTester tester, String digits) async {
    for (final digit in digits.split('')) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
  }

  Future<void> commit(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Use this PIN'));
    await tester.pumpAndSettle();
  }

  testWidgets('the done key appears only once four digits are in', (
    tester,
  ) async {
    await runSetup(tester, (tester) async {
      expect(find.bySemanticsLabel('Use this PIN'), findsNothing);
      await type(tester, '481');
      expect(find.bySemanticsLabel('Use this PIN'), findsNothing);
      await type(tester, '2');
      expect(find.bySemanticsLabel('Use this PIN'), findsOneWidget);
    });
  });

  testWidgets('a PIN longer than four is allowed', (tester) async {
    final pin = await runSetup(tester, (tester) async {
      await type(tester, '4821730');
      await commit(tester);
      // The confirmation is now fixed at seven, so it submits on its own.
      await type(tester, '4821730');
      await tester.pumpAndSettle();
    });
    expect(pin, '4821730');
  });

  testWidgets('an obvious PIN is nobody else\'s business', (tester) async {
    // Repeated digits and straight runs used to be refused. Refusing them
    // teaches nothing and mostly produces a PIN that gets written down.
    for (final obvious in ['1111', '1234']) {
      final pin = await runSetup(tester, (tester) async {
        await type(tester, obvious);
        await commit(tester);
        await type(tester, obvious);
        await tester.pumpAndSettle();
      });
      expect(pin, obvious);
    }
  });

  testWidgets('the two entries have to agree', (tester) async {
    await runSetup(tester, (tester) async {
      await type(tester, '4821');
      await commit(tester);
      await type(tester, '4822');
      await tester.pumpAndSettle();
      expect(find.text('Those did not match'), findsOneWidget);
      // And it starts over rather than leaving half a PIN behind.
      expect(find.bySemanticsLabel('Use this PIN'), findsNothing);
    });
  });

  testWidgets('proving an existing PIN submits at its own length', (
    tester,
  ) async {
    final proved = await runSetup(
      tester,
      (tester) async {
        await type(tester, '48217');
        await tester.pumpAndSettle();
      },
      screen: () => PinSetupScreen(
        title: 'Change PIN',
        confirm: false,
        fixedLength: 5,
        verify: (pin) async => pin == '48217',
      ),
    );
    expect(proved, '48217');
  });

  testWidgets('a wrong current PIN is refused and cleared', (tester) async {
    await runSetup(
      tester,
      (tester) async {
        await type(tester, '00000');
        await tester.pumpAndSettle();
        expect(find.text('Not your current PIN'), findsOneWidget);
      },
      screen: () => PinSetupScreen(
        title: 'Change PIN',
        confirm: false,
        fixedLength: 5,
        verify: (pin) async => pin == '48217',
      ),
    );
  });

  test('the floor is four and the app keeps no other opinion', () {
    expect(AppLockController.minPinLength, 4);
    expect(AppLockController.maxPinLength, greaterThanOrEqualTo(8));
  });
}
