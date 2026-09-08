import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../app/category_tones.dart';
import 'report_hero.dart';

/// The desk, printed: the same channel strip and patch bay as
/// `lib/features/insights/mixing_desk.dart`, redrawn for a page that cannot
/// be tapped.
///
/// Three things had to change for paper rather than glass, each decided here
/// rather than borrowed:
///
/// Colour carries the hardware feel on screen through a two-tone bevel --
/// one step lighter on top and left, one step darker on bottom and right --
/// which depends on a dark faceplate to read as depth at all; on white stock
/// it would invert into a smear, and a home printer's dot gain would not
/// hold the two steps apart regardless. What stands in for it here is line
/// weight, not colour: the plate is one hairline rule (the same idiom the
/// rest of this report already uses for "this is a boundary" -- the
/// masthead's rule, a docket subtotal's rule), each track is a hairline
/// groove with tick marks at the same quarter-heights the screen's own
/// `.grad` marks sit at, and each fader cap gets one crisp ink line along
/// its top edge standing in for a machined seam. A single hard line costs
/// the same at any print resolution; a soft light-to-dark gradient either
/// vanishes (too subtle) or muddies (not subtle enough) under dot gain, so
/// it is not attempted.
///
/// Every shape below is an ordinary `pw` widget -- `Container`, `BoxDecoration`,
/// `Stack`, `Positioned` -- never a `CustomPaint` canvas. That is a deliberate
/// match to the screen, not a shortcut: the finalized design brief for the
/// real widget is explicit that it needs "no shaders anywhere, no
/// CustomPainter required at all," because the only reasons `shape_kit.dart`
/// and this report's own ribbon reach for a canvas -- an organic curve, or
/// one hit-tested surface serving many touch targets -- do not apply here.
/// A still page has no touch targets to unify, and every one of this desk's
/// shapes is an axis-aligned rectangle a border can draw. Staying in
/// ordinary widgets also keeps the geometry a plain, testable function
/// ([deskLayoutFor], [deskLevelFor]) instead of arithmetic buried inside
/// canvas calls -- which is what lets a test assert a fader's height is in
/// true proportion to its share without first rendering a page of PDF bytes.
///
/// Paper adds one requirement the screen does not carry: there is no tap to
/// reveal what an AUX fold swallowed, so every category it holds is printed
/// in full underneath the patch bay, not left one gesture away.
class DeskHero implements ReportHero {
  const DeskHero();

  @override
  ReportTemplate get template => ReportTemplate.desk;

  // ---- geometry -------------------------------------------------------
  //
  // Every constant below is public so a test can build its own expectation
  // from the same numbers the drawing uses, rather than re-typing them and
  // risking the two silently drifting apart.

  /// Past this many active categories the strip folds into one AUX channel,
  /// unchanged from the screen's own threshold. The page has roughly 499pt
  /// of measure against the screen's 300px of strip -- far more room -- but
  /// that room is spent on making each of fourteen channels wider and more
  /// legible, not on packing more channels in. Keeping the same fold point
  /// means paper and screen agree on exactly which categories get a
  /// dedicated channel and which fold into AUX for the same ledger, which is
  /// what makes the two recognisably the same instrument rather than two
  /// objects that merely resemble each other.
  static const foldAt = 14;

  /// At or below this many total slots (real channels plus AUX, if any) the
  /// strip reads as a small desk on purpose rather than a large one missing
  /// most of its channels, and switches to a centred, fixed-width layout --
  /// the same threshold, and the same reasoning, as the screen's.
  static const miniMax = 6;

  static const trackHeight = 130.0;
  static const headroom = 8.0;

  /// The floor under a fader's height: even a category at a fraction of a
  /// percent still draws as a visible sliver rather than nothing. The
  /// honest cost, unchanged from the screen's own note on the same number,
  /// is that this is a fixed offset added to every channel, not a
  /// proportional line through zero -- the bottom of the scale is
  /// compressed, and a category needs real share before its height reads as
  /// more than "the floor plus a sliver." The printed percentage above the
  /// cap and the patch bay beneath it are what state the exact figure; the
  /// fader states the gist.
  static const minCap = 6.0;

  static const range = trackHeight - minCap - headroom;
  static const capHeight = 6.0;

