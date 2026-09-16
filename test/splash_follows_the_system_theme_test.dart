import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/ground.dart';

/// The one part of the app Flutter never gets to draw.
///
/// Between the launcher icon being tapped and the first Flutter frame there is
/// a window painted entirely from Android resources, and it was graphite in
/// both system modes — `values-night/styles.xml` existed, but there was no
/// `values-night/colors.xml`, so the only colour that mattered resolved the
/// same way whatever the phone was doing. On a light phone that is a black
/// flash on every single launch, which is the most-seen frame in the app.
///
/// Android resolves these by the *system* theme and nothing else, so the
/// splash cannot follow a person who has overridden SpendWise to Light on a
/// dark phone: they get a dark splash and then a paper app. With System as the
/// default that is the right answer for nearly everyone, and there is no
/// second answer available — the preference lives in an encrypted ledger that
/// cannot be opened before the window it would decide.
///
/// None of this is reachable from a widget test, so it is read as text. That
/// is weak, and it is still the difference between noticing at review and
/// noticing on a phone.
void main() {
  File res(String path) => File('android/app/src/main/res/$path');

  String read(String path) {
    final file = res(path);
    expect(file.existsSync(), isTrue, reason: file.path);
    return file.readAsStringSync();
  }

  Color colour(String source, String name) {
    final match = RegExp(
      '<color name="$name">#([0-9A-Fa-f]{6})</color>',
    ).firstMatch(source);
    expect(match, isNotNull, reason: 'no $name declared');
    return Color(0xFF000000 | int.parse(match!.group(1)!, radix: 16));
  }

  test('the splash has an answer for each system theme, and they differ', () {
    final day = read('values/colors.xml');
    final night = read('values-night/colors.xml');

    expect(colour(day, 'spendwise_splash'), Ground.paper.bg);
    expect(colour(night, 'spendwise_splash'), Ground.graphite.bg);
  });

  test('the mark on the splash is visible on the ground it lands on', () {
    // The trap this is here for: the mark's kept band is the app's near-white
    // #E9E7E2, and a splash that merely changed its background colour would
    // have drawn white on paper — an empty window with a thin clay thread
    // floating in it, which looks far more broken than a dark flash does.
    final day = read('values/colors.xml');
    final night = read('values-night/colors.xml');

    expect(
      contrastRatio(
        colour(day, 'spendwise_splash_kept'),
        colour(day, 'spendwise_splash'),
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrastRatio(
        colour(night, 'spendwise_splash_kept'),
        colour(night, 'spendwise_splash'),
      ),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('the launcher icon is not night-qualified, so it cannot change', () {
    // An icon lives in a launcher that caches it. A night-qualified ground
    // would give one install two icons with no way to say which is on screen.
    final night = read('values-night/colors.xml');
    for (final name in [
      'spendwise_background',
      'spendwise_keep',
      'spendwise_spend',
      'spendwise_mine',
    ]) {
      expect(
        night.contains('name="$name"'),
        isFalse,
        reason:
            '$name is drawn on the user\'s wallpaper — the launcher icon and '
            'the home-screen widget — where the system theme has no say',
      );
    }
  });

  test('both launch backgrounds draw the splash, not the icon foreground', () {
    // There are two copies of this drawable, and only one of them being
    // updated is exactly the kind of thing that ships.
    for (final path in [
      'drawable/launch_background.xml',
      'drawable-v21/launch_background.xml',
    ]) {
      final source = read(path);
      expect(source, contains('@color/spendwise_splash'), reason: path);
      expect(source, contains('@drawable/spendwise_splash_mark'), reason: path);
    }
  });
}
