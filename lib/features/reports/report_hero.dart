import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'spending_report.dart';

/// Which of the app's own drawings opens the report.
///
/// The templates used to be organised by *what data* they showed — a change
/// page, a docket, an almanac — which made choosing one a question about
/// statistics. They are organised by *drawing* instead, because a report
/// should look like the app it came out of. Someone who reads their spending
/// as a dial should be handed a dial; the choice is the one they have already
/// made on Insights, not a second unfamiliar one.
///
/// Every template carries the same summary and the same register beneath. The
/// hero is what differs, so nothing is lost by preferring one.
enum ReportTemplate {
  ribbon(
    id: 'ribbon',
    title: 'The ribbon',
    blurb: 'Everything that came in, splitting into what stayed and what left.',
  ),
  dial(
    id: 'dial',
    title: 'The dial',
    blurb:
        'A watch face. Each category a marker on the rim, its length the '
        'share.',
  ),
  desk(
    id: 'desk',
    title: 'The desk',
    blurb: 'A fader per category, each one keeping its own channel.',
  ),
  trace(
    id: 'trace',
    title: 'The trace',
    blurb: 'This period against the one before, as one continuous line.',
  );

  const ReportTemplate({
    required this.id,
    required this.title,
    required this.blurb,
  });

  final String id;
  final String title;
  final String blurb;

  static ReportTemplate fromId(String? id) {
    for (final value in values) {
      if (value.id == id) return value;
    }
    return ribbon;
  }
}

/// The paper a hero draws on: the tones, the type and the measure.
///
/// Passed rather than reached for, so a hero cannot quietly invent a colour
/// the rest of the document does not use, and so every hero is drawn against
/// the same ink on the same stock.
class ReportPaper {
  const ReportPaper({
    required this.data,
    required this.sans,
    required this.bold,
    required this.mono,
    required this.ink,
    required this.muted,
    required this.rule,
    required this.paper,
    required this.keep,
    required this.spend,
    required this.mine,
    required this.toneOf,
    required this.channelOf,
    required this.money,
    required this.width,
  });

  /// Every figure the report is made of, computed once so templates agree.
  final ReportData data;

  final pw.Font sans;
  final pw.Font bold;
  final pw.Font mono;

  /// Graphite on off-white. Not the app's near-black on its own ground: a
  /// palette that reads on a screen washes out under a printer's dot gain.
  final PdfColor ink;
  final PdfColor muted;
  final PdfColor rule;
  final PdfColor paper;

  /// The three meaning-carrying tones, already relit for paper.
  final PdfColor keep;
  final PdfColor spend;
  final PdfColor mine;

  /// A category's tone, keyed to the ledger's own category order exactly as
  /// the app keys it, so a category is the same colour on paper as it is on
  /// the screen the reader just came from.
  final PdfColor Function(String category) toneOf;

  /// The number a category answers to where one is printed, as on the desk's
  /// channel strip.
  ///
  /// Keyed to the same ledger-wide order as [toneOf] rather than rebuilt from
  /// the categories this period happens to contain. A number derived from one
  /// report's own contents is stable across reprints of that report and
  /// nothing else: the same category would answer to a different number in
  /// next month's report and to a third on the screen, which is precisely
  /// what a fixed channel number exists to prevent.
  final int Function(String category) channelOf;

  /// Grouped, and without the trailing `.00` that makes a column of round
  /// figures harder to scan than it needs to be.
  final String Function(int minorUnits) money;

  /// Usable content width in points, inside the margins.
  final double width;
}

/// One template's opening statement.
///
/// A hero returns the widgets that open the document and nothing else: the
/// masthead above it and the register below are the document's, identical
/// whichever hero is chosen. A hero that tried to own the whole page would
/// be four chances for the margins to disagree.
abstract interface class ReportHero {
  ReportTemplate get template;

  /// Drawn at the top of the first page, under the masthead.
  ///
  /// Must survive a period with nothing in it, one category, and thirty. The
  /// document is a [pw.MultiPage], so returning more than a page's worth
  /// spills rather than clipping — but a hero is an opening statement, and
  /// one that runs to two pages has stopped being one.
  List<pw.Widget> build(ReportPaper paper);
}
