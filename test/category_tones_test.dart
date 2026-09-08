import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/category_tones.dart';
import 'package:spendwise/app/palette.dart';
import 'package:spendwise/app/theme.dart';

/// A category's colour used to be its position in whatever list was being
/// drawn, so it changed whenever spending changed. Two screens showing the
/// same month could disagree, and the same category could be two colours in
/// two months without anything about it having changed.
void main() {
  // What the database returns: system categories first, then the user's,
  // both alphabetical.
  const known = [
    'Bills & utilities',
    'Food & dining',
    'Groceries',
    'Health',
    'Transport',
    'Kite repairs',
  ];

  test('a category keeps its tone when its ranking moves', () {
    final march = CategoryTones(
      known: known,
      present: const ['Groceries', 'Transport', 'Health'],
    );
    // April: Transport overtook Groceries. Under the old scheme both would
    // have swapped colours purely because the sort did.
    final april = CategoryTones(
      known: known,
      present: const ['Transport', 'Groceries', 'Health'],
    );

    for (final name in ['Groceries', 'Transport', 'Health']) {
      expect(
        april.of(name),
        march.of(name),
        reason: '$name changed colour without changing',
      );
    }
  });

  test('adding a category does not repaint the ones that were there', () {
    final before = CategoryTones(known: known);
    final after = CategoryTones(known: [...known, 'Astronomy']);

    for (final name in known) {
      expect(after.of(name), before.of(name), reason: '$name was repainted');
    }
  });

  test('a category the app has no row for still gets its own tone', () {
    final tones = CategoryTones(
      known: known,
      present: const ['Groceries', 'Falconry'],
    );
    expect(
      tones.of('Falconry'),
      isNot(tones.of('Groceries')),
      reason: 'an unfiled category must not collide with a filed one',
    );
    expect(tones.slotOf('Falconry'), known.length);
  });

  test(
    'every category in one view is drawn differently from its neighbours',
    () {
      // This asserted twenty and passed, while the real collision sat at
      // thirty-two: fading alone clamped, so slot 32 came out byte-identical
      // to slot 24. Twenty proved nothing about the scheme, only about the
      // part of it nobody reaches. Sixty-four is past any plausible ledger,
      // and past where every clamp used to bite.
      final tones = CategoryTones(
        known: [for (var i = 0; i < 64; i++) 'Category $i'],
      );
      final seen = <int, int>{};
      for (var i = 0; i < 64; i++) {
        final colour = tones.of('Category $i').toARGB32();
        expect(
          seen.containsKey(colour),
          isFalse,
          reason: 'Category $i repeats the tone of Category ${seen[colour]}',
        );
        seen[colour] = i;
      }
    },
  );

  test('the ramp holds for every palette, not just the shipped one', () {
    // The collision was found in sage. Nothing said the other four behaved.
    for (final palette in SpendWisePalette.all) {
      SpendWiseColors.apply(palette);
      final seen = <int, int>{};
      for (var i = 0; i < 64; i++) {
        final colour = SpendWiseColors.category(i).toARGB32();
        expect(
          seen.containsKey(colour),
          isFalse,
          reason: '${palette.name}: slot $i repeats slot ${seen[colour]}',
        );
        seen[colour] = i;
      }
    }
    SpendWiseColors.apply(SpendWisePalette.sage);
  });

  test('channel numbers are one-based and stable', () {
    final tones = CategoryTones(known: known);
    expect(tones.channelOf('Bills & utilities'), 1);
    expect(tones.channelOf('Kite repairs'), known.length);
  });

  test('the positional form is what a preview with no ledger gets', () {
    final tones = CategoryTones.positional(const ['One', 'Two']);
    expect(tones.of('One'), SpendWiseColors.category(0));
    expect(tones.of('Two'), SpendWiseColors.category(1));
  });
}
