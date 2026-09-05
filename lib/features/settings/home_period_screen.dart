import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../shell/spendwise_view_model.dart';

/// Choosing what Home is a picture of.
///
/// Every option shows the figures it would actually produce from the ledger,
/// because the choice is only meaningful in terms of its denominator: "the
/// 1st to today" and "last 30 days" are abstractions until you can see that
/// one of them says you received nothing.
class HomePeriodScreen extends StatefulWidget {
  const HomePeriodScreen({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<HomePeriodScreen> createState() => _HomePeriodScreenState();
}

class _HomePeriodScreenState extends State<HomePeriodScreen> {
  late int startDay;
  late int endDay;

  @override
  void initState() {
    super.initState();
    final current = widget.viewModel.uiHomePeriod;
    startDay = current.kind == HomePeriodKind.dayRange ? current.startDay : 1;
    endDay = current.kind == HomePeriodKind.dayRange ? current.endDay : 0;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final current = widget.viewModel.uiHomePeriod;
    final options = <HomePeriod>[
      HomePeriod.calendarMonth,
      HomePeriod.lastThirtyDays,
      HomePeriod.lastSevenDays,
      HomePeriod(
        kind: HomePeriodKind.dayRange,
        startDay: startDay,
        endDay: endDay,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('What Home covers')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          SpendWiseTheme.gutter,
          8,
          SpendWiseTheme.gutter,
          48 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          Text(
            'Home answers one question: of everything that arrived, how much '
            'is still yours. That needs a stretch of time with money in it — '
            'so pick the one that matches when you get paid.',
            style: SpendWiseType.body.copyWith(fontSize: 13.5),
          ),
          const SizedBox(height: 24),
          for (final option in options) ...[
            _PeriodTile(
              period: option,
              now: now,
              selected: option == current,
              totals: _totalsFor(option, now),
              onTap: () => _choose(option),
            ),
            if (option.kind == HomePeriodKind.dayRange)
              _DayRangeEditor(
                startDay: startDay,
                endDay: endDay,
                onChanged: (start, end) {
                  setState(() {
                    startDay = start;
                    endDay = end;
                  });
                  if (current.kind == HomePeriodKind.dayRange) {
                    _choose(
                      HomePeriod(
                        kind: HomePeriodKind.dayRange,
                        startDay: start,
                        endDay: end,
                      ),
                    );
                  }
                },
              ),
          ],
        ],
      ),
    );
  }

  void _choose(HomePeriod period) {
    widget.viewModel.uiSetHomePeriod(period);
    setState(() {});
  }

  /// The same arithmetic Home does, run over a candidate window so the choice
  /// can be judged on its own numbers rather than its name.
  ({int received, int spent, int entries}) _totalsFor(
    HomePeriod period,
    DateTime now,
  ) {
    final (from, to) = period.resolve(now);
    var received = 0, spent = 0, entries = 0;
    for (final item in widget.viewModel.transactions) {
      final at = item.occurredAt.toLocal();
      if (at.isBefore(from) || !at.isBefore(to)) continue;
      if (item.isLoanMovement) continue;
      entries++;
      if (item.kind == TransactionKind.income) {
        received += item.amount.minorUnits.abs();
      } else if (item.kind == TransactionKind.expense) {
        spent += item.amount.minorUnits.abs();
      }
    }
    return (received: received, spent: spent, entries: entries);
  }
}

class _PeriodTile extends StatelessWidget {
  const _PeriodTile({
    required this.period,
    required this.now,
    required this.selected,
    required this.totals,
    required this.onTap,
  });

