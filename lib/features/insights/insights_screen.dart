import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/category_tones.dart';
import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../shell/spendwise_view_model.dart';
import 'chronograph.dart';
import 'gate.dart';
import 'insights_layout.dart';
import 'insights_period_screen.dart';
import 'insights_sections_screen.dart';
import 'mixing_desk.dart';
import 'seismograph.dart';
import 'spending_analytics.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  /// Remembered, like every other choice about how a screen is drawn.
  ///
  /// It was the one view preference the app forgot: `ledger_view`,
  /// `ledger_span`, `home_period`, `home_savings` and the report template all
  /// persist, and this reverted on every launch. Somebody who reads their
  /// spending by year had to say so again every time they opened the tab.
  ///
  /// The month you are in, all spending, is the question people arrive with,
  /// so it remains what an unset preference opens on.
  late AnalyticsResolution resolution;
  String? category;

  @override
  void initState() {
    super.initState();
    resolution = _resolutionFromId(
      widget.viewModel.uiViewPreference(InsightsPreference.period),
    );
  }

  /// Stored by name rather than by index, so reordering the enum cannot
  /// silently reinterpret somebody's saved choice as a different period.
  static AnalyticsResolution _resolutionFromId(String? id) {
    for (final value in AnalyticsResolution.values) {
      if (value.name == id) return value;
    }
    return AnalyticsResolution.thisMonth;
  }

  void _chooseResolution(AnalyticsResolution value) {
    setState(() => resolution = value);
    widget.viewModel.uiSetViewPreference(InsightsPreference.period, value.name);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.viewModel,
    builder: (context, _) {
      final analytics = SpendingAnalytics.calculate(
        transactions: widget.viewModel.transactions,
        resolution: resolution,
        category: category,
      );
      final categories =
          widget.viewModel.transactions
              // Debt movements are excluded from every figure on this screen,
              // so a category that only ever appears on one would offer a
              // chip that filters the screen down to nothing.
              .where(
                (item) =>
                    item.kind == TransactionKind.expense &&
                    !item.isLoanMovement,
              )
              .map((item) => item.category)
              .toSet()
              .toList()
            ..sort();
      // Keyed to the ledger's own order, so a category holds one colour from
      // one period to the next and Home agrees with this screen about which
      // colour it is.
      final tones = widget.viewModel.tonesFor(categories);
      // Three questions, three settings. What is drawn here is whatever the
      // reader has asked for, and nothing else.
      final overTime = InsightsOverTime.fromId(
        widget.viewModel.uiViewPreference(InsightsPreference.overTime),
      );
      final share = InsightsShare.fromId(
        widget.viewModel.uiViewPreference(InsightsPreference.share),
      );
      final change = InsightsChange.fromId(
        widget.viewModel.uiViewPreference(InsightsPreference.change),
      );
      void select(String? value) => setState(() => category = value);

      return SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SpendWiseTheme.gutter,
                16,
                SpendWiseTheme.gutter,
                12,
              ),
              child: Row(
                children: [
                  Expanded(child: Text('Insights', style: SpendWiseType.title)),
                  // The only choice left in the header is how far back to
                  // look. It was a four-way segmented control until the two
                  // day windows were named for what they are; "This week" and
                  // "This month" do not fit beside a title on a phone, and
                  // the old short labels did not either.
                  _PeriodButton(
                    label: resolution.shortLabel,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => InsightsPeriodScreen(
                          viewModel: widget.viewModel,
                          selected: resolution,
                          onSelected: _chooseResolution,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: widget.viewModel.transactions.isEmpty
                  ? const RestState(
                      headline: 'Nothing to compare yet.',
                      detail:
                          'Once transactions reach your ledger, this becomes '
                          'the whole history of money in and out — by day, '
                          'month, year, and category.',
                    )
                  : CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 46,
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: SpendWiseTheme.gutter,
                              ),
                              scrollDirection: Axis.horizontal,
                              itemCount: categories.length + 1,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final value = index == 0
                                    ? null
                                    : categories[index - 1];
                                return _CategoryFilter(
                                  label: value ?? 'All spending',
                                  selected: category == value,
                                  onTap: () => setState(() => category = value),
                                );
                              },
                            ),
                          ),
                        ),
                        if (overTime.isOn)
                          SliverToBoxAdapter(
                            child: FlowSpine(
                              buckets: analytics.buckets,
                              currency: analytics.currency,
                              spendingOnly: category != null,
                            ),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(
                            SpendWiseTheme.gutter,
                            18,
                            SpendWiseTheme.gutter,
                            36,
                          ),
                          sliver: SliverList.list(
                            children: [
                              // No balances here. Insights is about what money
                              // did over a period; what is left in each
                              // account is what Accounts is for, and saying it
                              // in both places let the two disagree in front
                              // of the user.
                              _SummaryBand(analytics, category: category),
                              const SizedBox(height: 24),
                              // Every section below is shown whether or not a
                              // category is selected. The breakdown used to
                              // disappear entirely on selection, which took
                              // the whole picture away at the exact moment
                              // someone was examining one part of it -- and
                              // needlessly, because these totals are computed
                              // across every category regardless of the
                              // filter, so nothing here has to move.
                              if (share == InsightsShare.bars) ...[
                                const Eyebrow('Where your money went'),
                                const SizedBox(height: 12),
                                CategoryBars(
                                  analytics: analytics,
                                  tones: tones,
                                  selected: category,
                                  onSelect: select,
                                ),
                                const SizedBox(height: 24),
                              ] else if (share ==
                                  InsightsShare.chronograph) ...[
                                Chronograph(
                                  categories: analytics.categories,
                                  tones: tones,
                                  selected: category,
                                  onSelect: select,
                                  currency: analytics.currency,
                                ),
                                const SizedBox(height: 24),
                              ] else if (share == InsightsShare.mixingDesk) ...[
                                MixingDesk(
                                  categories: analytics.categories,
                                  tones: tones,
                                  selected: category,
                                  onSelect: select,
                                  currency: analytics.currency,
                                ),
                                const SizedBox(height: 24),
                              ],
                              if (change == InsightsChange.seismograph) ...[
                                Seismograph(
                                  changes: analytics.categoryChanges,
                                  tones: tones,
                                  selected: category,
                                  onSelect: select,
                                  currency: analytics.currency,
                                ),
                                const SizedBox(height: 24),
                              ] else if (change == InsightsChange.gate) ...[
                                Gate(
                                  changes: analytics.categoryChanges,
                                  tones: tones,
                                  sensitivity: GateSensitivity.fromId(
                                    widget.viewModel.uiViewPreference(
                                      InsightsPreference.gateSensitivity,
                                    ),
                                  ),
                                  totalSpendingMinor:
                                      analytics.totalSpendingMinor,
                                  selected: category,
                                  onSelect: select,
                                  currency: analytics.currency,
                                ),
                                const SizedBox(height: 24),
                              ],
                              Text(
                                'Excludes moves between your own accounts, '
                                'and money lent, borrowed or held.',
                                style: SpendWiseType.body.copyWith(
                                  fontSize: 12.5,
                                  color: SpendWiseColors.dim,
                                ),
                              ),
                              // At the end of what it draws, where someone who
                              // has just read the screen and wants it drawn
                              // differently is already looking. Settings has
                              // the same door for anyone who went there first.
                              const SizedBox(height: 20),
                              _SectionsEntry(
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => InsightsSectionsScreen(
                                        viewModel: widget.viewModel,
                                        resolution: resolution,
                                      ),
                                    ),
                                  );
                                  if (mounted) setState(() {});
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      );
    },
  );
}

