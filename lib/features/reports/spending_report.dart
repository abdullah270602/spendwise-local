import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart' show Color, HSLColor;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../app/category_tones.dart';
import '../../app/theme.dart';
import '../../app/palette.dart';
import '../shell/spendwise_view_model.dart';
import 'report_hero.dart';
import 'report_hero_desk.dart';
import 'report_hero_dial.dart';
import 'report_hero_ribbon.dart';
import 'report_hero_trace.dart';

/// How much of the ledger a report covers.
enum ReportRange { thisMonth, lastThreeMonths, thisYear, everything, custom }

extension ReportRangeCopy on ReportRange {
  String get title => switch (this) {
    ReportRange.thisMonth => 'This month',
    ReportRange.lastThreeMonths => 'Last three months',
    ReportRange.thisYear => 'This year',
    ReportRange.everything => 'Everything',
    ReportRange.custom => 'Pick dates',
  };
}

@immutable
class ReportRequest {
  const ReportRequest({
    required this.template,
    required this.from,
    required this.to,
    required this.label,
  });

  final ReportTemplate template;
  final DateTime from;
  final DateTime to;

  /// How the period reads on the cover: "September 2026", "Jul – Sep 2026".
  final String label;

  static ReportRequest forRange(
    ReportRange range,
    ReportTemplate template, {
    DateTime? now,
    DateTime? customFrom,
    DateTime? customTo,
    DateTime? earliest,
  }) {
    final anchor = now ?? DateTime.now();
    final today = DateTime(anchor.year, anchor.month, anchor.day);
    final (from, to) = switch (range) {
      ReportRange.thisMonth => (
        DateTime(today.year, today.month),
        DateTime(today.year, today.month + 1, 0),
      ),
      ReportRange.lastThreeMonths => (
        DateTime(today.year, today.month - 2),
        DateTime(today.year, today.month + 1, 0),
      ),
      ReportRange.thisYear => (
        DateTime(today.year),
        DateTime(today.year, 12, 31),
      ),
      ReportRange.everything => (earliest ?? DateTime(today.year - 5), today),
      ReportRange.custom => (
        customFrom ?? DateTime(today.year, today.month),
        customTo ?? today,
      ),
    };
    return ReportRequest(
      template: template,
      from: from,
      to: to,
      label: periodLabel(from, to),
    );
  }

  /// Shared with [ReportData], which uses it a second time to name the
  /// comparison period on "the change" -- the two must read in the same
  /// voice, or a report that talks about itself in two dialects reads as a
  /// bug.
  static String periodLabel(DateTime from, DateTime to) {
    final sameMonth = from.year == to.year && from.month == to.month;
    if (sameMonth) return DateFormat('MMMM yyyy').format(from);
    if (from.year == to.year) {
      return '${DateFormat('MMM').format(from)} – '
          '${DateFormat('MMM yyyy').format(to)}';
    }
    return '${DateFormat('MMM yyyy').format(from)} – '
        '${DateFormat('MMM yyyy').format(to)}';
  }
}

/// Received, spent and moved, plus the two rankings every template draws
/// from. Factored out because "the change" needs this shape twice -- once
/// for the period asked for, once for the one before it -- and a report
/// disagreeing with itself about how a category total is computed is worse
/// than the duplication it would take to avoid this.
class _Totals {
  const _Totals({
    required this.received,
    required this.spent,
    required this.moved,
    required this.byCategory,
    required this.byMerchant,
  });

  final int received;
  final int spent;
  final int moved;
  final List<MapEntry<String, int>> byCategory;
  final List<MapEntry<String, int>> byMerchant;

  static _Totals of(List<TransactionViewData> items) {
    var received = 0, spent = 0, moved = 0;
    final categories = <String, int>{};
    final merchants = <String, int>{};
    for (final item in items) {
      // Lending, being repaid, and holding money for somebody else move an
      // account without being spending or income. The ledger already knows
      // which those are, and Home and Insights both leave them out; this did
      // not, so a month in which money passed through on its way to a
      // relative reported it as income on arrival and as spending on the way
      // out, and "Transfer" could outrank every real category on the page.
      if (item.isLoanMovement) continue;
      final amount = item.amount.minorUnits.abs();
      switch (item.kind) {
        case TransactionKind.income:
          received += amount;
        case TransactionKind.expense:
          spent += amount;
          categories.update(
            item.category,
            (value) => value + amount,
            ifAbsent: () => amount,
          );
          merchants.update(
            item.title,
            (value) => value + amount,
            ifAbsent: () => amount,
          );
        case TransactionKind.transfer:
          moved += amount;
      }
    }
    List<MapEntry<String, int>> ranked(Map<String, int> source) =>
        source.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return _Totals(
      received: received,
      spent: spent,
      moved: moved,
      byCategory: ranked(categories),
      byMerchant: ranked(merchants),
    );
  }
}

