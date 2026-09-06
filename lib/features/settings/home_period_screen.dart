import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/chooser_kit.dart';
import '../../widgets/shape_kit.dart';
import '../dashboard/home_preview.dart';
import '../dashboard/home_savings.dart';
import '../shell/spendwise_view_model.dart';

/// Choosing what stretch of time Home is a picture of.
///
/// Every option used to carry its own miniature set of figures, which made a
/// wall of numbers to read before you could choose anything. One preview
/// answers the question better: pick a window and watch Home become that
/// window, including the case that matters most -- the one where the window
/// you picked contains no income and the proportion means nothing.
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

  void _choose(HomePeriod period) {
    widget.viewModel.uiSetHomePeriod(period);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final viewModel = widget.viewModel;
    final current = viewModel.uiHomePeriod;
    final figures = homeFigures(viewModel, now: now);
    final options = <HomePeriod>[
      HomePeriod.calendarMonth,
      HomePeriod.lastThirtyDays,
      HomePeriod.lastFourteenDays,
      HomePeriod.lastSevenDays,
      HomePeriod(
        kind: HomePeriodKind.dayRange,
        startDay: startDay,
        endDay: endDay,
      ),
    ];

    return ChooserScreen(
      title: 'How much time Home shows',
      preview: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomePreview(
            figures: figures,
            style: HomeSavingsStyle.fromId(
              viewModel.uiViewPreference('home_savings'),
            ),
            extra: HomeSavingsExtra.resolve(
              viewModel.uiViewPreference('home_savings_extra'),
              viewModel.uiViewPreference('home_savings'),
              legacyOn: viewModel.uiShowSavingsOnHome,
            ),
            label: current.label(now),
          ),
          if (figures.received == 0) ...[
            const SizedBox(height: 12),
            Text(
              'Nothing arrived in this window, so there is no proportion to '
              'show. Pick one that contains a payday.',
              style: SpendWiseType.body.copyWith(
                fontSize: 12.5,
                color: SpendWiseColors.spend,
              ),
            ),
          ],
        ],
      ),
      children: [
        ChoiceGroup(
          label: 'The window',
          caption: 'Match it to when you get paid.',
          first: true,
          children: [
            for (final option in options) ...[
              ChoiceRow(
                title: option.title,
                detail: option.blurb,
                selected: option == current,
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
      ],
    );
  }
}

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
