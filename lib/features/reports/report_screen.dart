import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../shell/spendwise_view_model.dart';
import '../insights/insights_layout.dart';
import 'report_hero.dart';
import 'spending_report.dart';

/// Pick a period, pick a shape, get a PDF.
///
/// Everything happens on the device: the ledger is already here, the fonts are
/// bundled, and the file goes wherever the user says. Nothing is uploaded to
/// render it, which is the only way a report is consistent with the rest of
/// the app's promise.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  static const _templateKey = 'report_template';

  ReportRange range = ReportRange.thisMonth;
  late ReportTemplate template;
  DateTimeRange? custom;
  bool working = false;

  @override
  void initState() {
    super.initState();
    // Remembered like the palette is: the shape of report someone wants
    // rarely changes month to month, so asking again every time would just
    // be the same tap repeated forever.
    //
    // Unset, it follows Insights rather than falling back to a house
    // default. Someone who reads their spending as a dial should be handed a
    // dial without being asked the same question twice in two places.
    final saved = widget.viewModel.uiViewPreference(_templateKey);
    template = saved != null
        ? ReportTemplate.fromId(saved)
        : _matchingInsights(widget.viewModel);
  }

  /// The template that draws what Insights is already drawing.
  ///
  /// "What changed" wins over the breakdown when both are on, because it is
  /// the one somebody turned on deliberately -- it is off until asked for.
  static ReportTemplate _matchingInsights(SpendWiseViewModel viewModel) {
    final change = InsightsChange.fromId(
      viewModel.uiViewPreference(InsightsPreference.change),
    );
    if (change == InsightsChange.seismograph) return ReportTemplate.trace;
    return switch (InsightsShare.fromId(
      viewModel.uiViewPreference(InsightsPreference.share),
    )) {
      InsightsShare.chronograph => ReportTemplate.dial,
      InsightsShare.mixingDesk => ReportTemplate.desk,
      InsightsShare.bars || InsightsShare.off => ReportTemplate.ribbon,
    };
  }

  @override
  Widget build(BuildContext context) {
    final request = _request();
    final data = ReportData.gather(
      request: request,
      transactions: widget.viewModel.transactions,
      accounts: widget.viewModel.accounts,
      debts: widget.viewModel.uiDebts,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Spending report')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          SpendWiseTheme.gutter,
          8,
          SpendWiseTheme.gutter,
          48 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          Text(
            'A PDF of what your money did, built on this device.',
            style: SpendWiseType.body.copyWith(fontSize: 13.5),
          ),
          const SizedBox(height: 26),
          const Eyebrow('Period'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in ReportRange.values)
                ChoiceChip(
                  label: Text(
                    option == ReportRange.custom && custom != null
                        ? _customLabel(custom!)
                        : option.title,
                  ),
                  selected: range == option,
                  onSelected: (_) => _chooseRange(option),
                ),
            ],
          ),
          const SizedBox(height: 26),
          const Eyebrow('Template'),
          const SizedBox(height: 10),
          for (final option in ReportTemplate.values)
            _TemplateTile(
              template: option,
              selected: template == option,
              onTap: () => _chooseTemplate(option),
            ),
          const SizedBox(height: 26),
          _Preview(data: data),
          const SizedBox(height: 22),
          PrimaryAction(
            label: data.isEmpty
                ? 'Nothing in this period'
                : 'Create ${request.label} report',
            busy: working,
            onPressed: data.isEmpty ? null : () => _create(data),
          ),
          const SizedBox(height: 14),
          Text(
            'The file is written where you choose it. SpendWise never sends it '
            'anywhere.',
            style: SpendWiseType.body.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }

  ReportRequest _request() => ReportRequest.forRange(
    range,
    template,
    customFrom: custom?.start,
    customTo: custom?.end,
    earliest: widget.viewModel.transactions.isEmpty
        ? null
        : widget.viewModel.transactions
              .map((item) => item.occurredAt.toLocal())
              .reduce((a, b) => a.isBefore(b) ? a : b),
  );

  void _chooseTemplate(ReportTemplate option) {
    widget.viewModel.uiSetViewPreference(_templateKey, option.name);
    setState(() => template = option);
  }

  Future<void> _chooseRange(ReportRange option) async {
    if (option != ReportRange.custom) {
      setState(() => range = option);
      return;
    }
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      initialDateRange:
          custom ??
          DateTimeRange(start: DateTime(now.year, now.month), end: now),
    );
    if (picked == null) return;
    setState(() {
      range = ReportRange.custom;
      custom = picked;
    });
  }

  Future<void> _create(ReportData data) async {
    setState(() => working = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await SpendingReport(
        palette: SpendWiseColors.palette,
        // The ledger's own category order, so a category is the same
        // colour and answers to the same channel number on paper as it
        // does on the screen this was opened from.
        categoryOrder: widget.viewModel.uiCategories
            .map((item) => item.name)
            .toList(),
      ).build(data);
      final name =
          'spendwise-${data.request.label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}.pdf';
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Save your spending report',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: bytes,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(saved == null ? 'Report discarded.' : 'Report saved.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not build the report: $error')),
      );
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  static String _customLabel(DateTimeRange value) =>
      '${DateFormat('d MMM').format(value.start)} – '
      '${DateFormat('d MMM').format(value.end)}';
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final ReportTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? SpendWiseColors.fg : SpendWiseColors.edge,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TemplateThumb(template: template),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(template.title, style: SpendWiseType.rowStrong),
                  const SizedBox(height: 3),
                  Text(
                    template.blurb,
                    style: SpendWiseType.body.copyWith(fontSize: 12.5),
                  ),
                ],
              ),
            ),
            if (selected)
              Text(
                '✓',
                style: TextStyle(color: SpendWiseColors.keep, fontSize: 16),
              ),
          ],
        ),
      ),
    ),
  );
}

