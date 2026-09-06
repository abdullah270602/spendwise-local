import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../shell/spendwise_view_model.dart';
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
  ReportRange range = ReportRange.thisMonth;
  ReportTemplate template = ReportTemplate.shape;
  DateTimeRange? custom;
  bool working = false;

  @override
  Widget build(BuildContext context) {
    final request = _request();
    final data = ReportData.gather(
      request: request,
      transactions: widget.viewModel.transactions,
      accounts: widget.viewModel.accounts,
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
              onTap: () => setState(() => template = option),
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
      final bytes = await SpendingReport(palette: SpendWiseColors.palette)
          .build(data);
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
        if (template == ReportTemplate.shape) ...[
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 7,
                  child: Container(color: SpendWiseColors.keep),
                ),
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
          ),
          const SizedBox(height: 4),
          Container(width: 26, height: 2, color: const Color(0xFFDFDDD6)),
        ] else
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 7; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Container(
                      width: i.isEven ? 28 : 22,
                      height: 1.6,
                      color: i == 0
                          ? SpendWiseColors.spend
                          : const Color(0xFFDFDDD6),
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
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
