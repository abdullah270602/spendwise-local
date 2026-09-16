import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/brightness_choice.dart';
import 'package:spendwise/app/ground.dart';
import 'package:spendwise/app/palette.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/shell/spendwise_shell.dart';

import 'light_mode_fixture.dart';

/// Text that kept the ink of the ground it was written for.
///
/// The text theme was assembled with `copyWith`, which replaces a style
/// outright — so handing it a `SpendWiseType` entry with no colour threw away
/// the colour Flutter's own base theme had put there. `titleLarge`,
/// `bodyLarge`, `headlineSmall` and the rest came back with a null colour, and
/// `ListTileThemeData` was given two more the same way.
///
/// On graphite that was invisible: whatever a null colour resolved to happened
/// to be close enough to off-white that nobody could tell. On paper it was
/// not. Settings headings, every list tile's title and every app name in the
/// source picker stayed in the old ground's ink — pale text on pale paper.
///
/// A colour that is right by accident on one ground is a colour that will be
/// wrong on the next one, so this walks the real screens and refuses any text
/// that either has no ink at all or has ink too light to read on paper.
void main() {
  /// A colour this pale on `#FAF9F6` is somewhere between hard to read and
  /// invisible. Deliberately generous: the point is to catch text still
  /// wearing the dark ground's off-white, not to police contrast, which
  /// `contrast_floor_test.dart` does properly.
  const tooPaleForPaper = 0.45;

  setUp(() => brightnessChoice.value = BrightnessChoice.system);
  tearDown(() {
    brightnessChoice.value = BrightnessChoice.system;
    SpendWiseColors.apply(SpendWisePalette.sage, on: Ground.graphite);
  });

  void onAPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Widget onPaper(Widget home) {
    SpendWiseColors.apply(SpendWisePalette.sage, on: Ground.paper);
    return MaterialApp(theme: SpendWiseTheme.light, home: home);
  }

  List<String> unreadableIn(WidgetTester tester) {
    final wrong = <String>[];
    for (final element in find.byType(Text).evaluate()) {
      final text = element.widget as Text;
      if (text.data == null || text.data!.trim().isEmpty) continue;
      final inherited = DefaultTextStyle.of(element).style;
      final style = text.style;
      final resolved = style == null
          ? inherited
          : (style.inherit ? inherited.merge(style) : style);
      final colour = resolved.color;
      if (colour == null) {
        wrong.add('no ink at all: "${text.data}"');
      } else if (colour.toARGB32() & 0xFFFFFF ==
          SpendWiseColors.bg.toARGB32() & 0xFFFFFF) {
        // Deliberately the ground's own colour: a label sitting on a filled
        // chip, inverted on purpose, which follows the ground like everything
        // else. Compared without its alpha because these are routinely faded
        // -- the ledger's selected view toggle draws one at full strength and
        // an account's masked digits draw one at 72%.
        continue;
      } else if (colour.computeLuminance() > tooPaleForPaper) {
        wrong.add(
          'ink too pale for paper '
          '(${colour.toARGB32().toRadixString(16)}): "${text.data}"',
        );
      }
    }
    return wrong;
  }

  testWidgets('every tab of the shell is written in ink you can read', (
    tester,
  ) async {
    onAPhone(tester);
    final fixture = LightModeFixture();
    addTearDown(fixture.ledger.close);

    await tester.pumpWidget(onPaper(SpendWiseShell(viewModel: fixture)));
    await tester.pumpAndSettle();
    expect(
      unreadableIn(tester),
      isEmpty,
      reason: 'Home, on paper',
    );

    for (final tab in ['Ledger', 'Review', 'Insights', 'Accounts']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(unreadableIn(tester), isEmpty, reason: '$tab, on paper');
    }
  });
}
