import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/category_tones.dart';
import 'package:spendwise/app/ground.dart';
import 'package:spendwise/app/palette.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/insights/chronograph.dart';
import 'package:spendwise/features/insights/spending_analytics.dart';

/// The figure at the centre of the dial, drawn white on white.
///
/// Selecting a category puts its share in the hub, and that share was built
/// with `RichText`. `RichText` is not `Text`: it paints the span exactly as
/// given and inherits nothing, so a style carrying no colour — which
/// `SpendWiseType.amount` does not — fell through to Flutter's own default.
/// That default is white.
///
/// On graphite the number was white and the ground was near-black, so it
/// looked deliberate and nobody could tell it was an accident. On paper it
/// was white on paper: the one figure a person selects a category in order
/// to read, gone.
///
/// The app has one `RichText` and this is it. The sweep in
/// `no_text_keeps_the_old_ground_test.dart` cannot catch this on its own,
/// because it walks `Text` widgets and this was not one.
///
/// The first version of this test was useless and is worth recording. It
/// pumped the dial and checked the figure's colour, and it passed with the
/// fix reverted — because the fix also changed `RichText` to `Text.rich`,
/// and `Text.rich` inherits, so the colour came back from the ambient style
/// either way. It proved inheritance worked, not that the figure states its
/// own ink.
///
/// So the dial is pumped under a deliberately hostile `DefaultTextStyle` —
/// white, the very colour the bug produced. A figure that reads correctly
/// underneath that is a figure carrying its own colour, which is the only
/// thing that survives somebody reaching for `RichText` again.
void main() {
  List<CategoryAnalytics> categories() {
    const raw = [('Groceries', 42000), ('Transport', 31000), ('Fuel', 18000)];
    final total = raw.fold<int>(0, (sum, item) => sum + item.$2);
    return [
      for (final (name, amount) in raw)
        CategoryAnalytics(
          category: name,
          amountMinor: amount,
          fraction: amount / total,
        ),
    ];
  }

  tearDown(
    () => SpendWiseColors.apply(SpendWisePalette.sage, on: Ground.graphite),
  );

  Future<Color?> hubFigureColour(WidgetTester tester, Ground ground) async {
    SpendWiseColors.apply(SpendWisePalette.sage, on: ground);
    final items = categories();
    await tester.pumpWidget(
      MaterialApp(
        theme: ground.isLight ? SpendWiseTheme.light : SpendWiseTheme.dark,
        home: Scaffold(
          // Hostile on purpose: white is what the bug drew, so a figure that
          // merely inherits its surroundings fails here and a figure that
          // names its own ink does not.
          body: DefaultTextStyle(
            style: const TextStyle(color: Colors.white),
            child: SingleChildScrollView(
              child: Chronograph(
                categories: items,
                tones: CategoryTones.positional([
                  for (final item in items) item.category,
                ]),
                // The hub only carries a figure while a category is selected.
                selected: 'Groceries',
                onSelect: (_) {},
                currency: 'PKR',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byWidgetPredicate(
      (widget) => widget is Text && widget.textSpan != null,
    );
    expect(
      finder,
      findsWidgets,
      reason: 'the hub should carry the selected share as a rich span',
    );
    final element = finder.evaluate().first;
    final span = (element.widget as Text).textSpan! as TextSpan;
    final inherited = DefaultTextStyle.of(element).style;
    final style = span.style;
    return style == null
        ? inherited.color
        : (style.inherit ? inherited.merge(style).color : style.color);
  }

  testWidgets('on paper it is the paper ground\'s ink, not white', (
    tester,
  ) async {
    final colour = await hubFigureColour(tester, Ground.paper);
    expect(colour, isNotNull, reason: 'a figure with no ink is drawn white');
    expect(
      colour!.computeLuminance(),
      lessThan(0.45),
      reason:
          'the share is the figure somebody selected a category to read; '
          'pale ink on paper loses it entirely',
    );
  });

  testWidgets('and on graphite it is still the graphite ground\'s ink', (
    tester,
  ) async {
    final colour = await hubFigureColour(tester, Ground.graphite);
    expect(colour, isNotNull);
    expect(
      colour!.computeLuminance(),
      greaterThan(0.45),
      reason:
          'the fix must not darken the figure on the ground it already '
          'read correctly on',
    );
  });
}
