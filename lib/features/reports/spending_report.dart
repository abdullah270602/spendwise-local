import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../app/palette.dart';
import '../shell/spendwise_view_model.dart';

/// How much of the ledger a report covers.
enum ReportRange { thisMonth, lastThreeMonths, thisYear, everything, custom }

/// What the report looks like. Two shapes, because the two reasons anyone
/// wants a PDF are "show someone the shape of my month" and "give me the
/// actual list on paper".
enum ReportTemplate {
  /// One page. The month as a picture: what arrived, what stayed, what went,
  /// and where. Nothing you would not want to hand to somebody.
  shape,

  /// The summary, then every transaction, day by day. Runs to as many pages
  /// as the period needs.
  statement,
}

extension ReportTemplateCopy on ReportTemplate {
  String get title => switch (this) {
    ReportTemplate.shape => 'The shape',
    ReportTemplate.statement => 'The statement',
  };

  String get blurb => switch (this) {
    ReportTemplate.shape =>
      'One page. What came in, what stayed, where the rest went.',
    ReportTemplate.statement =>
      'The summary, then every transaction, day by day.',
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
      label: _label(from, to),
    );
  }

  static String _label(DateTime from, DateTime to) {
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

/// The numbers a report is made of, computed once so both templates agree.
class ReportData {
  ReportData._({
    required this.request,
    required this.transactions,
    required this.receivedMinor,
    required this.spentMinor,
    required this.movedMinor,
    required this.byCategory,
    required this.byMerchant,
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
  final String currency;
  final List<AccountViewData> accounts;

  int get keptMinor => receivedMinor - spentMinor;

  double get keptFraction =>
      receivedMinor <= 0 ? 0 : (keptMinor / receivedMinor).clamp(0.0, 1.0);

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

    var received = 0, spent = 0, moved = 0;
    final categories = <String, int>{};
    final merchants = <String, int>{};
    for (final item in within) {
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

    return ReportData._(
      request: request,
      transactions: within,
      receivedMinor: received,
      spentMinor: spent,
      movedMinor: moved,
      byCategory: ranked(categories),
      byMerchant: ranked(merchants),
      currency: within.isEmpty ? 'PKR' : within.first.amount.currency,
      accounts: accounts,
    );
  }
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

  PdfColor get _keep => PdfColor.fromInt(palette.keep.toARGB32());
  PdfColor get _spend => PdfColor.fromInt(palette.spend.toARGB32());
  PdfColor get _mine => PdfColor.fromInt(palette.mine.toARGB32());

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
        document.addPage(_shapePage(data, sansBold, sansMedium, mono));
      case ReportTemplate.statement:
        document.addPage(_shapePage(data, sansBold, sansMedium, mono));
        document.addPage(_registerPages(data, sansBold, sansMedium, mono));
    }
    return document.save();
  }

  // ---- page one: the shape ------------------------------------------------

  /// Paper edge to edge. Painting a filled box inside the margins instead
  /// leaves a visible rectangle of white around it.
  pw.PageTheme _pageTheme(pw.EdgeInsets margin) => pw.PageTheme(
    pageFormat: PdfPageFormat.a4,
    margin: margin,
    buildBackground: (context) =>
        pw.FullPage(ignoreMargins: true, child: pw.Container(color: _paper)),
  );

  pw.Page _shapePage(
    ReportData data,
    pw.Font bold,
    pw.Font medium,
    pw.Font mono,
  ) => pw.Page(
    pageTheme: _pageTheme(const pw.EdgeInsets.fromLTRB(48, 52, 48, 44)),
    build: (context) => pw.Padding(
      padding: pw.EdgeInsets.zero,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _masthead(data, bold, mono),
          pw.SizedBox(height: 30),
          if (data.isEmpty)
            _nothing(bold)
          else ...[
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
            _categories(data, bold, medium, mono),
            pw.SizedBox(height: 26),
            _dailySpine(data, medium, mono),
            pw.Spacer(),
            _merchants(data, medium, mono),
          ],
          pw.SizedBox(height: 18),
          _colophon(mono),
        ],
      ),
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

  pw.Widget _nothing(pw.Font bold) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Nothing moved in this period.',
        style: pw.TextStyle(font: bold, fontSize: 17, color: _ink),
      ),
      pw.SizedBox(height: 8),
      pw.Text(
        'No transactions fall inside these dates.',
        style: const pw.TextStyle(fontSize: 10, color: _muted),
      ),
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

  // ---- the register -------------------------------------------------------

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
      if (day != lastDay) {
        lastDay = day;
        rows.add(
          pw.Padding(
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
          ),
        );
      }
      final tone = switch (item.kind) {
        TransactionKind.income => _keep,
        TransactionKind.transfer => _mine,
        TransactionKind.expense => _spend,
      };
      rows.add(
        pw.Container(
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
        ),
      );
    }

    return pw.MultiPage(
      pageTheme: _pageTheme(const pw.EdgeInsets.fromLTRB(48, 46, 48, 40)),
      header: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 14),
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 1.2)),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                'The register · ${data.request.label}',
                style: pw.TextStyle(font: bold, fontSize: 12, color: _ink),
              ),
            ),
            pw.Text(
              '${context.pageNumber} / ${context.pagesCount}',
              style: pw.TextStyle(font: mono, fontSize: 7.5, color: _muted),
            ),
          ],
        ),
      ),
      build: (context) => rows,
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
      PdfColor.fromInt(palette.ramp[index % palette.ramp.length].toARGB32());

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
