import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/ground.dart';
import 'package:spendwise/app/palette.dart';
import 'package:spendwise/features/reports/spending_report.dart';

/// There are now two copies of the relight that takes a dark-ground tone to
/// paper: `paperTone` in the PDF exporter, which has printed every report
/// SpendWise has ever made, and `paperCap` in `palette.dart`, which lights the
/// screen.
///
/// One copy would be better. It is two because the exporter was already right
/// and is outside what this change is allowed to touch, and because the screen
/// needs a `Color` where the exporter needs a `PdfColor`. That is a reason to
/// keep them, not a reason to let them drift: the entire argument for choosing
/// warm paper over a pure white or a cool grey was that the report a person
/// shares and the screen they read it on would finally be the same document.
/// If these two functions ever disagree, that stops being true silently, on
/// every tone at once, and the only place it shows is a printout next to a
/// phone.
void main() {
  test(
    'every palette tone relights to the same colour on screen as on paper',
    () {
      for (final palette in SpendWisePalette.all) {
        final tones = <String, Color>{
          'keep': palette.keep,
          'spend': palette.spend,
          'mine': palette.mine,
          for (var i = 0; i < palette.ramp.length; i++)
            'ramp ${i + 1}': palette.ramp[i],
        };
        for (final entry in tones.entries) {
          expect(
            paperCap(entry.value).toARGB32(),
            paperTone(entry.value).toInt(),
            reason:
                '${palette.name} ${entry.key}: the screen and the exporter '
                'relight the same tone differently',
          );
        }
      }
    },
  );

  test(
    'the screen and the exporter print on the same ground and the same ink',
    () {
      // Both constants are hard-coded on either side, so this is the only thing
      // holding them level. The design note that chose this ground chose it
      // because it is `_paper` byte for byte; that claim is worth a test.
      expect(Ground.paper.bg.toARGB32(), 0xFFFAF9F6);
      expect(Ground.paper.fg.toARGB32(), 0xFF17191A);
      expect(Ground.paper.dim.toARGB32(), 0xFF6B7176);
    },
  );
}