/// One category, chosen or not.
///
/// A ChoiceChip sat here, which is Material's rounded, filled idiom and the
/// only one of its kind on the screen -- beside a segmented ViewToggle making
/// a structurally identical "pick one" choice a single row above it.
class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Center(
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? SpendWiseColors.fg : SpendWiseColors.edge,
          ),
          color: selected ? SpendWiseColors.fg : Colors.transparent,
        ),
        child: Text(
          label,
          style: SpendWiseType.metaTight.copyWith(
            color: selected ? SpendWiseColors.bg : SpendWiseColors.dim,
          ),
        ),
      ),
    ),
  );
}

/// The in/out spine: one horizontal time axis with money in growing upward and
/// money out growing downward, drawn to a shared scale so the two sides are
/// directly comparable. This is the whole history in one object -- scroll it
/// sideways and you walk back through every period you have records for.
/// The way to change what this screen is made of, from the screen itself.
class _SectionsEntry extends StatelessWidget {
  const _SectionsEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.tune_rounded, size: 15, color: SpendWiseColors.dim),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Change what Insights shows',
              style: SpendWiseType.body.copyWith(
                fontSize: 12.5,
                color: SpendWiseColors.dim,
              ),
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: SpendWiseColors.dim,
          ),
        ],
      ),
    ),
  );
}