/// A page-shaped hint of what comes out, drawn rather than screenshotted so it
/// stays right when the palette changes.
class _TemplateThumb extends StatelessWidget {
  const _TemplateThumb({required this.template});

  final ReportTemplate template;

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 54,
    padding: const EdgeInsets.all(5),
    color: const Color(0xFFFAF9F6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 22, height: 3, color: const Color(0xFF17191A)),
        const SizedBox(height: 4),
        Expanded(child: _body),
      ],
    ),
  );

  /// A miniature of the drawing itself, not a symbol standing in for it.
  /// The point of choosing here is recognising the figure you already read on
  /// Insights, which a generic icon would defeat.
  Widget get _body => switch (template) {
    // The ribbon: what came in, splitting into what stayed and what left.
    ReportTemplate.ribbon => Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(flex: 7, child: Container(color: SpendWiseColors.keep)),
        const SizedBox(width: 2),
        Expanded(
          flex: 3,
          child: FractionallySizedBox(
            heightFactor: .5,
            alignment: Alignment.bottomCenter,
            child: Container(color: SpendWiseColors.spend),
          ),
        ),
      ],
    ),
    // The dial: markers on a rim, longest at twelve o'clock.
    ReportTemplate.dial => Center(
      child: SizedBox.square(
        dimension: 30,
        child: CustomPaint(painter: _DialThumb()),
      ),
    ),
    // The desk: a fader per channel, each at its own level.
    ReportTemplate.desk => Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final level in const [.9, .55, .75, .3, .62, .45])
          Container(
            width: 3,
            height: 26 * level,
            color: SpendWiseColors.spend.withValues(alpha: .55 + level * .45),
          ),
      ],
    ),
    // The trace: one line, pulled aside at each category.
    ReportTemplate.trace => Center(
      child: SizedBox(
        width: 26,
        height: 30,
        child: CustomPaint(painter: _TraceThumb()),
      ),
    ),
  };
}

/// What the report will say, before committing to a file.
class _Preview extends StatelessWidget {
  const _Preview({required this.data});

  final ReportData data;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(top: 14),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: SpendWiseColors.edge)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(
          'It will cover',
          trailing: Text(
            '${data.transactions.length} '
            '${data.transactions.length == 1 ? 'entry' : 'entries'}',
            style: SpendWiseType.eyebrow,
          ),
        ),
        const SizedBox(height: 12),
        if (data.isEmpty)
          Text(
            'No transactions fall inside these dates.',
            style: SpendWiseType.body.copyWith(fontSize: 13),
          )
        else
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'In',
                  value: formatMinor(data.receivedMinor, cents: false),
                  tone: SpendWiseColors.keep,
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'Out',
                  value: formatMinor(data.spentMinor, cents: false),
                  tone: SpendWiseColors.spend,
                ),
              ),
              if (data.movedMinor > 0)
                Expanded(
                  child: _Stat(
                    label: 'Moved',
                    value: formatMinor(data.movedMinor, cents: false),
                    tone: SpendWiseColors.mine,
                  ),
                ),
            ],
          ),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.tone});

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Eyebrow(label),
      const SizedBox(height: 3),
      Text(
        value,
        style: SpendWiseType.rowStrong.copyWith(fontSize: 16, color: tone),
      ),
    ],
  );
}

/// Six markers on a rim, longest first, read clockwise from the top -- the
/// dial's own rule, at the size of a thumbnail.
class _DialThumb extends CustomPainter {
  static const _shares = [1.0, .78, .6, .46, .3, .2];

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final rim = size.width / 2 - 1;
    canvas.drawCircle(
      centre,
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = SpendWiseColors.edge,
    );
    for (var i = 0; i < _shares.length; i++) {
      final angle = -math.pi / 2 + i * (2 * math.pi / _shares.length);
      final inner = rim - 2 - _shares[i] * (rim * .55);
      canvas.drawLine(
        centre + Offset(math.cos(angle), math.sin(angle)) * (rim - 2),
        centre + Offset(math.cos(angle), math.sin(angle)) * inner,
        Paint()
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..color = SpendWiseColors.category(i),
      );
    }
  }

  @override
  bool shouldRepaint(_DialThumb oldDelegate) => false;
}

/// One continuous line leaving and returning to its centre, which is the
/// whole of the trace's idea.
class _TraceThumb extends CustomPainter {
  static const _deflections = [.35, -.6, .15, -.2, .8, -.35];

  @override
  void paint(Canvas canvas, Size size) {
    final centreX = size.width / 2;
    canvas.drawLine(
      Offset(centreX, 0),
      Offset(centreX, size.height),
      Paint()
        ..strokeWidth = 1
        ..color = SpendWiseColors.edge,
    );
    final path = Path()..moveTo(centreX, 0);
    final step = size.height / _deflections.length;
    for (var i = 0; i < _deflections.length; i++) {
      final top = i * step;
      final x = centreX + _deflections[i] * (size.width / 2 - 1);
      path
        ..cubicTo(
          centreX,
          top + step * .2,
          x,
          top + step * .25,
          x,
          top + step * .5,
        )
        ..cubicTo(
          x,
          top + step * .75,
          centreX,
          top + step * .8,
          centreX,
          top + step,
        );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeJoin = StrokeJoin.round
        ..color = SpendWiseColors.spend,
    );
  }

  @override
  bool shouldRepaint(_TraceThumb oldDelegate) => false;
}