  final HomePeriod period;
  final DateTime now;
  final bool selected;
  final ({int received, int spent, int entries}) totals;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kept = totals.received - totals.spent;
    final hasIncome = totals.received > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(period.title, style: SpendWiseType.rowStrong),
                  ),
                  if (selected)
                    Text(
                      '✓',
                      style: TextStyle(
                        color: SpendWiseColors.keep,
                        fontSize: 16,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                period.blurb,
                style: SpendWiseType.body.copyWith(fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.only(top: 11),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: SpendWiseColors.line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow(
                      period.label(now),
                      trailing: Text(
                        '${totals.entries} '
                        '${totals.entries == 1 ? 'entry' : 'entries'}',
                        style: SpendWiseType.eyebrow,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!hasIncome)
                      // The whole reason this setting exists.
                      Text(
                        totals.spent == 0
                            ? 'Nothing at all in this window.'
                            : 'Nothing received in this window, so Home cannot '
                                  'show a share — only '
                                  '${formatMinor(totals.spent, cents: false)} '
                                  'spent.',
                        style: SpendWiseType.body.copyWith(
                          fontSize: 12.5,
                          color: SpendWiseColors.spend,
                        ),
                      )
                    else ...[
                      SegmentBar(
                        weights: [
                          kept < 0 ? 0.0 : kept / totals.received,
                          (kept < 0 ? 1.0 : totals.spent / totals.received)
                              .clamp(0.0, 1.0),
                        ],
                        colors: [
                          SpendWiseColors.keep,
                          SpendWiseColors.spend,
                        ],
                        height: 8,
                        gap: 2,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _Figure(
                              label: 'Received',
                              value: formatMinor(
                                totals.received,
                                cents: false,
                              ),
                              tone: SpendWiseColors.fg,
                            ),
                          ),
                          Expanded(
                            child: _Figure(
                              label: kept < 0 ? 'Overspent' : 'Still yours',
                              value: formatMinor(kept, cents: false),
                              tone: kept < 0
                                  ? SpendWiseColors.spend
                                  : SpendWiseColors.keep,
                            ),
                          ),
                          Expanded(
                            child: _Figure(
                              label: 'Gone',
                              value: formatMinor(totals.spent, cents: false),
                              tone: SpendWiseColors.spend,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Eyebrow(label),
      const SizedBox(height: 2),
      Text(
        value,
        style: SpendWiseType.rowStrong.copyWith(fontSize: 14, color: tone),
      ),
    ],
  );
}

/// Two dials for the pay-cycle window. The end day is optional, because the
/// common case is "my month starts when I get paid" rather than a window that
/// deliberately ignores the last few days.
class _DayRangeEditor extends StatelessWidget {
  const _DayRangeEditor({
    required this.startDay,
    required this.endDay,
    required this.onChanged,
  });

  final int startDay;
  final int endDay;
  final void Function(int startDay, int endDay) onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 14, bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Eyebrow('Starts on the'),
            const SizedBox(width: 10),
            _DayStepper(
              value: startDay,
              min: 1,
              max: 28,
              onChanged: (value) => onChanged(value, endDay),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Eyebrow('Ends on the'),
            const SizedBox(width: 10),
            _DayStepper(
              value: endDay,
              min: 0,
              max: 31,
              zeroLabel: 'today',
              onChanged: (value) => onChanged(startDay, value),
            ),
          ],
        ),
      ],
    ),
  );
}

class _DayStepper extends StatelessWidget {
  const _DayStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.zeroLabel,
  });

  final int value;
  final int min;
  final int max;
  final String? zeroLabel;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(border: Border.all(color: SpendWiseColors.edge)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Step(
          icon: Icons.remove_rounded,
          onTap: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 58,
          child: Text(
            value == 0 ? (zeroLabel ?? '0') : '$value',
            textAlign: TextAlign.center,
            style: SpendWiseType.rowStrong.copyWith(fontSize: 14),
          ),
        ),
        _Step(
          icon: Icons.add_rounded,
          onTap: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    ),
  );
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(9),
      child: Icon(
        icon,
        size: 16,
        color: onTap == null ? SpendWiseColors.line : SpendWiseColors.fg,
      ),
    ),
  );
}