  static const gap = 4.0;
  static const miniWidth = 34.0;
  static const miniGap = 20.0;
  static const cheekWidth = 10.0;

  @override
  List<pw.Widget> build(ReportPaper paper) {
    final categories = paper.data.byCategory;
    final total = categories.fold<int>(0, (sum, entry) => sum + entry.value);

    final header = pw.Row(
      children: [
        pw.Expanded(child: _eyebrow(paper, 'Where your money went')),
        pw.Text(
          paper.money(total),
          style: pw.TextStyle(
            font: paper.mono,
            fontSize: 8,
            color: paper.ink,
            letterSpacing: .8,
          ),
        ),
      ],
    );

    // A period with no categorised spending still has to open the report --
    // stated plainly, the same voice the rest of this document uses for an
    // empty period, rather than an empty box that looks unfinished.
    if (categories.isEmpty) {
      return [
        header,
        pw.SizedBox(height: 12),
        pw.Text(
          'No categories carried spend this period.',
          style: pw.TextStyle(fontSize: 10, color: paper.muted),
        ),
      ];
    }

    // The floor rule the screen also keeps: one channel has nothing to be
    // compared against, so a fader bank showing exactly one fader is a
    // number pretending to be a chart. The solo module names the category
    // in full instead.
    if (categories.length == 1) {
      return [header, pw.SizedBox(height: 16), _solo(paper, categories.single)];
    }

    // The document's own numbering, which comes from the ledger's whole
    // category list rather than from this period's slice of it. A number
    // derived from one report's contents is stable across reprints of that
    // report and nothing else: the same category would answer to a different
    // number next month, and to a third one on Insights.
    final layout = deskLayoutFor(categories, paper.channelOf);

    return [
      header,
      pw.SizedBox(height: 14),
      pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border.all(color: paper.rule)),
        padding: const pw.EdgeInsets.fromLTRB(12, 14, 12, 10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _strip(paper, layout),
            pw.SizedBox(height: 10),
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: paper.rule)),
              ),
              padding: const pw.EdgeInsets.only(top: 9),
              child: _patchBay(paper, layout),
            ),
          ],
        ),
      ),
    ];
  }

  // ---- the strip --------------------------------------------------------

  pw.Widget _strip(ReportPaper paper, DeskLayout layout) {
    final channels = layout.channels;
    final n = channels.length;

    if (layout.mini) {
      return pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          _cheek(paper),
          for (var i = 0; i < n; i++) ...[
            if (i > 0) pw.SizedBox(width: miniGap),
            pw.SizedBox(
              width: miniWidth,
              child: _column(paper, channels[i], layout.maxFraction),
            ),
          ],
          _cheek(paper),
        ],
      );
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < n; i++) ...[
          if (i > 0) pw.SizedBox(width: gap),
          pw.Expanded(child: _column(paper, channels[i], layout.maxFraction)),
        ],
      ],
    );
  }

  /// A blank end-plate bookending the strip's small-desk layout -- filler
  /// that says "this desk is small on purpose," the same reasoning the
  /// screen's own cheek carries.
  pw.Widget _cheek(ReportPaper paper) => pw.Container(
    width: cheekWidth,
    height: 20,
    margin: const pw.EdgeInsets.only(bottom: 16),
    color: paper.rule,
  );

  /// One fader: an ink-marked patch tick, the scribble-strip abbreviation,
  /// the share it carries, the track with its groove marks and cap, and the
  /// stable number underneath -- the same five elements in the same order
  /// as the screen's channel column.
  pw.Widget _column(
    ReportPaper paper,
    DeskChannel channel,
    double maxFraction,
  ) {
    final level = deskLevelFor(channel.fraction, maxFraction);
    final label = channel.isAux ? 'AUX' : _abbreviate(channel.category);
    final noText = channel.isAux
        ? 'S${channel.auxCount}'
        : channel.no.toString().padLeft(2, '0');
    final pctText = (channel.fraction * 100).toStringAsFixed(1);
    final PdfColor? tone = channel.isAux
        ? null
        : paper.toneOf(channel.category);

    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(width: 3, height: 3, color: paper.ink),
        pw.SizedBox(height: 4),
        pw.Text(
          label,
          maxLines: 1,
          overflow: pw.TextOverflow.clip,
          style: pw.TextStyle(
            font: paper.mono,
            fontSize: 6.5,
            color: paper.muted,
            letterSpacing: .3,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          pctText,
          maxLines: 1,
          style: pw.TextStyle(
            font: paper.mono,
            fontSize: 7,
            color: paper.muted,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.SizedBox(
          width: double.infinity,
          height: trackHeight,
          child: pw.Stack(
            alignment: pw.Alignment.bottomCenter,
            children: [
              pw.Container(width: 1, height: trackHeight, color: paper.rule),
              // The screen's `.grad` reference marks, redrawn as an
              // engraved scale rather than a lit gutter -- a ruler's own
              // idiom for "measured precisely," which does not need light
              // to read on paper the way the screen's bevel did.
              for (final fraction in const [0.25, 0.5, 0.75])
                pw.Positioned(
                  bottom: fraction * trackHeight,
                  child: pw.Container(width: 7, height: .6, color: paper.rule),
                ),
              pw.Positioned(
                left: 0,
                right: 0,
                bottom: (level - capHeight / 2).clamp(
                  0.0,
                  trackHeight - capHeight,
                ),
                child: pw.Container(
                  height: capHeight,
                  decoration: pw.BoxDecoration(
                    color: tone,
                    // The plate-seam substitute for the screen's two-tone
                    // bevel: one hard ink rule along the cap's top edge.
                    // AUX carries no category, so it stays hollow -- an
                    // outline in the muted tone, the same "this is not one
                    // category" signal the screen's own transparent AUX cap
                    // sends.
                    border: channel.isAux
                        ? pw.Border.all(color: paper.muted, width: .8)
                        : pw.Border(
                            top: pw.BorderSide(color: paper.ink, width: .7),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          noText,
          style: pw.TextStyle(
            font: paper.mono,
            fontSize: 7.5,
            color: paper.muted,
          ),
        ),
      ],
    );
  }

  // ---- the patch bay ------------------------------------------------------

  pw.Widget _patchBay(ReportPaper paper, DeskLayout layout) {
    final real = layout.channels.where((channel) => !channel.isAux).toList();
    final aux = layout.channels.where((channel) => channel.isAux).toList();
    final rows = [for (final channel in real) _patchRow(paper, channel)];
    if (aux.isNotEmpty) rows.add(_patchRow(paper, aux.single));

    final paired = <pw.Widget>[
      for (var i = 0; i < rows.length; i += 2)
        pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: rows[i]),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: i + 1 < rows.length ? rows[i + 1] : pw.SizedBox(),
              ),
            ],
          ),
        ),
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        ...paired,
        // Stricter than the screen: there is no tap here to reveal what
        // AUX swallowed, so every category it folded is named and given its
        // own stable number below, unconditionally, rather than behind a
        // gesture the reader of a printed page cannot make.
        if (aux.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: paper.rule)),
            ),
            padding: const pw.EdgeInsets.only(top: 6),
            child: _auxList(paper, aux.single.auxFolded),
          ),
        ],
      ],
    );
  }

  pw.Widget _patchRow(ReportPaper paper, DeskChannel channel) {
    final label = channel.isAux
        ? '+ ${channel.auxCount} more'
        : channel.category;
    final noText = channel.isAux ? 'S' : channel.no.toString().padLeft(2, '0');
    final pctText = '${(channel.fraction * 100).toStringAsFixed(1)}%';
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        children: [
          pw.Container(
            width: 7,
            height: 7,
            decoration: pw.BoxDecoration(
              color: channel.isAux ? null : paper.toneOf(channel.category),
              border: channel.isAux
                  ? pw.Border.all(color: paper.muted, width: .8)
                  : null,
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Text(
            noText,
            style: pw.TextStyle(
              font: paper.mono,
              fontSize: 7.5,
              color: paper.muted,
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Text(
              label,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(fontSize: 9.5, color: paper.ink),
            ),
          ),
          pw.Text(
            pctText,
            style: pw.TextStyle(
              font: paper.mono,
              fontSize: 7.5,
              color: paper.muted,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _auxList(ReportPaper paper, List<DeskChannel> folded) {
    final rows = [for (final channel in folded) _auxRow(paper, channel)];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i += 2)
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: rows[i]),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: i + 1 < rows.length ? rows[i + 1] : pw.SizedBox(),
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget _auxRow(ReportPaper paper, DeskChannel channel) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      children: [
        pw.Text(
          channel.no.toString().padLeft(2, '0'),
          style: pw.TextStyle(
            font: paper.mono,
            fontSize: 7,
            color: paper.muted,
          ),
        ),
        pw.SizedBox(width: 6),
        pw.Expanded(
          child: pw.Text(
            channel.category,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(fontSize: 8.5, color: paper.ink),
          ),
        ),
        pw.Text(
          '${(channel.fraction * 100).toStringAsFixed(2)}%',
          style: pw.TextStyle(
            font: paper.mono,
            fontSize: 7,
            color: paper.muted,
          ),
        ),
      ],
    ),
  );

  // ---- the N=1 case -------------------------------------------------------

  /// The screen's own "insert" module, redrawn: the category named in full
  /// (nothing to disambiguate, so no abbreviation), one wide fader reading
  /// 100%, the same track-groove relief the strip uses -- so it still reads
  /// as the same hardware family rather than a fallback screen bolted on.
  pw.Widget _solo(ReportPaper paper, MapEntry<String, int> only) {
    final tone = paper.toneOf(only.key);
    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: paper.rule)),
      padding: const pw.EdgeInsets.all(14),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            only.key,
            style: pw.TextStyle(
              font: paper.bold,
              fontSize: 15,
              color: paper.ink,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            'Nothing to compare against yet -- one category is the whole '
            'period.',
            style: pw.TextStyle(fontSize: 9, color: paper.muted),
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.SizedBox(
                width: 36,
                height: trackHeight,
                child: pw.Stack(
                  alignment: pw.Alignment.bottomCenter,
                  children: [
                    pw.Container(
                      width: 2,
                      height: trackHeight,
                      color: paper.rule,
                    ),
                    pw.Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: pw.Container(
                        height: 9,
                        decoration: pw.BoxDecoration(
                          color: tone,
                          border: pw.Border(
                            top: pw.BorderSide(color: paper.ink, width: .8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '100%',
                      style: pw.TextStyle(
                        font: paper.bold,
                        fontSize: 24,
                        color: paper.ink,
                        letterSpacing: -.6,
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      '${paper.money(only.value)} · every expense this '
                      'period',
                      style: pw.TextStyle(
                        font: paper.mono,
                        fontSize: 8,
                        color: paper.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _eyebrow(ReportPaper paper, String text) => pw.Text(
    text.toUpperCase(),
    style: pw.TextStyle(
      font: paper.mono,
      fontSize: 7.5,
      color: paper.muted,
      letterSpacing: 2,
    ),
  );
}

/// The scribble strip's abbreviation: strip non-letters, take the first
/// four, uppercase. Copied rather than imported from `mixing_desk.dart`,
/// which this task is told not to touch -- both copies implement the one
/// algorithm the design settled on, and either one changing without the
/// other is a divergence worth seeing in a diff, not something an import
/// would quietly paper over.
String _abbreviate(String name) {
  final letters = name.replaceAll(RegExp('[^A-Za-z]'), '');
  final take = letters.length > 4 ? letters.substring(0, 4) : letters;
  return take.toUpperCase();
}

/// One channel's resolved facts -- which category (if any), the stable
/// number it answers to, and its share of the period's spend -- exposed so
/// a test can check real geometry against the same values the drawing used,
/// without parsing the PDF bytes the drawing eventually becomes.
@immutable
@visibleForTesting
class DeskChannel {
  const DeskChannel({
    required this.category,
    required this.no,
    required this.fraction,
    required this.amountMinor,
    this.isAux = false,
    this.auxCount = 0,
    this.auxFolded = const [],
  });

  final String category;
  final int no;
  final double fraction;
  final int amountMinor;

  /// True for the one folded channel a long period grows past
  /// [DeskHero.foldAt]. It is not a category, so it never carries a tone.
  final bool isAux;
  final int auxCount;
  final List<DeskChannel> auxFolded;
}

@immutable
@visibleForTesting
class DeskLayout {
  const DeskLayout({
    required this.channels,
    required this.maxFraction,
    required this.mini,
  });

  final List<DeskChannel> channels;
  final double maxFraction;
  final bool mini;
}

/// The order this hero prints channel numbers in, rebuilt from whatever
/// categories this one report actually touches.
///
/// [CategoryTones] is meant to be built from the ledger's whole history --
/// that is what makes a channel number mean the same thing next month, and
/// [ReportPaper.toneOf] already carries that promise for colour, resolved by
/// whoever built the paper this hero draws on. [ReportData] itself, though,
/// only ever carries the categories one period actually spent against, never
/// the account's full category list -- there is no all-time roster here to
/// sort system-first-then-user the way the real [CategoryTones] does.
/// Alphabetical order over the categories on this page is the closest a
/// single period can get to the same promise without that history: the same
/// set of categories always sorts to the same numbers, so a channel's number
/// on a re-printed copy of this exact report cannot be shuffled merely
/// because this period's ranking put a different category first -- the same
/// defect the design this hero implements was written to rule out. It is
/// not guaranteed to equal the number the same category answers to on the
/// Insights screen, which has more history to draw its own order from; a
/// future [ReportPaper] that threads a real, ledger-wide [CategoryTones]
/// through would let this match exactly.
@visibleForTesting
CategoryTones deskTonesFor(List<MapEntry<String, int>> categories) =>
    CategoryTones.positional(
      categories.map((entry) => entry.key).toList()..sort(),
    );

/// Turns this period's category totals into channels: numbered by [channelOf],
/// ordered by that stable number rather than by amount, and folded into one
/// AUX channel past [foldAt] active categories -- the same computation
/// `mixing_desk.dart`'s own `_layout` performs, mirrored here because that
/// file is off limits to this task and paper cannot import a private
/// function from it regardless.
@visibleForTesting
DeskLayout deskLayoutFor(
  List<MapEntry<String, int>> categories,
  int Function(String category) channelOf, {
  int foldAt = DeskHero.foldAt,
}) {
  final total = categories.fold<int>(0, (sum, entry) => sum + entry.value);
  final withNo = [
    for (final entry in categories)
      DeskChannel(
        category: entry.key,
        no: channelOf(entry.key),
        fraction: total <= 0 ? 0 : entry.value / total,
        amountMinor: entry.value,
      ),
  ];
  final maxFraction = withNo.fold<double>(
    0,
    (best, channel) => math.max(best, channel.fraction),
  );

  List<DeskChannel> real;
  DeskChannel? aux;
  if (withNo.length > foldAt) {
    // Which categories earn a dedicated channel this period is unavoidably
    // a rank question, even though where they sit once they earn one is
    // not -- so the split is by amount, and only the display order that
    // follows it is put back into stable channel order.
    final byAmount = [...withNo]
      ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    real = byAmount.sublist(0, foldAt - 1)
      ..sort((a, b) => a.no.compareTo(b.no));
    final folded = byAmount.sublist(foldAt - 1)
      ..sort((a, b) => a.no.compareTo(b.no));
    aux = DeskChannel(
      category: '',
      no: 0,
      fraction: folded.fold<double>(
        0,
        (sum, channel) => sum + channel.fraction,
      ),
      amountMinor: folded.fold<int>(
        0,
        (sum, channel) => sum + channel.amountMinor,
      ),
      isAux: true,
      auxCount: folded.length,
      auxFolded: folded,
    );
  } else {
    real = [...withNo]..sort((a, b) => a.no.compareTo(b.no));
  }

  final channels = [...real, ?aux];
  return DeskLayout(
    channels: channels,
    // A period where every category sits at 0% would otherwise divide by
    // zero; there is nothing honest to draw then anyway; the categories
    // this hero is ever handed always carry a positive amount, so this is a
    // defensive floor rather than a reachable branch.
    maxFraction: maxFraction <= 0 ? 1 : maxFraction,
    mini: channels.length <= DeskHero.miniMax,
  );
}

/// A channel's cap height in points, floored at [DeskHero.minCap] so even a
/// sliver of a share still draws as visible ink -- see [DeskHero.minCap] for
/// the honesty cost of that floor.
@visibleForTesting
double deskLevelFor(double fraction, double maxFraction) {
  if (fraction <= 0) return 0;
  final safeMax = maxFraction <= 0 ? 1 : maxFraction;
  return DeskHero.minCap + (fraction / safeMax) * DeskHero.range;
}