/// The numbers a report is made of, computed once so every template agrees.
class ReportData {
  ReportData._({
    required this.request,
    required this.transactions,
    required this.receivedMinor,
    required this.spentMinor,
    required this.movedMinor,
    required this.byCategory,
    required this.byMerchant,
    required this.previousLabel,
    required this.previousReceivedMinor,
    required this.previousSpentMinor,
    required this.previousByCategory,
    required this.currency,
    required this.accounts,
  });

  final ReportRequest request;
  final List<TransactionViewData> transactions;
  final int receivedMinor;
  final int spentMinor;
  final int movedMinor;
  final List<MapEntry<String, int>> byCategory;
  final List<MapEntry<String, int>> byMerchant;

  /// How the equal-length period immediately before this one reads on the
  /// cover -- "August 2026" against "September 2026".
  final String previousLabel;
  final int previousReceivedMinor;
  final int previousSpentMinor;
  final List<MapEntry<String, int>> previousByCategory;

  final String currency;
  final List<AccountViewData> accounts;

  int get keptMinor => receivedMinor - spentMinor;

  double get keptFraction =>
      receivedMinor <= 0 ? 0 : (keptMinor / receivedMinor).clamp(0.0, 1.0);

  /// Positive: spent more than the period before. Negative: spent less.
  int get spentDeltaMinor => spentMinor - previousSpentMinor;

  /// Null when there is nothing from before to compare against, rather than
  /// a claimed "infinite" increase.
  double? get spentDeltaFraction =>
      previousSpentMinor <= 0 ? null : spentDeltaMinor / previousSpentMinor;

  bool get isEmpty => transactions.isEmpty;

  /// True when the register lists something the figures deliberately do not
  /// count, which is the moment the page owes the reader an explanation.
  bool get hasExcludedMovements => transactions.any(
    (item) => item.isLoanMovement || item.kind == TransactionKind.transfer,
  );

  static ReportData gather({
    required ReportRequest request,
    required List<TransactionViewData> transactions,
    required List<AccountViewData> accounts,
  }) {
    final to = DateTime(
      request.to.year,
      request.to.month,
      request.to.day,
      23,
      59,
      59,
    );
    final within = transactions.where((item) {
      final at = item.occurredAt.toLocal();
      return !at.isBefore(request.from) && !at.isAfter(to);
    }).toList()..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    // The comparison period is always the window of the same length
    // immediately before this one -- the same rule Insights uses for its own
    // period-over-period reading, so "did this get better" means one thing
    // across the app.
    final spanDays = to.difference(request.from).inDays + 1;
    final previousFrom = request.from.subtract(Duration(days: spanDays));
    final previousTo = request.from.subtract(const Duration(seconds: 1));
    final previousWithin = transactions.where((item) {
      final at = item.occurredAt.toLocal();
      return !at.isBefore(previousFrom) && !at.isAfter(previousTo);
    }).toList();

    final current = _Totals.of(within);
    final previous = _Totals.of(previousWithin);

    return ReportData._(
      request: request,
      transactions: within,
      receivedMinor: current.received,
      spentMinor: current.spent,
      movedMinor: current.moved,
      byCategory: current.byCategory,
      byMerchant: current.byMerchant,
      previousLabel: ReportRequest.periodLabel(previousFrom, previousTo),
      previousReceivedMinor: previous.received,
      previousSpentMinor: previous.spent,
      previousByCategory: previous.byCategory,
      currency: within.isEmpty ? 'PKR' : within.first.amount.currency,
      accounts: accounts,
    );
  }
}

/// One category's expenses for "the docket": every transaction that belongs
/// to it, and the subtotal that closes the group.
@immutable
class CategoryGroup {
  const CategoryGroup({
    required this.category,
    required this.totalMinor,
    required this.items,
  });

