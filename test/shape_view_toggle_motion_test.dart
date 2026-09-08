import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/widgets/shape_kit.dart';

/// The `Chart / Plain` control slides its fill from one segment to the other.
///
/// `AnimatedContainer` does not consult the platform's reduced-motion flag on
/// its own -- honouring it is opt-in, per widget -- so the toggle went on
/// sliding for someone who had asked the whole system to stop moving. Every
/// other implicit animation in this app already gates its duration on that
/// flag; this one opted out by saying nothing.
void main() {
  testWidgets('a segment stays compact, on purpose', (tester) async {
    // Under the 48dp Android tap-target guideline, and meant to be. Raising
    // it to 48 was tried on a real device and reverted: in a header beside a
    // screen title it read as a slab rather than a switch. Pinned here so
    // that raising it again is a decision somebody makes, rather than a
    // guideline sweep changing a control nobody was looking at.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ViewToggle(
              options: const ['Chart', 'River', 'Plain'],
              selected: 0,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(ViewToggle)).height, lessThan(36));
  });

  testWidgets('it stays one line at ordinary text size', (tester) async {
    // The first version of the tap-target fix centred each segment with the
    // Container's own `alignment`, which makes a Container with no explicit
    // width expand to every pixel it is offered. Each segment took the whole
    // row, so three of them wrapped onto three lines and the toggle became a
    // block a third of the screen tall. The width assertion below passed
    // throughout -- a full-width block is not too wide.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ViewToggle(
              options: const ['Chart', 'River', 'Plain'],
              selected: 0,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(ViewToggle));
    expect(
      size.height,
      lessThan(64),
      reason: 'three segments on one line, not stacked into a block',
    );
    // And every segment shares that line, rather than one of them holding it.
    final tops = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(ViewToggle),
            matching: find.byType(Text),
          ),
        )
        .toList();
    expect(tops, hasLength(3));
    final rects = [
      for (final option in ['CHART', 'RIVER', 'PLAIN'])
        tester.getRect(find.text(option)),
    ];
    expect(
      rects.map((rect) => rect.top).toSet(),
      hasLength(1),
      reason: 'the three labels are not on one baseline',
    );
  });

  testWidgets('it wraps instead of overflowing at large text', (tester) async {
    // Three segments named honestly at twice the default text size are wider
    // than a 360dp phone on their own. The screen that hit this first could
    // only shrink the whole control from outside, which fixed the overflow by
    // taking the tap targets back under the minimum.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ViewToggle(
              options: const ['Chart', 'River', 'Plain'],
              selected: 1,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(ViewToggle)).width,
      lessThanOrEqualTo(360),
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    required bool reduceMotion,
    int selected = 0,
  }) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: MaterialApp(
          theme: SpendWiseTheme.dark,
          home: Scaffold(
            body: Center(
              child: ViewToggle(
                options: const ['Chart', 'Plain'],
                selected: selected,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Duration> durationsOn(WidgetTester tester) => tester
      .widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byType(ViewToggle),
          matching: find.byType(AnimatedContainer),
        ),
      )
      .map((container) => container.duration)
      .toList();

  testWidgets('the segments travel by default', (tester) async {
    await pump(tester, reduceMotion: false);
    expect(
      durationsOn(tester),
      everyElement(const Duration(milliseconds: 120)),
    );
  });

  testWidgets('and arrive at once when motion is turned off', (tester) async {
    await pump(tester, reduceMotion: true);
    expect(durationsOn(tester), everyElement(Duration.zero));
  });

  testWidgets('the selected segment is still the selected one either way', (
    tester,
  ) async {
    // Reduced motion removes the travelling, never the answer: the control
    // still says which view is showing, it simply says it immediately.
    // Disposed by hand rather than in a tear-down: the framework checks for
    // a live handle before tear-downs run, and reports a leak in place of
    // whatever actually failed.
    final handle = tester.ensureSemantics();
    try {
      await pump(tester, reduceMotion: true, selected: 1);
      expect(
        tester.getSemantics(find.text('PLAIN')),
        isSemantics(isSelected: true),
      );
    } finally {
      handle.dispose();
    }
  });
}
