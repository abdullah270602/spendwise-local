import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart' show Color, HSLColor;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../app/palette.dart';
import '../shell/spendwise_view_model.dart';

/// How much of the ledger a report covers.
enum ReportRange { thisMonth, lastThreeMonths, thisYear, everything, custom }

/// What the report looks like. Five editorial takes on the same numbers,
/// because "a PDF of my spending" means different things to different
/// people: the shape of a month, the full list, how it moved against last
/// time, a claim ready to file, or a year read at a glance.
enum ReportTemplate {
  /// One page. What arrived, what stayed, what went, and where. Nothing you
  /// would not want to hand to somebody.
  shape,

  /// The summary, then every transaction, day by day. Runs to as many pages
  /// as the period needs.
  statement,

  /// This period against the one immediately before it, category by
  /// category. For the question "shape" cannot answer: did this get better?
  change,

  /// Every expense, grouped and subtotalled by category, like a claim ready
  /// to file rather than a diary of the month.
  docket,

  /// One tile per month, so a year -- or a decade -- reads at a glance.
  almanac,
}

extension ReportTemplateCopy on ReportTemplate {
  String get title => switch (this) {
    ReportTemplate.shape => 'The shape',
    ReportTemplate.statement => 'The statement',
    ReportTemplate.change => 'The change',
    ReportTemplate.docket => 'The docket',
    ReportTemplate.almanac => 'The almanac',
  };