  final String category;
  final int totalMinor;
  final List<TransactionViewData> items;
}

/// Expenses only, grouped by category and ranked by subtotal -- income and
/// transfers do not belong on a claim. [transactions] is expected already
/// sorted (newest first, as [ReportData] leaves it), and that order survives
/// inside each group.
List<CategoryGroup> categoryGroups(List<TransactionViewData> transactions) {
  final order = <String>[];
  final items = <String, List<TransactionViewData>>{};
  for (final item in transactions) {
    if (item.kind != TransactionKind.expense) continue;
    final bucket = items.putIfAbsent(item.category, () {
      order.add(item.category);
      return [];
    });
    bucket.add(item);
  }
  final groups =
      order
          .map(
            (category) => CategoryGroup(
              category: category,
              totalMinor: items[category]!.fold<int>(
                0,
                (sum, item) => sum + item.amount.minorUnits.abs(),
              ),
              items: items[category]!,
            ),
          )
          .toList()
        ..sort((a, b) => b.totalMinor.compareTo(a.totalMinor));
  return groups;
}

/// One calendar month for "the almanac".
@immutable
class MonthBucket {
  const MonthBucket({
    required this.start,
    required this.receivedMinor,
    required this.spentMinor,
    required this.topCategory,
  });

  /// The first of the month, local time.
  final DateTime start;
  final int receivedMinor;
  final int spentMinor;

  /// The category that took the most that month, or null if nothing was
  /// spent.
  final String? topCategory;

  int get netMinor => receivedMinor - spentMinor;
}

/// Every calendar month the period touches, in order -- including a quiet
/// month with nothing in it, so a year still draws twelve tiles. [from] and
/// [to] are read to the month only; [transactions] should already be the
/// period's own (already date-filtered), as [ReportData.transactions] is.
List<MonthBucket> monthBuckets(
  DateTime from,
  DateTime to,
  List<TransactionViewData> transactions,
) {
  final months = <DateTime>[];
  var cursor = DateTime(from.year, from.month);
  final last = DateTime(to.year, to.month);
  while (!cursor.isAfter(last)) {
    months.add(cursor);
    cursor = DateTime(cursor.year, cursor.month + 1);
  }
  return months.map((month) {
    var received = 0, spent = 0;
    final categories = <String, int>{};
    for (final item in transactions) {
      final at = item.occurredAt.toLocal();
      if (at.year != month.year || at.month != month.month) continue;
      final amount = item.amount.minorUnits.abs();
      switch (item.kind) {
        case TransactionKind.income:
          received += amount;
        case TransactionKind.expense:
          spent += amount;
          categories.update(
            item.category,
            (value) => value + amount,
            ifAbsent: () => amount,
          );
        case TransactionKind.transfer:
          break;
      }
    }
    String? top;
    var topAmount = 0;
    for (final entry in categories.entries) {
      if (entry.value > topAmount) {
        top = entry.key;
        topAmount = entry.value;
      }
    }
    return MonthBucket(
      start: month,
      receivedMinor: received,
      spentMinor: spent,
      topCategory: top,
    );
  }).toList();
}

/// A dark-ground colour, re-lit for paper.
///
/// Every [SpendWisePalette] is tuned for contrast against
/// `SpendWiseColors.bg` -- near-black -- and several of the lighter members
/// (a pale sage, a light brass tan) read as a wash once the ground turns to
/// off-white paper, and a home printer's dot gain only lightens them further.
/// Capping lightness rather than rescaling every tone leaves whatever was
/// already dark enough alone, and a small saturation lift keeps a relit tone
/// from reading as merely greyed-out. The result is not the palette repainted
/// for a light theme -- it is the same hues, held to the darkness paper
/// actually needs.
PdfColor paperTone(Color source) {
  final hsl = HSLColor.fromColor(source);
  final lightness = math.min(hsl.lightness, 0.40);
  final saturation = (hsl.saturation * 1.25).clamp(0.0, 1.0);
  final relit = hsl.withLightness(lightness).withSaturation(saturation);
  return PdfColor.fromInt(relit.toColor().toARGB32());
}

/// Builds the PDF.
///
/// Deliberately printed rather than screenshotted: a report is shared and
/// often printed, so it sits on paper-white with graphite ink and spends the
/// palette's three tones only where they carry meaning. The typography is the
/// app's, so it still reads as the same product.
class SpendingReport {
  const SpendingReport({required this.palette, this.categoryOrder = const []});