/// The header's one control: the period, named, with somewhere to go.
///
/// Deliberately built like one segment of the toggle it replaced, so the
/// header still reads as a control rather than as a label that happens to be
/// tappable.
class _PeriodButton extends StatelessWidget {
  const _PeriodButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Period: $label. Choose how far back Insights looks',
    child: InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: SpendWiseColors.edge),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 7, 7, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontFamily: SpendWiseType.sans,
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: SpendWiseColors.fg,
                ),
              ),
              const SizedBox(width: 5),
              const Icon(
                Icons.expand_more_rounded,
                size: 14,
                color: SpendWiseColors.dim,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class FlowSpine extends StatelessWidget {
  const FlowSpine({
    super.key,
    required this.buckets,
    required this.currency,
    this.height = 237,
    this.spendingOnly = false,
  });

  final List<AnalyticsBucket> buckets;
  final String currency;
  final double height;

  /// True while a single category is being looked at.
  ///
  /// Income is not attributed to categories — a salary is not "Groceries"
  /// — so a filtered bucket carries no income at all. That zero must not
  /// be allowed to set the scale: measuring the columns against an income
  /// peak of nothing would draw every day's spending at full height. Filtered,
  /// the spine scales to spending alone and shows only the arm it has.
  final bool spendingOnly;

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) return SizedBox(height: height);
    final peak = buckets.fold<int>(
      1,
      (best, bucket) => math.max(
        best,
        spendingOnly
            ? bucket.spendingMinor
            : math.max(bucket.incomeMinor, bucket.spendingMinor),
      ),
    );
    // Wide enough that a column is readable, narrow enough that a year of
    // months does not need six swipes — but never narrower than the widest
    // figure it has to print. A fixed 46 was clipping the label on any day
    // large enough to be worth looking at, which is exactly the wrong day to
    // lose a digit on. The spine scrolls, so paying for the width is cheap.
    final base = buckets.length > 18 ? 34.0 : 46.0;
    final widest = buckets.fold<double>(0, (best, bucket) {
      var worst = best;
      // Measured under the same conditions the labels are drawn under, so a
      // figure that is not printed cannot widen the column.
      if (bucket.incomeMinor > 0) {
        worst = math.max(
          worst,
          _tickWidth(formatMinor(bucket.incomeMinor, cents: false)),
        );
      }
      if (bucket.spendingMinor > 0) {
        worst = math.max(
          worst,
          _tickWidth(formatMinor(bucket.spendingMinor, cents: false)),
        );
      }
      return worst;
    });
    final columnWidth = math.max(base, widest + 8);

    return SizedBox(
      height: height,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: SpendWiseTheme.gutter),
        itemCount: buckets.length,
        itemBuilder: (context, index) {
          final bucket = buckets[buckets.length - 1 - index];
          return _SpineColumn(
            bucket: bucket,
            peak: peak,
            width: columnWidth,
            latest: index == 0,
            spendingOnly: spendingOnly,
          );
        },
      ),
    );
  }
}

class _SpineColumn extends StatelessWidget {
  const _SpineColumn({
    required this.bucket,
    required this.peak,
    required this.width,
    required this.latest,
    required this.spendingOnly,
  });

