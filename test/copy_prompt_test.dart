import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/help/help_figures.dart';

/// The app cannot answer a question -- it has no network and never will -- so
/// the prompt it hands you has to stand on its own wherever it is pasted.
void main() {
  testWidgets('it copies context, the section, and a place to type', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: const Scaffold(
          body: CopyPromptButton(
            title: 'Reading an alert',
            brief: 'SpendWise reads the sentence, not just the numbers.',
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ask an AI about this'));
    await tester.pumpAndSettle();

    final text = copied!;
    // Enough about the app that the answer is about SpendWise rather than
    // about budgeting apps in general.
    expect(text, contains('offline Android app'));
    expect(text, contains('no internet permission'));
    // The section itself, named and quoted.
    expect(text, contains('--- Reading an alert ---'));
    expect(text, contains('not just the numbers'));
    // And somewhere to put the question.
    expect(text, endsWith('My question: '));
    // Real line breaks, not the two characters that look like one.
    expect(text, contains('\n\n'));
    expect(text, isNot(contains(r'\n')));
  });

  testWidgets('it says what happened, because nobody has met this before', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: const Scaffold(
          body: CopyPromptButton(title: 'Privacy', brief: 'No network.'),
        ),
      ),
    );
    await tester.tap(find.text('Ask an AI about this'));
    await tester.pumpAndSettle();

    expect(find.text('Copied'), findsOneWidget);
    expect(find.textContaining('Paste it into'), findsOneWidget);
    expect(find.textContaining('This whole section: Privacy'), findsOneWidget);
    // The reassurance that matters in an app whose whole claim is offline.
    expect(find.textContaining('Nothing was sent anywhere'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('Copied'), findsNothing);
  });
}
