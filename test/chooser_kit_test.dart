import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/widgets/chooser_kit.dart';

/// Every settings chooser in the app is this one screen with a different
/// subject, so a defect here is a defect in all of them.
///
/// Two of them were live. The pinned preview had no ceiling: at twice the
/// default text size it wanted more height than a phone has and simply took
/// it, and the choices it exists to explain were pushed off the bottom of a
/// Column with nowhere to put them. And the choice rows animated their border
/// unconditionally -- `AnimatedContainer` does not consult the platform's
/// reduced-motion flag by itself, so a widget that never asks never honours
/// it.
void main() {
  /// A 360px phone rather than the 800x600 desktop default. This project
  /// shipped a 108px header overflow because every widget test ran at that
  /// default and nothing narrower was ever laid out.
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double textScale = 1,
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: inner!,
        ),
        home: child,
      ),
    );
  }

  /// Keyed so a test can compare what the preview wanted to be with what the
  /// pane actually gave it.
  const previewKey = Key('preview-content');

  /// Shaped like the real previews: a heading, a ribbon of fixed height, and
  /// a stack of legend lines that grow with the text size. [lines] is how
  /// many of those a chooser carries -- the savings one draws the most,
  /// because it adds a line beneath the shape as well.
  Widget preview({required int lines}) => Column(
    key: previewKey,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('ON HOME'),
      const SizedBox(height: 132),
      for (var i = 0; i < lines; i++)
        Text('Legend line $i', style: const TextStyle(fontSize: 22)),
    ],
  );

  Widget chooser({required int lines}) => ChooserScreen(
    title: 'Savings on Home',
    preview: preview(lines: lines),
    children: [
      ChoiceGroup(
        label: 'In the figure',
        first: true,
        children: [
          for (var i = 0; i < 5; i++)
            ChoiceRow(
              title: 'Choice $i',
              detail: 'One short line about choice $i.',
              selected: i == 0,
              onTap: () {},
            ),
        ],
      ),
    ],
  );

  /// How much of the preview is on screen at once. The pane only becomes a
  /// scroll view once it has run out of room, so it is measured wherever it
  /// happens to be.
  double previewPane(WidgetTester tester) {
    final scrolling = find.byType(SingleChildScrollView);
    if (scrolling.evaluate().isNotEmpty) {
      return tester.getSize(scrolling).height;
    }
    return tester.getSize(find.byType(ConstraintsTransformBox).first).height;
  }

  /// How tall the preview wanted to be.
  double previewWanted(WidgetTester tester) =>
      tester.getSize(find.byKey(previewKey)).height;

  /// How much is left for the choices.
  double choicesPane(WidgetTester tester) =>
      tester.getSize(find.byType(ListView)).height;

  group('a preview taller than the screen', () {
    testWidgets('does not overflow a 360px phone at twice the text size', (
      tester,
    ) async {
      await pump(tester, chooser(lines: 10), textScale: 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('leaves the choices at least half the screen', (tester) async {
      // Pinning the preview is the whole point of this screen -- a choice you
      // cannot see the effect of while making it is a guess -- but pinned is
      // not the same as unlimited. Half is the split that keeps the answer
      // visible and the questions reachable.
      await pump(tester, chooser(lines: 10), textScale: 2);
      expect(previewPane(tester), lessThanOrEqualTo(choicesPane(tester)));
      expect(find.text('Choice 0'), findsOneWidget);
    });

    testWidgets('and every choice can still be reached', (tester) async {
      await pump(tester, chooser(lines: 10), textScale: 2);
      await tester.dragUntilVisible(
        find.text('Choice 4'),
        find.byType(ListView),
        const Offset(0, -120),
      );
      expect(find.text('Choice 4'), findsOneWidget);
    });

    testWidgets('and scrolls rather than losing its tail', (tester) async {
      // A cap would be no better than the overflow if the part past it were
      // simply gone: the last legend line is a figure, and a figure nobody
      // can reach is a figure the screen is hiding.
      await pump(tester, chooser(lines: 10), textScale: 2);
      expect(
        previewWanted(tester),
        greaterThan(previewPane(tester)),
        reason: 'it is taller than its pane, so it has to scroll',
      );
      await tester.dragUntilVisible(
        find.text('Legend line 9'),
        find.byType(SingleChildScrollView),
        const Offset(0, -120),
      );
      expect(find.text('Legend line 9'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a preview that fits is left exactly as it was', (tester) async {
    // The cap has to be invisible until it bites, or the fix for the largest
    // text size would have quietly redesigned the screen for everyone else.
    await pump(tester, chooser(lines: 3));
    expect(
      previewPane(tester),
      closeTo(previewWanted(tester), 0.5),
      reason: 'nothing is clipped and nothing scrolls',
    );
    expect(previewPane(tester), lessThan(choicesPane(tester)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('and the screen still has exactly one thing that scrolls', (
    tester,
  ) async {
    // A second scrollable is not free. Every caller that says "scroll this
    // screen" -- a test, a switch, a voice command -- then has to say which
    // one it meant, and a preview that fits has nothing to scroll anyway.
    await pump(tester, chooser(lines: 3));
    expect(find.byType(Scrollable), findsOneWidget);
  });

  group('a choice row', () {
    Duration durationOn(WidgetTester tester) => tester
        .widget<AnimatedContainer>(
          find
              .descendant(
                of: find.byType(ChoiceRow),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        )
        .duration;

    testWidgets('travels to its selected state by default', (tester) async {
      await pump(tester, chooser(lines: 3));
      expect(durationOn(tester), const Duration(milliseconds: 140));
    });

    testWidgets('and arrives at once when motion is turned off', (
      tester,
    ) async {
      await pump(tester, chooser(lines: 3), reduceMotion: true);
      expect(durationOn(tester), Duration.zero);
    });
  });
}