  final AnalyticsBucket bucket;
  final int peak;
  final double width;
  final bool latest;
  final bool spendingOnly;

  @override
  Widget build(BuildContext context) {
    // Fixed arm and tick heights: the column has to fit an exact budget, and a
    // font that renders a hair taller than expected must clip a label rather
    // than overflow the spine.
    const armHeight = 84.0;
    final inHeight = spendingOnly
        ? 0.0
        : (bucket.incomeMinor / peak) * armHeight;
    final outHeight = (bucket.spendingMinor / peak) * armHeight;
    return Semantics(
      label: spendingOnly
          ? '${bucket.label}: ${formatMinor(bucket.spendingMinor)} out'
          : '${bucket.label}: '
                '${formatMinor(bucket.incomeMinor)} in, '
                '${formatMinor(bucket.spendingMinor)} out',
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            SizedBox(
              height: armHeight + _Tick.height + 6,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (bucket.incomeMinor > 0)
                    _Tick(
                      text: formatMinor(bucket.incomeMinor, cents: false),
                      color: latest
                          ? SpendWiseColors.keep
                          : SpendWiseColors.dim,
                      padding: const EdgeInsets.only(bottom: 3),
                    ),
                  Container(
                    width: width - 14,
                    height: math.max(inHeight, bucket.incomeMinor > 0 ? 2 : 0),
                    color: SpendWiseColors.keep.withValues(
                      alpha: latest ? 1 : .58,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: width,
              height: 1,
              color: latest ? SpendWiseColors.fg : SpendWiseColors.edge,
            ),
            SizedBox(
              height: armHeight + _Tick.height + 6,
              child: Column(
                children: [
                  Container(
                    width: width - 14,
                    height: math.max(
                      outHeight,
                      bucket.spendingMinor > 0 ? 2 : 0,
                    ),
                    color: SpendWiseColors.spend.withValues(
                      alpha: latest ? 1 : .58,
                    ),
                  ),
                  if (bucket.spendingMinor > 0)
                    _Tick(
                      text: formatMinor(bucket.spendingMinor, cents: false),
                      color: latest
                          ? SpendWiseColors.spend
                          : SpendWiseColors.dim,
                      padding: const EdgeInsets.only(top: 3),
                    ),
                ],
              ),
            ),
            const Spacer(),
            // The date, and nothing else. A net figure used to sit under it,
            // repeating in one cramped line what the two arms above already
            // say in full, and doing it in a third colour.
            _Tick(
              text: bucket.label,
              color: latest ? SpendWiseColors.fg : SpendWiseColors.dim,
            ),
          ],
        ),
      ),
    );
  }
}

/// The printed width of one spine figure.
///
/// A column has to be at least as wide as the widest number it will print,
/// and the only way to know that is to lay the text out. Estimating it from
/// the character count is what clipped large days.
double _tickWidth(String text) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: _Tick.style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}

/// A one-line figure on the spine, in a box tall enough for exactly one line.
class _Tick extends StatelessWidget {
  const _Tick({
    required this.text,
    required this.color,
    this.padding = EdgeInsets.zero,
  });

  static const height = 12.0;

  /// Shared with [_tickWidth]. If the label and the measurement ever drift
  /// apart, columns go back to being sized for text they do not contain.
  static final style = SpendWiseType.metaTight.copyWith(
    fontSize: 8.5,
    letterSpacing: .2,
    height: 1.15,
  );

  final String text;
  final Color color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: SizedBox(
      height: height,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.clip,
        softWrap: false,
        style: style.copyWith(color: color),
      ),
    ),
  );
}

class _SummaryBand extends StatelessWidget {
  const _SummaryBand(this.analytics, {this.category});

  final SpendingAnalytics analytics;

  /// Named on the figure itself. The filter used to be stated only in an
  /// eyebrow *below* this number, so anyone reading the big figure had
  /// already passed the one line saying what it was filtered to.
  final String? category;