  String get blurb => switch (this) {
    ReportTemplate.shape =>
      'One page. What came in, what stayed, where the rest went.',
    ReportTemplate.statement =>
      'The summary, then every transaction, day by day.',
    ReportTemplate.change =>
      'This period against the one before it, category by category.',
    ReportTemplate.docket =>
      'Every expense, grouped and subtotalled by category.',
    ReportTemplate.almanac =>
      'One tile per month, so a year reads at a glance.',
  };
}

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
  const SpendingReport({required this.palette});

  final SpendWisePalette palette;

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

    switch (data.request.template) {
      case ReportTemplate.shape:
        document.addPage(_shapeDocument(data, sansBold, sansMedium, mono));
      case ReportTemplate.statement:
        document.addPage(_shapeDocument(data, sansBold, sansMedium, mono));
        document.addPage(_registerPages(data, sansBold, sansMedium, mono));
      case ReportTemplate.change:
        document.addPage(_changeDocument(data, sansBold, sansMedium, mono));
      case ReportTemplate.docket:
        document.addPage(_docketPages(data, sansBold, sansMedium, mono));
      case ReportTemplate.almanac:
        document.addPage(_almanacPages(data, sansBold, sansMedium, mono));
    }
    return document.save();
  }

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

  pw.Widget _nothing(
    pw.Font bold, [
    String detail = 'No transactions fall inside these dates.',
  ]) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Nothing moved in this period.',
        style: pw.TextStyle(font: bold, fontSize: 17, color: _ink),
      ),
      pw.SizedBox(height: 8),
      pw.Text(detail, style: const pw.TextStyle(fontSize: 10, color: _muted)),
    ],
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

  /// A proportional bar drawn from flex ratios rather than fixed widths, so
  /// it holds its shape at any column width. Shared by "the change" and "the
  /// almanac", both of which pair two amounts against a common scale.
  pw.Widget _bar(int amountMinor, int maxMinor, PdfColor tone) {
    const total = 1000;
    final used = maxMinor <= 0
        ? 0
        : ((amountMinor / maxMinor) * total).round().clamp(0, total);
    return pw.Row(
      children: [
        if (used > 0)
          pw.Expanded(
            flex: used,
            child: pw.Container(height: 5, color: tone),
          ),
        if (used < total)
          pw.Expanded(flex: total - used, child: pw.SizedBox(height: 5)),
      ],
    );
  }

  // ---- the shape ------------------------------------------------------

  /// Built as a [pw.MultiPage] rather than a fixed [pw.Page]: the curation
  /// (top categories, top merchants, a bounded day count) keeps this to one
  /// page for almost every real period, but a fixed page does not clip
  /// overflow -- it draws past the margin box in page-absolute coordinates,
  /// which can push the masthead itself off the top of the sheet. A
  /// MultiPage instead spills onto a quiet second page, so a period unusual
  /// enough to overflow still prints something legible rather than
  /// something silently missing its top half.
  pw.MultiPage _shapeDocument(
    ReportData data,
    pw.Font bold,
    pw.Font medium,
    pw.Font mono,
  ) => pw.MultiPage(
    pageTheme: _pageTheme(),
    header: (context) => context.pageNumber == 1
        ? _cover(data, bold, mono)
        : _continuationHeader('The shape', data, bold, mono, context),
    footer: (context) => _colophon(mono),
    build: (context) => data.isEmpty
        ? [_nothing(bold)]
        : [
            _eyebrow('What happened to it', mono),
            pw.SizedBox(height: 10),
            pw.SizedBox(
              height: 150,
              width: double.infinity,
              child: pw.CustomPaint(
                painter: (canvas, size) => _paintFlow(canvas, size, data),
              ),
            ),
            pw.SizedBox(height: 14),
            _legend(data, bold, mono),
            pw.SizedBox(height: 30),
            // Inseparable, because a Column is spanning-capable by default in
            // this package: without it, a section that lands right on a page
            // boundary loses its eyebrow to the page above and its content
            // to the page below, rather than moving as one block.
            pw.Inseparable(child: _categories(data, bold, medium, mono)),
            pw.SizedBox(height: 26),
            pw.Inseparable(child: _dailySpine(data, medium, mono)),
            pw.SizedBox(height: 26),
            pw.Inseparable(child: _merchants(data, medium, mono)),
          ],
  );

  pw.Widget _legend(ReportData data, pw.Font bold, pw.Font mono) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: _figure(
          'Still yours',
          _money(data.keptMinor),
          data.receivedMinor > 0
              ? '${_percent(data.keptMinor, data.receivedMinor)} of what came in'
              : 'nothing came in',
          _ink,
          bold,
          mono,
        ),
      ),
      pw.Expanded(
        child: _figure(
          'Gone',
          _money(data.spentMinor),
          _percent(data.spentMinor, data.receivedMinor),
          _spend,
          bold,
          mono,
        ),
      ),
      if (data.movedMinor > 0)
        pw.Expanded(
          child: _figure(
            'Moved between your accounts',
            _money(data.movedMinor),
            'not counted as spending',
            _mine,
            bold,
            mono,
          ),
        ),
    ],
  );

  pw.Widget _figure(
    String label,
    String value,
    String note,
    PdfColor tone,
    pw.Font bold,
    pw.Font mono,
  ) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _eyebrow(label, mono),
      pw.SizedBox(height: 5),
      pw.Text(
        value,
        style: pw.TextStyle(
          font: bold,
          fontSize: 19,
          color: tone,
          letterSpacing: -.6,
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Text(note, style: pw.TextStyle(fontSize: 8.5, color: _muted)),
    ],
  );

  pw.Widget _categories(
    ReportData data,
    pw.Font bold,
    pw.Font medium,
    pw.Font mono,
  ) {
    if (data.byCategory.isEmpty) return pw.SizedBox();
    final total = data.byCategory.fold<int>(0, (sum, e) => sum + e.value);
    final shown = data.byCategory.take(8).toList();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _rule)),
          ),
          padding: const pw.EdgeInsets.only(top: 11),
          child: pw.Row(
            children: [
              pw.Expanded(child: _eyebrow('Where it went', mono)),
              _eyebrow('${data.byCategory.length} categories', mono),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
        pw.SizedBox(
          height: 22,
          child: pw.Row(
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) pw.SizedBox(width: 2),
                pw.Expanded(
                  flex: shown[i].value < 1 ? 1 : shown[i].value,
                  child: pw.Container(color: _ramp(i)),
                ),
              ],
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        for (var i = 0; i < shown.length; i++)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              children: [
                pw.Container(width: 7, height: 7, color: _ramp(i)),
                pw.SizedBox(width: 9),
                pw.Expanded(
                  child: pw.Text(
                    shown[i].key,
                    style: pw.TextStyle(fontSize: 10, color: _ink),
                  ),
                ),
                pw.Text(
                  _percent(shown[i].value, total),
                  style: pw.TextStyle(font: mono, fontSize: 8, color: _muted),
                ),
                pw.SizedBox(width: 14),
                pw.Text(
                  _money(shown[i].value),
                  style: pw.TextStyle(font: medium, fontSize: 10, color: _ink),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Every day of the period, in above the line and out below it. On a page
  /// this is what turns a summary into something you can actually read a month
  /// off -- where the salary landed, which weeks were heavy.
  pw.Widget _dailySpine(ReportData data, pw.Font medium, pw.Font mono) {
    final from = data.request.from;
    final days = data.request.to.difference(from).inDays + 1;
    if (days < 2 || days > 400) return pw.SizedBox();

    final incoming = List<int>.filled(days, 0);
    final outgoing = List<int>.filled(days, 0);
    for (final item in data.transactions) {
      final index = item.occurredAt.toLocal().difference(from).inDays;
      if (index < 0 || index >= days) continue;
      final amount = item.amount.minorUnits.abs();
      if (item.kind == TransactionKind.income) {
        incoming[index] += amount;
      } else if (item.kind == TransactionKind.expense) {
        outgoing[index] += amount;
      }
    }
    var peak = 1;
    for (var i = 0; i < days; i++) {
      peak = [peak, incoming[i], outgoing[i]].reduce((a, b) => a > b ? a : b);
    }
    if (peak <= 1) return pw.SizedBox();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _rule)),
          ),
          padding: const pw.EdgeInsets.only(top: 11),
          child: pw.Row(
            children: [
              pw.Expanded(child: _eyebrow('Day by day', mono)),
              _eyebrow('in above, out below', mono),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        pw.SizedBox(
          height: 92,
          width: double.infinity,
          child: pw.CustomPaint(
            painter: (canvas, size) =>
                _paintSpine(canvas, size, incoming, outgoing, peak),
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              DateFormat('d MMM').format(from),
              style: pw.TextStyle(font: mono, fontSize: 7, color: _muted),
            ),
            pw.Text(
              DateFormat('d MMM').format(data.request.to),
              style: pw.TextStyle(font: mono, fontSize: 7, color: _muted),
            ),
          ],
        ),
      ],
    );
  }

  void _paintSpine(
    PdfGraphics canvas,
    PdfPoint size,
    List<int> incoming,
    List<int> outgoing,
    int peak,
  ) {
    final days = incoming.length;
    final slot = size.x / days;
    final barW = slot > 3 ? slot * .62 : slot;
    final mid = size.y / 2;
    final arm = mid - 4;

    canvas
      ..setStrokeColor(_rule)
      ..setLineWidth(.7)
      ..drawLine(0, mid, size.x, mid)
      ..strokePath();

    for (var i = 0; i < days; i++) {
      final x = i * slot + (slot - barW) / 2;
      if (incoming[i] > 0) {
        final h = (incoming[i] / peak) * arm;
        canvas
          ..setFillColor(_keep)
          ..drawRect(x, mid + 1, barW, h < 1 ? 1 : h)
          ..fillPath();
      }
      if (outgoing[i] > 0) {
        final h = (outgoing[i] / peak) * arm;
        canvas
          ..setFillColor(_spend)
          ..drawRect(x, mid - 1 - (h < 1 ? 1 : h), barW, h < 1 ? 1 : h)
          ..fillPath();
      }
    }
  }

  pw.Widget _merchants(ReportData data, pw.Font medium, pw.Font mono) {
    if (data.byMerchant.length < 2) return pw.SizedBox();
    final shown = data.byMerchant.take(5).toList();
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _rule)),
      ),
      padding: const pw.EdgeInsets.only(top: 11),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _eyebrow('Most of it went to', mono),
          pw.SizedBox(height: 9),
          pw.Row(
            children: [
              for (final entry in shown)
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        entry.key,
                        maxLines: 2,
                        overflow: pw.TextOverflow.clip,
                        style: pw.TextStyle(fontSize: 8.5, color: _muted),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        _money(entry.value),
                        style: pw.TextStyle(
                          font: medium,
                          fontSize: 11,
                          color: _ink,
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

  // ---- the register (part of "the statement") -----------------------------

  pw.MultiPage _registerPages(
    ReportData data,
    pw.Font bold,
    pw.Font medium,
    pw.Font mono,
  ) {
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

    return pw.MultiPage(
      pageTheme: _pageTheme(),
      header: (context) =>
          _continuationHeader('The register', data, bold, mono, context),
      footer: (context) => _colophon(mono),
      build: (context) => rows.isEmpty ? [_nothing(bold)] : rows,
    );
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

  pw.MultiPage _changeDocument(
    ReportData data,
    pw.Font bold,
    pw.Font medium,
    pw.Font mono,
  ) {
    final current = {
      for (final entry in data.byCategory) entry.key: entry.value,
    };
    final previous = {
      for (final entry in data.previousByCategory) entry.key: entry.value,
    };
    final categories = {...current.keys, ...previous.keys}.toList()
      ..sort((a, b) => (current[b] ?? 0).compareTo(current[a] ?? 0));
    final maxAmount = categories.fold<int>(0, (peak, category) {
      final here = math.max(current[category] ?? 0, previous[category] ?? 0);
      return math.max(peak, here);
    });

    return pw.MultiPage(
      pageTheme: _pageTheme(),
      header: (context) => context.pageNumber == 1
          ? _cover(data, bold, mono)
          : _continuationHeader('The change', data, bold, mono, context),
      footer: (context) => _colophon(mono),
      build: (context) => data.isEmpty
          ? [_nothing(bold)]
          : [
              _eyebrow('Against ${data.previousLabel}', mono),
              pw.SizedBox(height: 12),
              _changeHeadline(data, bold, mono),
              pw.SizedBox(height: 28),
              if (categories.isEmpty)
                pw.Text(
                  'Nothing to compare it against.',
                  style: const pw.TextStyle(fontSize: 10, color: _muted),
                )
              else ...[
                // The header is glued to the first row -- on its own, a bare
                // "by category" label at the foot of a page promises a list
                // the next page hasn't started yet.
                pw.Inseparable(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(top: pw.BorderSide(color: _rule)),
                        ),
                        padding: const pw.EdgeInsets.only(top: 11, bottom: 12),
                        child: _eyebrow(
                          'By category, against ${data.previousLabel}',
                          mono,
                        ),
                      ),
                      _changeRow(
                        categories.first,
                        current[categories.first] ?? 0,
                        previous[categories.first] ?? 0,
                        maxAmount,
                        medium,
                        mono,
                      ),
                    ],
                  ),
                ),
                for (final category in categories.skip(1))
                  // See the shape's categories/spine/merchants: a bare
                  // Column can be split across a page boundary by this
                  // package, which would separate a category's name from
                  // its own bars.
                  pw.Inseparable(
                    child: _changeRow(
                      category,
                      current[category] ?? 0,
                      previous[category] ?? 0,
                      maxAmount,
                      medium,
                      mono,
                    ),
                  ),
              ],
            ],
    );
  }

  pw.Widget _changeHeadline(ReportData data, pw.Font bold, pw.Font mono) {
    final delta = data.spentDeltaMinor;
    final fraction = data.spentDeltaFraction;
    final tone = delta > 0 ? _spend : (delta < 0 ? _keep : _muted);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _figure(
            'Spent this period',
            _money(data.spentMinor),
            data.request.label,
            _ink,
            bold,
            mono,
          ),
        ),
        pw.Expanded(
          child: _figure(
            'Spent last time',
            _money(data.previousSpentMinor),
            data.previousLabel,
            _muted,
            bold,
            mono,
          ),
        ),
        pw.Expanded(
          child: _figure(
            'The difference',
            '${delta > 0
                ? '+'
                : delta < 0
                ? '−'
                : ''}${_money(delta.abs())}',
            fraction == null
                ? 'nothing to compare it against'
                : '${(fraction * 100).abs().toStringAsFixed(0)}% '
                      '${delta > 0
                          ? 'more'
                          : delta < 0
                          ? 'less'
                          : 'the same'}',
            tone,
            bold,
            mono,
          ),
        ),
      ],
    );
  }

  pw.Widget _changeRow(
    String category,
    int current,
    int previous,
    int maxAmount,
    pw.Font medium,
    pw.Font mono,
  ) {
    final delta = current - previous;
    final tone = delta > 0 ? _spend : (delta < 0 ? _keep : _muted);
    final percent = previous <= 0 ? null : (delta / previous) * 100;
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  category,
                  style: pw.TextStyle(fontSize: 10, color: _ink),
                ),
              ),
              pw.Text(
                _money(current),
                style: pw.TextStyle(font: medium, fontSize: 10, color: _ink),
              ),
              pw.SizedBox(width: 10),
              pw.SizedBox(
                width: 46,
                child: pw.Text(
                  percent == null
                      ? 'new'
                      : '${percent > 0 ? '+' : ''}${percent.toStringAsFixed(0)}%',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(font: mono, fontSize: 8, color: tone),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 5),
          _bar(previous, maxAmount, _muted),
          pw.SizedBox(height: 2),
          _bar(current, maxAmount, tone),
        ],
      ),
    );
  }

  // ---- the docket -------------------------------------------------------

  pw.MultiPage _docketPages(
    ReportData data,
    pw.Font bold,
    pw.Font medium,
    pw.Font mono,
  ) {
    final groups = categoryGroups(data.transactions);
    final total = groups.fold<int>(0, (sum, group) => sum + group.totalMinor);
    final count = groups.fold<int>(0, (sum, group) => sum + group.items.length);

    // A group's header names a category nobody has read the amount for yet,
    // and a subtotal means nothing once its last row is a page away -- each
    // is glued to its neighbour so a page break can only fall between two
    // whole transactions, never leave a heading or a total stranded alone.
    final rows = <pw.Widget>[];
    for (final group in groups) {
      final header = _docketGroupHeader(group, bold, mono);
      final items = group.items;
      if (items.length == 1) {
        rows.add(
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                header,
                _docketRow(items.first, medium, mono),
                _docketSubtotal(group, medium, mono),
              ],
            ),
          ),
        );
        continue;
      }
      rows.add(
        pw.Inseparable(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [header, _docketRow(items.first, medium, mono)],
          ),
        ),
      );
      for (final item in items.skip(1).take(items.length - 2)) {
        rows.add(_docketRow(item, medium, mono));
      }
      rows.add(
        pw.Inseparable(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _docketRow(items.last, medium, mono),
              _docketSubtotal(group, medium, mono),
            ],
          ),
        ),
      );
    }
    if (groups.isNotEmpty) {
      rows.add(pw.SizedBox(height: 10));
      rows.add(_docketGrandTotal(total, count, bold, mono));
    }

    return pw.MultiPage(
      pageTheme: _pageTheme(),
      header: (context) => context.pageNumber == 1
          ? _cover(data, bold, mono)
          : _continuationHeader('The docket', data, bold, mono, context),
      footer: (context) => _colophon(mono),
      build: (context) => rows.isEmpty
          ? [
              _nothing(
                bold,
                'No expenses fall inside these dates -- only income or '
                'transfers, which a docket does not itemise.',
              ),
            ]
          : rows,
    );
  }

  pw.Widget _docketGroupHeader(
    CategoryGroup group,
    pw.Font bold,
    pw.Font mono,
  ) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            group.category,
            style: pw.TextStyle(font: bold, fontSize: 11.5, color: _ink),
          ),
        ),
        pw.Text(
          '${group.items.length} ${group.items.length == 1 ? 'item' : 'items'}',
          style: pw.TextStyle(
            font: mono,
            fontSize: 7.5,
            color: _muted,
            letterSpacing: .8,
          ),
        ),
      ],
    ),
  );

  pw.Widget _docketRow(
    TransactionViewData item,
    pw.Font medium,
    pw.Font mono,
  ) => pw.Container(
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _rule, width: .5)),
    ),
    padding: const pw.EdgeInsets.symmetric(vertical: 5),
    child: pw.Row(
      children: [
        pw.SizedBox(
          width: 52,
          child: pw.Text(
            DateFormat('d MMM').format(item.occurredAt.toLocal()),
            style: pw.TextStyle(font: mono, fontSize: 8, color: _muted),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            item.title,
            maxLines: 1,
            style: pw.TextStyle(fontSize: 9.5, color: _ink),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.SizedBox(
          width: 92,
          child: pw.Text(
            item.accountName,
            maxLines: 1,
            textAlign: pw.TextAlign.right,
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(
              font: mono,
              fontSize: 7,
              color: _muted,
              letterSpacing: .3,
            ),
          ),
        ),
        pw.SizedBox(width: 10),
        pw.SizedBox(
          width: 62,
          child: pw.Text(
            _money(item.amount.minorUnits.abs()),
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(font: medium, fontSize: 9.5, color: _spend),
          ),
        ),
      ],
    ),
  );

  pw.Widget _docketSubtotal(
    CategoryGroup group,
    pw.Font medium,
    pw.Font mono,
  ) => pw.Container(
    padding: const pw.EdgeInsets.only(top: 5),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: _ink, width: .8)),
    ),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            'Subtotal',
            style: pw.TextStyle(
              font: mono,
              fontSize: 7.5,
              color: _muted,
              letterSpacing: .8,
            ),
          ),
        ),
        pw.Text(
          _money(group.totalMinor),
          style: pw.TextStyle(font: medium, fontSize: 10, color: _ink),
        ),
      ],
    ),
  );

  pw.Widget _docketGrandTotal(
    int total,
    int count,
    pw.Font bold,
    pw.Font mono,
  ) => pw.Container(
    padding: const pw.EdgeInsets.only(top: 10),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: _ink, width: 1.4)),
    ),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            '$count ${count == 1 ? 'expense' : 'expenses'} in total',
            style: const pw.TextStyle(fontSize: 10, color: _muted),
          ),
        ),
        pw.Text(
          _money(total),
          style: pw.TextStyle(font: bold, fontSize: 16, color: _spend),
        ),
      ],
    ),
  );

  // ---- the almanac ------------------------------------------------------

  pw.MultiPage _almanacPages(
    ReportData data,
    pw.Font bold,
    pw.Font medium,
    pw.Font mono,
  ) {
    final buckets = monthBuckets(
      data.request.from,
      data.request.to,
      data.transactions,
    );
    final peak = buckets.fold<int>(
      1,
      (top, bucket) =>
          math.max(top, math.max(bucket.receivedMinor, bucket.spentMinor)),
    );
    final rows = <pw.Widget>[
      for (var i = 0; i < buckets.length; i += 3)
        _almanacRow(buckets.skip(i).take(3).toList(), peak, bold, medium, mono),
    ];

    return pw.MultiPage(
      pageTheme: _pageTheme(),
      header: (context) => context.pageNumber == 1
          ? _cover(data, bold, mono)
          : _continuationHeader('The almanac', data, bold, mono, context),
      footer: (context) => _colophon(mono),
      build: (context) => rows.isEmpty ? [_nothing(bold)] : rows,
    );
  }

  pw.Widget _almanacRow(
    List<MonthBucket> slice,
    int peak,
    pw.Font bold,
    pw.Font medium,
    pw.Font mono,
  ) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 14),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) pw.SizedBox(width: 14),
          pw.Expanded(
            child: i < slice.length
                ? _almanacTile(slice[i], peak, bold, medium, mono)
                : pw.SizedBox(),
          ),
        ],
      ],
    ),
  );

  pw.Widget _almanacTile(
    MonthBucket bucket,
    int peak,
    pw.Font bold,
    pw.Font medium,
    pw.Font mono,
  ) {
    final tone = bucket.netMinor >= 0 ? _keep : _spend;
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _rule)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            DateFormat('MMM yyyy').format(bucket.start).toUpperCase(),
            style: pw.TextStyle(
              font: mono,
              fontSize: 7.5,
              color: _muted,
              letterSpacing: 1.4,
            ),
          ),
          pw.SizedBox(height: 7),
          pw.Text(
            _money(bucket.netMinor.abs()),
            style: pw.TextStyle(
              font: bold,
              fontSize: 15,
              color: tone,
              letterSpacing: -.4,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            bucket.netMinor >= 0 ? 'kept' : 'over',
            style: const pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
          pw.SizedBox(height: 8),
          _bar(bucket.receivedMinor, peak, _keep),
          pw.SizedBox(height: 2),
          _bar(bucket.spentMinor, peak, _spend),
          pw.SizedBox(height: 8),
          pw.Text(
            bucket.topCategory ?? 'no spending',
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(font: medium, fontSize: 8.5, color: _ink),
          ),
        ],
      ),
    );
  }

  // ---- drawing ------------------------------------------------------------

  /// The same ribbon as Home: one band in, a wide kept band and a thin spent
  /// thread out, to true proportion.
  void _paintFlow(PdfGraphics canvas, PdfPoint size, ReportData data) {
    final w = size.x;
    final h = size.y;
    const barH = 9.0;
    final topW = w * .44;
    final topX = (w - topW) / 2;
    final topY = h - barH;
    final botY = 2.0;
    final margin = w * .06;

    final keptW = topW * data.keptFraction;
    final spentW = topW - keptW;
    final splitX = topX + keptW;
    final keptBotX = margin;
    final spentBotX = w - margin - spentW;

    // PDF's origin is bottom-left, so "down the page" is decreasing y.
    final yTop = topY;
    final c1 = topY - (topY - botY - barH) * .42;
    final c2 = topY - (topY - botY - barH) * .60;
    final barTop = botY + barH;

    void ribbon(
      double aTop,
      double bTop,
      double aBot,
      double bBot,
      PdfColor colour,
      double opacity,
    ) {
      canvas
        ..setFillColor(colour)
        ..setGraphicState(PdfGraphicState(fillOpacity: opacity))
        ..moveTo(aTop, yTop)
        ..curveTo(aTop, c1, aBot, c2, aBot, barTop)
        ..lineTo(bBot, barTop)
        ..curveTo(bBot, c2, bTop, c1, bTop, yTop)
        ..closePath()
        ..fillPath()
        ..setGraphicState(const PdfGraphicState(fillOpacity: 1));
    }

    ribbon(topX, splitX, keptBotX, keptBotX + keptW, _keep, .34);
    ribbon(splitX, topX + topW, spentBotX, spentBotX + spentW, _spend, .5);

    canvas
      ..setFillColor(_ink)
      ..drawRect(topX, topY, topW, barH)
      ..fillPath()
      ..setFillColor(_keep)
      ..drawRect(keptBotX, botY, keptW, barH)
      ..fillPath()
      ..setFillColor(_spend)
      ..drawRect(spentBotX, botY, spentW, barH)
      ..fillPath();
  }

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

  PdfColor _ramp(int index) =>
      paperTone(palette.ramp[index % palette.ramp.length]);

  static String _money(int minorUnits) {
    final value = (minorUnits.abs() / 100).toStringAsFixed(2);
    final parts = value.split('.');
    final grouped = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return parts.last == '00' ? grouped : '$grouped.${parts.last}';
  }

  static String _percent(int part, int whole) {
    if (whole <= 0) return '0%';
    final value = (part / whole) * 100;
    return value < 10 && value > 0
        ? '${value.toStringAsFixed(1)}%'
        : '${value.round()}%';
  }
}
