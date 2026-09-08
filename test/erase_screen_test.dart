import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/settings/erase_screen.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// Erasing was a dialog with two buttons: two taps from the settings list to
/// permanent, unrecoverable loss. There is no backup and no copy anywhere
/// else, so a mis-tap here is the worst thing this app can do to somebody.
/// Every gate below exists to make that mis-tap impossible, and every one of
/// them is only real if a test says it blocks.
void main() {
  Future<_Model> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final model = _Model();
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: EraseScreen(viewModel: model),
      ),
    );
    await tester.pumpAndSettle();
    return model;
  }

  testWidgets('typing nothing leaves the button dead', (tester) async {
    final model = await pump(tester);
    expect(find.text('Erase everything'), findsOneWidget);

    await tester.tap(find.text('Erase everything'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Erasing in'), findsNothing);
    expect(model.erased, isFalse);
  });

  testWidgets('a near miss is not the word', (tester) async {
    // "ERAS", "ERASED", a stray space at the front. Only the word counts.
    final model = await pump(tester);
    for (final attempt in ['ERAS', 'ERASED', 'DELETE', 'e r a s e']) {
      await tester.enterText(find.byType(TextField), attempt);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Erase everything'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Erasing in'),
        findsNothing,
        reason: '"$attempt" started the countdown',
      );
    }
    expect(model.erased, isFalse);
  });

  testWidgets('the word starts a countdown, and nothing is gone yet', (
    tester,
  ) async {
    final model = await pump(tester);
    await tester.enterText(find.byType(TextField), 'erase');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase everything'));
    await tester.pump();

    expect(find.text('30'), findsOneWidget);
    expect(
      model.erased,
      isFalse,
      reason: 'the countdown must not have started by deleting',
    );

    // Ten seconds in, still nothing.
    await tester.pump(const Duration(seconds: 10));
    expect(model.erased, isFalse);
    expect(find.text('20'), findsOneWidget);
  });

  testWidgets('stopping keeps the data, and resets the word', (tester) async {
    final model = await pump(tester);
    await tester.enterText(find.byType(TextField), 'ERASE');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase everything'));
    await tester.pump(const Duration(seconds: 5));

    await tester.tap(find.text('Stop, keep my data'));
    await tester.pumpAndSettle();

    // Long past the original deadline.
    await tester.pump(const Duration(seconds: 60));
    expect(model.erased, isFalse);

    // And the typed word is cleared, so stopping does not leave a screen one
    // tap from starting again.
    expect(find.text('Erase everything'), findsOneWidget);
    await tester.tap(find.text('Erase everything'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Erasing in'), findsNothing);
  });

  testWidgets('leaving the screen cancels it', (tester) async {
    // Closing the app has the same effect, for the same reason: resuming a
    // pending destroy would take the data of somebody who changed their mind.
    final model = _Model();
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => EraseScreen(viewModel: model),
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

    await tester.enterText(find.byType(TextField), 'ERASE');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase everything'));
    await tester.pump(const Duration(seconds: 3));

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 60));
    expect(model.erased, isFalse);
  });

  testWidgets('the countdown does run out, when it is left alone', (
    tester,
  ) async {
    // The gates must not be so good that the feature stops working.
    final model = await pump(tester);
    await tester.enterText(find.byType(TextField), 'ERASE');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase everything'));
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();

    expect(model.erased, isTrue);
  });

  testWidgets('it says what goes, and that nobody can get it back', (
    tester,
  ) async {
    await pump(tester);
    expect(find.textContaining('every transaction'), findsOneWidget);
    expect(find.textContaining('no backup'), findsOneWidget);
  });
}

class _Model extends ChangeNotifier implements SpendWiseViewModel {
  bool erased = false;

  @override
  Future<void> eraseAllData() async => erased = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
