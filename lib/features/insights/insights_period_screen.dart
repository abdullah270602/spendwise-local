import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/chooser_kit.dart';
import '../../widgets/shape_kit.dart';
import '../shell/spendwise_view_model.dart';
import 'spending_analytics.dart';

/// How far back Insights looks.
///
/// This used to be a four-way segmented control in the screen's header, beside
/// the title. It never fitted: with the two day windows named honestly — "This
/// week", "This month" rather than "7 days" and "30 days" — the control wants
/// 424 logical pixels and a 360px phone has 316 to give it, and even the old
/// short labels overflowed by forty. Widening a phone is not an option, and
/// shrinking the words back would mean the screen says "30 days" over a figure
/// that covers a calendar month.
///
/// So it became a chooser, like every other question this app asks about how a
/// screen is drawn: one preview, held still, and the options that change it.
class InsightsPeriodScreen extends StatefulWidget {
  const InsightsPeriodScreen({
    super.key,
    required this.viewModel,
    required this.selected,
    required this.onSelected,
  });

  final SpendWiseViewModel viewModel;
  final AnalyticsResolution selected;
  final ValueChanged<AnalyticsResolution> onSelected;

  @override
  State<InsightsPeriodScreen> createState() => _InsightsPeriodScreenState();
}

class _InsightsPeriodScreenState extends State<InsightsPeriodScreen> {
  late AnalyticsResolution resolution = widget.selected;

  void _choose(AnalyticsResolution value) {
    if (value == resolution) return;
    setState(() => resolution = value);
    widget.onSelected(value);
  }

  @override
  Widget build(BuildContext context) {
    // Computed from the real ledger at the real resolution, so the preview
    // cannot describe a period the screen would then draw differently.
    final analytics = SpendingAnalytics.calculate(
      transactions: widget.viewModel.transactions,
      resolution: resolution,
    );

    return ChooserScreen(
      title: 'How far back Insights looks',
      preview: _PeriodPreview(analytics),
      children: [
        ChoiceGroup(
          label: 'The period you are in',
          caption:
              'Cut to the calendar, and compared against the same stretch of '
              'the one before.',
          first: true,
          children: [
            ChoiceRow(
              title: 'This week',
              detail: 'Monday to today, one bar a day',
              selected: resolution == AnalyticsResolution.thisWeek,
              onTap: () => _choose(AnalyticsResolution.thisWeek),
            ),
            ChoiceRow(
              title: 'This month',
              detail: 'The 1st to today, one bar a day',
              selected: resolution == AnalyticsResolution.thisMonth,
              onTap: () => _choose(AnalyticsResolution.thisMonth),
            ),
          ],
        ),
        ChoiceGroup(
          label: 'Further back',
          caption: 'History, grouped. One bar covers a whole month or year.',
          children: [
            ChoiceRow(
              title: 'Months',
              detail: 'The last twelve, against the same twelve last year',
              selected: resolution == AnalyticsResolution.months,
              onTap: () => _choose(AnalyticsResolution.months),
            ),
            ChoiceRow(
              title: 'Years',
              detail: 'Every year you have recorded',
              selected: resolution == AnalyticsResolution.years,
              onTap: () => _choose(AnalyticsResolution.years),
            ),
          ],
        ),
      ],
    );
  }
}

/// What the period actually changes: how many bars there are, and what they
/// add up to. Drawn from the same buckets the spine will draw, rather than an
/// illustration of them.
class _PeriodPreview extends StatelessWidget {
  const _PeriodPreview(this.analytics);

  final SpendingAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final buckets = analytics.buckets;
    final peak = buckets.fold<int>(
      1,
      (best, bucket) =>
          bucket.spendingMinor > best ? bucket.spendingMinor : best,
    );
    final cadence = analytics.resolution.cadence;
    final count = buckets.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(analytics.resolution.shortLabel),
        const SizedBox(height: 14),
        SizedBox(
          height: 72,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var index = 0; index < buckets.length; index++) ...[
                if (index > 0) const SizedBox(width: 2),
                Expanded(
                  child: Container(
                    // A day with nothing spent still gets a mark. A gap in the
                    // row would read as a day that is missing, not a quiet one.
                    height: buckets[index].spendingMinor == 0
                        ? 1
                        : 3 + (buckets[index].spendingMinor / peak) * 69,
                    color: index == buckets.length - 1
                        ? SpendWiseColors.spend
                        : SpendWiseColors.spend.withValues(alpha: .5),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${formatMinor(analytics.totalSpendingMinor, cents: false)} spent '
          'over $count ${count == 1 ? cadence : '${cadence}s'}',
          style: SpendWiseType.body.copyWith(
            fontSize: 12.5,
            color: SpendWiseColors.dim,
          ),
        ),
      ],
    );
  }
}