  @override
  Widget build(BuildContext context) {
    final change = analytics.spendingChangePercent;
    final changeColor = change == null || change <= 0
        ? SpendWiseColors.keep
        : SpendWiseColors.spend;
    final cadence = 'per ${analytics.resolution.cadence}';
    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SpendWiseColors.edge)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(
            category == null ? 'Spent in this view' : 'Spent on $category',
          ),
          const SizedBox(height: 6),
          // A period switch or a category tap changes this figure outright --
          // it is not the same spending restated, it is a different question
          // answered -- so it travels to its new value the same way every
          // other headline figure in the app does, rather than cutting to it.
          AnimatedMinor(
            analytics.totalSpendingMinor,
            style: SpendWiseType.figure.copyWith(fontSize: 30),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _SummaryItem(
                  label: 'Average $cadence',
                  value: formatAmount(
                    MoneyViewData(
                      analytics.averagePerBucketMinor,
                      currency: analytics.currency,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _SummaryItem(
                  label: change == null ? 'Previous period' : 'Spending rate',
                  value: change == null
                      ? 'No comparison yet'
                      : '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)}%',
                  color: changeColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
      ),
    ],
  );
}

/// Where the money went, drawn the way Home draws it.
///
/// This was a donut beside a list of the same six categories -- the same
/// numbers stated twice, once through arc length, which the eye reads worse
/// than bar length, and once as text. The bar was also quietly dishonest: it
/// trimmed every sweep by a fixed amount so the segments would separate,
/// which could clip a small category to nothing while its row still printed
/// a confident 1%.
/// The original breakdown: one bar to true proportion, then every category
/// by name. Public because the chooser previews it beside the dial and the
/// desk, and a preview drawn from a copy of the real thing is a preview that
/// can drift from it.
class CategoryBars extends StatelessWidget {
  const CategoryBars({
    super.key,
    required this.analytics,
    required this.tones,
    required this.selected,
    required this.onSelect,
  });

  final SpendingAnalytics analytics;
  final CategoryTones tones;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    if (analytics.categories.isEmpty) {
      return Text(
        'Categorised spending will appear here.',
        style: SpendWiseType.body.copyWith(fontSize: 13),
      );
    }
    // Every category, not the biggest few. Home folds its tail into one
    // line because it answers a glance; this screen is where someone comes
    // to look at all of it.
    final shown = analytics.categories;
    final total = shown.fold<int>(0, (sum, item) => sum + item.amountMinor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label:
              'Category spending. '
              '${shown.map((item) => '${item.category} ${(item.fraction * 100).round()} percent').join(', ')}',
          child: SegmentBar(
            weights: [
              for (final item in shown)
                total == 0 ? 1 : item.amountMinor / total,
            ],
            // Through the tones, like every other swatch. The bar used to
            // take the raw ramp and wrap at eight while the dot beside each
            // row stepped the tone down instead, so from the ninth category
            // on, a row's dot and its slice of the bar were different
            // colours -- the chart disagreeing with itself.
            colors: [for (final item in shown) tones.of(item.category)],
          ),
        ),
        const SizedBox(height: 4),
        for (final item in shown)
          _BreakdownRow(
            item: item,
            currency: analytics.currency,
            tone: tones.of(item.category),
            // Nothing is dimmed while nothing is selected, so the list reads
            // at full strength until someone actually asks a narrower
            // question.
            faded: selected != null && selected != item.category,
            // Tapping the selected row again clears the filter, which is the
            // only way back out without hunting for the "All spending" chip.
            onTap: () =>
                onSelect(selected == item.category ? null : item.category),
          ),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.item,
    required this.currency,
    required this.tone,
    required this.faded,
    required this.onTap,
  });

  final CategoryAnalytics item;
  final String currency;
  final Color tone;
  final bool faded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: AnimatedOpacity(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      opacity: faded ? .38 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(width: 9, height: 9, color: tone),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                item.category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SpendWiseType.row,
              ),
            ),
            Text(
              formatAmount(
                MoneyViewData(item.amountMinor, currency: currency),
                cents: false,
              ),
              style: SpendWiseType.rowStrong,
            ),
          ],
        ),
      ),
    ),
  );
}