  final SpendWisePalette palette;

  /// The ledger's own category list, in its own order.
  ///
  /// Threaded in so a category's tone and its channel number are decided the
  /// same way here as on the screen. Derived from the report's own contents
  /// instead, they would be stable across reprints of one report and nothing
  /// else -- the same category would answer to a different number next month,
  /// and to a third one on Insights.
  final List<String> categoryOrder;

  static const _paper = PdfColor.fromInt(0xFFFAF9F6);
  static const _ink = PdfColor.fromInt(0xFF17191A);
  static const _muted = PdfColor.fromInt(0xFF6B7176);
  static const _rule = PdfColor.fromInt(0xFFDFDDD6);

  /// One margin for every page of every template. The original had the
  /// register a few points tighter than the shape page it follows in "the
  /// statement" -- an arbitrary difference nothing asked for, and a report
  /// whose pages disagree about where the edge of the paper is reads as
  /// unfinished.
  static const _margin = pw.EdgeInsets.fromLTRB(48, 50, 48, 42);

  PdfColor get _keep => paperTone(palette.keep);
  PdfColor get _spend => paperTone(palette.spend);
  PdfColor get _mine => paperTone(palette.mine);

  Future<Uint8List> build(ReportData data) async {
    final sans = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Archivo-Regular.ttf'),
    );
    final sansBold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Archivo-Bold.ttf'),
    );
    final sansMedium = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Archivo-Medium.ttf'),
    );
    final mono = pw.Font.ttf(
      await rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf'),
    );

    final theme = pw.ThemeData.withFont(
      base: sans,
      bold: sansBold,
      italic: sans,
      boldItalic: sansBold,
    ).copyWith(defaultTextStyle: pw.TextStyle(font: sans, fontSize: 10));

    final document = pw.Document(
      title: 'SpendWise — ${data.request.label}',
      author: 'SpendWise',
      theme: theme,
    );

    final tones = CategoryTones(
      known: categoryOrder,
      present: data.byCategory.map((entry) => entry.key),
    );
    final paper = ReportPaper(
      data: data,
      sans: sans,
      bold: sansBold,
      mono: mono,
      ink: _ink,
      muted: _muted,
      rule: _rule,
      paper: _paper,
      keep: _keep,
      spend: _spend,
      mine: _mine,
      toneOf: (category) =>
          paperTone(SpendWiseColors.category(tones.slotOf(category))),
      channelOf: tones.channelOf,
      money: _money,
      width: PdfPageFormat.a4.width - _margin.left - _margin.right,
    );

    document.addPage(
      _document(
        data,
        paper,
        _heroFor(data.request.template),
        sansBold,
        sansMedium,
        mono,
      ),
    );
    return document.save();
  }

  /// The drawing that opens the document.
  ReportHero _heroFor(ReportTemplate template) => switch (template) {
    ReportTemplate.ribbon => const RibbonHero(),
    ReportTemplate.dial => const DialHero(),
    ReportTemplate.desk => const DeskHero(),
    ReportTemplate.trace => const TraceHero(),
  };

  /// One document, whichever drawing opens it.
  ///
  /// Every template used to build its own pages, which is how the register
  /// came to sit a few points tighter than the page above it and how "the
  /// statement" ended up as two documents stapled together. The masthead, the
  /// margins, the running header and the colophon are the document's; the
  /// hero is the only thing that differs.
  pw.MultiPage _document(
    ReportData data,
    ReportPaper paper,
    ReportHero hero,
    pw.Font bold,
    pw.Font medium,
    pw.Font mono,
  ) => pw.MultiPage(
    pageTheme: _pageTheme(),
    header: (context) => context.pageNumber == 1
        ? _cover(data, bold, mono)
        : _continuationHeader(hero.template.title, data, bold, mono, context),
    footer: (context) => _colophon(mono),
    build: (context) => [
      ...hero.build(paper),
      if (data.transactions.isNotEmpty) ...[
        pw.SizedBox(height: 26),
        _eyebrow('Every entry', mono),
        pw.SizedBox(height: 10),
        ..._registerRows(data, medium, mono),
      ],
      // The register lists everything that moved; the figures above count
      // only what was earned or spent. Without this line the two disagree by
      // exactly the amount that was never anybody's, and the reader is left
      // to work out which of them is lying.
      if (data.hasExcludedMovements) ...[
        pw.SizedBox(height: 18),
        _footnote(
          'Figures above exclude moves between your own accounts, and money '
          'lent, borrowed or held for someone else. Those entries are still '
          'listed, because the money really did move.',
          mono,
        ),
      ],
    ],
  );

  // ---- shared page furniture -----------------------------------------------

  /// Paper edge to edge. Painting a filled box inside the margins instead
  /// leaves a visible rectangle of white around it.
  pw.PageTheme _pageTheme() => pw.PageTheme(
    pageFormat: PdfPageFormat.a4,
    margin: _margin,
    buildBackground: (context) =>
        pw.FullPage(ignoreMargins: true, child: pw.Container(color: _paper)),
  );

  /// The masthead, plus the gap every template gives it before its own
  /// content starts. Used as page one's header on every multi-page template,
  /// so a template that spills past a single page still opens the same way.
  pw.Widget _cover(ReportData data, pw.Font bold, pw.Font mono) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [_masthead(data, bold, mono), pw.SizedBox(height: 26)],
  );

  /// The slim header a template falls back to once it runs past its first
  /// page: a title, the period, and a page count -- the same shape the
  /// register has always used, now shared so a fourth template does not
  /// reinvent it a fourth time.
  pw.Widget _continuationHeader(
    String title,
    ReportData data,
    pw.Font bold,
    pw.Font mono,
    pw.Context context,
  ) => pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 14),
    padding: const pw.EdgeInsets.only(bottom: 8),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 1.2)),
    ),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            '$title · ${data.request.label}',
            style: pw.TextStyle(font: bold, fontSize: 12, color: _ink),
          ),
        ),
        pw.Text(
          '${context.pageNumber} / ${context.pagesCount}',
          style: pw.TextStyle(font: mono, fontSize: 7.5, color: _muted),
        ),
      ],
    ),
  );

  pw.Widget _masthead(ReportData data, pw.Font bold, pw.Font mono) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 25,
            height: 29,
            child: pw.CustomPaint(painter: _paintMark),
          ),
          pw.SizedBox(width: 13),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  data.request.label,
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 30,
                    color: _ink,
                    letterSpacing: -1,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'SpendWise · ${data.transactions.length} '
                  '${data.transactions.length == 1 ? 'entry' : 'entries'} '
                  '· ${data.currency}',
                  style: pw.TextStyle(
                    font: mono,
                    fontSize: 8,
                    color: _muted,
                    letterSpacing: .8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 16),
      pw.Container(height: 1.6, color: _ink),
    ],
  );

  pw.Widget _eyebrow(String text, pw.Font mono) => pw.Text(
    text.toUpperCase(),
    style: pw.TextStyle(
      font: mono,
      fontSize: 7.5,
      color: _muted,
      letterSpacing: 2,
    ),
  );

  pw.Widget _footnote(String text, pw.Font mono) => pw.Text(
    text,
    style: pw.TextStyle(font: mono, fontSize: 7.5, color: _muted, height: 1.5),
  );

  pw.Widget _colophon(pw.Font mono) => pw.Container(
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: _rule)),
    ),
    padding: const pw.EdgeInsets.only(top: 9),
    child: pw.Text(
      'Generated on this device from your local ledger. '
      'SpendWise has no account, cloud, or analytics.',
      style: pw.TextStyle(
        font: mono,
        fontSize: 7,
        color: _muted,
        letterSpacing: .6,
      ),
    ),
  );

  // ---- the shape ------------------------------------------------------

  // ---- the register (part of "the statement") -----------------------------

  /// The ledger itself, day by day, beneath whichever drawing opened the
  /// page. Returned as rows rather than as its own document so it flows on
  /// from the hero instead of restarting the paper.
  List<pw.Widget> _registerRows(ReportData data, pw.Font medium, pw.Font mono) {
    final rows = <pw.Widget>[];
    DateTime? lastDay;
    for (final item in data.transactions) {
      final at = item.occurredAt.toLocal();
      final day = DateTime(at.year, at.month, at.day);
      final row = _registerRow(item, medium, mono);
      if (day != lastDay) {
        lastDay = day;
        // Glued to the day's first row, so a break can only ever fall
        // between two transactions -- never between a date and the one
        // entry it was naming.
        rows.add(
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [_registerDayHeader(day, mono), row],
            ),
          ),
        );
      } else {
        rows.add(row);
      }
    }

    return rows;
  }

  pw.Widget _registerDayHeader(DateTime day, pw.Font mono) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 13, bottom: 5),
    child: pw.Row(
      children: [
        pw.Text(
          DateFormat('EEE dd MMM').format(day).toUpperCase(),
          style: pw.TextStyle(
            font: mono,
            fontSize: 7.5,
            color: _muted,
            letterSpacing: 1.4,
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(child: pw.Container(height: .6, color: _rule)),
      ],
    ),
  );

  pw.Widget _registerRow(
    TransactionViewData item,
    pw.Font medium,
    pw.Font mono,
  ) {
    final tone = switch (item.kind) {
      TransactionKind.income => _keep,
      TransactionKind.transfer => _mine,
      TransactionKind.expense => _spend,
    };
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _rule, width: .5)),
      ),
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 5,
            child: pw.Row(
              children: [
                // A drawn marker, because the arrows glyph is not in
                // Archivo and renders as a tofu box.
                if (item.kind == TransactionKind.transfer) ...[
                  pw.Container(width: 5, height: 5, color: _mine),
                  pw.SizedBox(width: 6),
                ],
                pw.Expanded(
                  child: pw.Text(
                    item.title,
                    maxLines: 1,
                    style: pw.TextStyle(fontSize: 9.5, color: _ink),
                  ),
                ),
              ],
            ),
          ),
          pw.Expanded(
            flex: 4,
            child: pw.Text(
              [
                item.category,
                if (item.accountName.isNotEmpty) item.accountName,
              ].join(' · ').toUpperCase(),
              maxLines: 1,
              style: pw.TextStyle(
                font: mono,
                fontSize: 6.8,
                color: _muted,
                letterSpacing: .5,
              ),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              _money(item.amount.minorUnits.abs()),
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(font: medium, fontSize: 9.5, color: tone),
            ),
          ),
        ],
      ),
    );
  }

  // ---- the change -----------------------------------------------------

  // ---- the docket -------------------------------------------------------

  // ---- the almanac ------------------------------------------------------

  // ---- drawing ------------------------------------------------------------

  /// The Split mark: one band in, a wide kept mass and a thin spent thread
  /// out. Authored on a 64-unit grid spanning x 10..52 and y 8..56, so it is
  /// fitted to the box rather than scaled off one axis.
  void _paintMark(PdfGraphics canvas, PdfPoint size) {
    final scale = (size.x / 42) < (size.y / 48) ? size.x / 42 : size.y / 48;
    final dx = (size.x - 42 * scale) / 2;
    final dy = (size.y - 48 * scale) / 2;
    double x(double value) => dx + (value - 10) * scale;
    // The PDF origin is bottom-left; the mark was authored top-down.
    double y(double value) => size.y - dy - (value - 8) * scale;

    canvas
      ..setFillColor(_ink)
      ..moveTo(x(24), y(8))
      ..lineTo(x(24), y(20))
      ..curveTo(x(24), y(34), x(10), y(40), x(10), y(56))
      ..lineTo(x(22), y(56))
      ..curveTo(x(22), y(40), x(36), y(34), x(36), y(20))
      ..lineTo(x(36), y(8))
      ..closePath()
      ..fillPath()
      ..setFillColor(_spend)
      ..moveTo(x(36), y(8))
      ..lineTo(x(36), y(20))
      ..curveTo(x(36), y(34), x(49), y(40), x(49), y(56))
      ..lineTo(x(52), y(56))
      ..curveTo(x(52), y(40), x(39), y(34), x(39), y(20))
      ..lineTo(x(39), y(8))
      ..closePath()
      ..fillPath();
  }

  /// Grouped, and without the trailing `.00` that makes a column of round
  /// figures harder to scan than it needs to be. Handed to every hero through
  /// `ReportPaper.money`, so the document cannot disagree with its own figure
  /// about how a number is written.
  static String _money(int minorUnits) {
    final value = (minorUnits.abs() / 100).toStringAsFixed(2);
    final parts = value.split('.');
    final grouped = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return parts.last == '00' ? grouped : '$grouped.${parts.last}';
  }
}
