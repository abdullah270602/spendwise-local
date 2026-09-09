import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/dashboard/home_savings.dart';
import 'package:spendwise/features/dashboard/home_widget_snapshot.dart';

/// The widget can only ever draw what [HomeWidgetSnapshot] hands it, so this
/// is where "no figures, no words, no amounts" is actually enforced -- not by
/// a promise in a comment, but by every equality check below treating two
/// months of wildly different sizes as the same picture whenever their
/// proportion is the same.
void main() {
  HomeFigures figures({
    required int received,
    required int spent,
    required int kept,
    int saved = 0,
    int held = 0,
  }) => HomeFigures(
    received: received,
    spent: spent,
    kept: kept,
    saved: saved,
    held: held,
    from: DateTime(2026),
    to: DateTime(2026, 2),
  );

  group('hasData', () {
    test('is false for a fresh install: nothing received, nothing spent', () {
      final snapshot = HomeWidgetSnapshot.from(
        figures(received: 0, spent: 0, kept: 0),
        HomeSavingsStyle.off,
      );
      expect(snapshot.hasData, isFalse);
      // A share of nothing is not a share -- the fraction is never read in
      // this state, but it is pinned at a neutral value rather than left to
      // whatever the last division happened to produce.
      expect(snapshot.keptFraction, 0);
      expect(snapshot.hasSavedBranch, isFalse);
      expect(snapshot.savedOfKept, 0);
    });

    test('is true the moment anything has moved, even a pure loss', () {
      final snapshot = HomeWidgetSnapshot.from(
        figures(received: 0, spent: 5000, kept: -5000),
        HomeSavingsStyle.off,
      );
      expect(snapshot.hasData, isTrue);
    });
  });

  group('keptFraction', () {
    test('is the plain kept share when nothing sets saving aside', () {
      final snapshot = HomeWidgetSnapshot.from(
        figures(received: 400000, spent: 150000, kept: 250000),
        HomeSavingsStyle.off,
      );
      expect(snapshot.keptFraction, closeTo(250000 / 400000, 1e-9));
    });

    test('clamps to fully spent when kept is zero', () {
      final snapshot = HomeWidgetSnapshot.from(
        figures(received: 100000, spent: 100000, kept: 0),
        HomeSavingsStyle.off,
      );
      expect(snapshot.keptFraction, 0);
    });

    test('clamps to fully kept when nothing was spent', () {
      final snapshot = HomeWidgetSnapshot.from(
        figures(received: 100000, spent: 0, kept: 100000),
        HomeSavingsStyle.off,
      );
      expect(snapshot.keptFraction, 1);
    });

    test('an overspent month divides on magnitude, the same way FlowShape '
        'itself does -- the shape cannot tell a saved share from an '
        'overspent one, only how big each side is', () {
      final snapshot = HomeWidgetSnapshot.from(
        figures(received: 50000, spent: 80000, kept: -30000),
        HomeSavingsStyle.off,
      );
      expect(snapshot.keptFraction, closeTo(30000 / 110000, 1e-9));
    });

    test('never divides by zero when both sides are empty but flagged', () {
      // Not reachable through hasData in practice (received/spent would both
      // be zero too), but the same max(1, ...) floor FlowShape itself relies
      // on has to hold here independently of that gate.
      final snapshot = HomeWidgetSnapshot.from(
        figures(received: 1, spent: 0, kept: 0),
        HomeSavingsStyle.off,
      );
      expect(snapshot.keptFraction, 0);
    });

    test('"Only what I can spend" takes saved money out of the shape, '
        'exactly as it takes it out of Home\'s own ribbon', () {
      final month = figures(
        received: 400000,
        spent: 150000,
        kept: 250000,
        saved: 100000,
      );
      final available = HomeWidgetSnapshot.from(
        month,
        HomeSavingsStyle.available,
      );
      final plain = HomeWidgetSnapshot.from(month, HomeSavingsStyle.off);

      expect(available.keptFraction, closeTo(150000 / 300000, 1e-9));
      expect(plain.keptFraction, closeTo(250000 / 400000, 1e-9));
    });

    test('"Saving gets its own branch" leaves the headline fraction alone, '
        'exactly as it leaves Home\'s own headline alone', () {
      final month = figures(
        received: 400000,
        spent: 150000,
        kept: 250000,
        saved: 100000,
      );
      final siblings = HomeWidgetSnapshot.from(
        month,
        HomeSavingsStyle.siblings,
      );
      final plain = HomeWidgetSnapshot.from(month, HomeSavingsStyle.off);
      // `siblings` divides the kept branch further; it never changes what
      // share of the whole is kept in the first place.
      expect(siblings.keptFraction, plain.keptFraction);
    });

    test(
      '"Marked inside what is still yours" and "a seam in the shape" are '
      'not styles this widget draws a branch for -- their division is a '
      'shading inside the kept ribbon, illegible at launcher scale with no '
      'legend, so both publish the plain two-branch snapshot "off" would',
      () {
        final month = figures(
          received: 400000,
          spent: 150000,
          kept: 250000,
          saved: 100000,
        );
        final plain = HomeWidgetSnapshot.from(month, HomeSavingsStyle.off);
        for (final style in [HomeSavingsStyle.divided, HomeSavingsStyle.seam]) {
          final snapshot = HomeWidgetSnapshot.from(month, style);
          expect(snapshot.keptFraction, plain.keptFraction, reason: style.id);
          expect(snapshot.hasSavedBranch, isFalse, reason: style.id);
        }
      },
    );
  });

  group('hasSavedBranch and savedOfKept', () {
    test('only "siblings" ever draws a third branch -- every other style, '
        'including the ones that touch the headline fraction, draws none', () {
      final month = figures(
        received: 400000,
        spent: 150000,
        kept: 250000,
        saved: 100000,
      );
      for (final style in [HomeSavingsStyle.off, HomeSavingsStyle.available]) {
        final snapshot = HomeWidgetSnapshot.from(month, style);
        expect(snapshot.hasSavedBranch, isFalse, reason: style.id);
        expect(snapshot.savedOfKept, 0, reason: style.id);
      }
    });

    test('"siblings" divides the kept branch by the same share FlowShape '
        'itself would divide it by', () {
      final month = figures(
        received: 400000,
        spent: 150000,
        kept: 250000,
        saved: 100000,
      );
      final snapshot = HomeWidgetSnapshot.from(
        month,
        HomeSavingsStyle.siblings,
      );
      expect(snapshot.hasSavedBranch, isTrue);
      expect(snapshot.savedOfKept, closeTo(100000 / 250000, 1e-9));
    });

    test('a month that saved nothing draws no branch even under "siblings" -- '
        'a division with nothing on one side of it is not a division', () {
      final month = figures(
        received: 400000,
        spent: 150000,
        kept: 250000,
        saved: 0,
      );
      final snapshot = HomeWidgetSnapshot.from(
        month,
        HomeSavingsStyle.siblings,
      );
      expect(snapshot.hasSavedBranch, isFalse);
      expect(snapshot.savedOfKept, 0);
    });

    test('never divides by the sign of an overspent month', () {
      // kept is negative here; the branch cannot be drawn (there is nothing
      // still "yours" for it to come out of), and the guard above must reach
      // for the same reason it does when kept is exactly zero.
      final month = figures(
        received: 50000,
        spent: 80000,
        kept: -30000,
        saved: 0,
      );
      final snapshot = HomeWidgetSnapshot.from(
        month,
        HomeSavingsStyle.siblings,
      );
      expect(snapshot.hasSavedBranch, isFalse);
    });
  });

  group('the boundary', () {
    test(
      'two months of very different size are the identical snapshot when '
      'their shape is identical -- nothing but the ratio survives the trip',
      () {
        final small = HomeWidgetSnapshot.from(
          figures(received: 4000, spent: 1500, kept: 2500),
          HomeSavingsStyle.off,
        );
        final large = HomeWidgetSnapshot.from(
          figures(received: 40000000, spent: 15000000, kept: 25000000),
          HomeSavingsStyle.off,
        );
        expect(small, equals(large));
        expect(small.hashCode, large.hashCode);
      },
    );

    test('a different proportion is a different snapshot', () {
      final a = HomeWidgetSnapshot.from(
        figures(received: 400000, spent: 150000, kept: 250000),
        HomeSavingsStyle.off,
      );
      final b = HomeWidgetSnapshot.from(
        figures(received: 400000, spent: 250000, kept: 150000),
        HomeSavingsStyle.off,
      );
      expect(a, isNot(equals(b)));
    });

    test('the same holds once a third branch is in play -- the saved share '
        'survives the trip and the underlying amounts still do not', () {
      final small = HomeWidgetSnapshot.from(
        figures(received: 4000, spent: 1500, kept: 2500, saved: 1000),
        HomeSavingsStyle.siblings,
      );
      final large = HomeWidgetSnapshot.from(
        figures(
          received: 40000000,
          spent: 15000000,
          kept: 25000000,
          saved: 10000000,
        ),
        HomeSavingsStyle.siblings,
      );
      expect(small, equals(large));
      expect(small.hashCode, large.hashCode);
    });

    test('a different saved share is a different snapshot even when the '
        'headline fraction is identical', () {
      final a = HomeWidgetSnapshot.from(
        figures(received: 400000, spent: 150000, kept: 250000, saved: 50000),
        HomeSavingsStyle.siblings,
      );
      final b = HomeWidgetSnapshot.from(
        figures(received: 400000, spent: 150000, kept: 250000, saved: 100000),
        HomeSavingsStyle.siblings,
      );
      expect(a, isNot(equals(b)));
    });
  });
}
