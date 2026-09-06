import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';
import '../transactions/transaction_details_screen.dart';
import 'river_view.dart';
import 'spending_analytics.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  /// Thirty days of all spending is the question people actually arrive with,
  /// so it is what the screen opens on.
  AnalyticsResolution resolution = AnalyticsResolution.last30Days;
  String? category;
  _InsightsView view = _InsightsView.detail;

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
              .where((item) => item.kind == TransactionKind.expense)
              .map((item) => item.category)
              .toSet()
              .toList()
            ..sort();

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
                  ViewToggle(
                    options: const ['River', 'Flow', 'Detail'],
                    selected: view.index,
                    onSelected: (index) =>
                        setState(() => view = _InsightsView.values[index]),
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
                        if (view != _InsightsView.river)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(
                              SpendWiseTheme.gutter,
                              0,
                              SpendWiseTheme.gutter,
                              10,
                            ),
                            sliver: SliverToBoxAdapter(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: ViewToggle(
                                  options: [
                                    for (final value
                                        in AnalyticsResolution.values)
                                      value.shortLabel,
                                  ],
                                  selected: AnalyticsResolution.values.indexOf(
                                    resolution,
                                  ),
                                  onSelected: (index) => setState(() {
                                    resolution =
                                        AnalyticsResolution.values[index];
                                  }),
                                ),
                              ),
                            ),
                          ),
                        if (view == _InsightsView.river) ...[
                          SliverToBoxAdapter(
                            child: RiverHeading(
                              inTotal: analytics.totalIncomeMinor,
                              outTotal: analytics.totalSpendingMinor,
                            ),
                          ),
                          RiverView(
                            transactions: widget.viewModel.transactions,
                            onOpen: (item) => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => TransactionDetailsScreen(
                                  viewModel: widget.viewModel,
                                  transaction: item,
                                ),
                              ),
                            ),
                          ),
                        ] else if (view == _InsightsView.flow) ...[
                          SliverToBoxAdapter(
                            child: FlowSpine(
                              buckets: analytics.buckets,
                              currency: analytics.currency,
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(
                              SpendWiseTheme.gutter,
                              20,
                              SpendWiseTheme.gutter,
                              36,
                            ),
                            sliver: SliverList.list(
                              children: [
                                _SummaryBand(analytics),
                                const SizedBox(height: 22),
                                Text(
                                  'Every ${_resolutionWord(resolution)} you '
                                  'have records for, in and out from one '
                                  'spine. Scroll it sideways to walk back '
                                  'through your whole history.',
                                  style: SpendWiseType.body.copyWith(
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
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
                                  return ChoiceChip(
                                    label: Text(value ?? 'All spending'),
                                    selected: category == value,
                                    onSelected: (_) =>
                                        setState(() => category = value),
                                  );
                                },
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(
                              SpendWiseTheme.gutter,
                              14,
                              SpendWiseTheme.gutter,
                              36,
                            ),
                            sliver: SliverList.list(
                              children: [
                                _BalanceSnapshot(
                                  accounts: widget.viewModel.accounts,
                                ),
                                const SizedBox(height: 22),
                                _SummaryBand(analytics),
                                const SizedBox(height: 22),
                                Eyebrow(
                                  category == null
                                      ? 'Money moving over time'
                                      : '$category spending over time',
                                ),
                                const SizedBox(height: 10),
                                _TrendChart(analytics),
                                const SizedBox(height: 22),
                                if (category == null) ...[
                                  const Eyebrow('Where your money went'),
                                  const SizedBox(height: 10),
                                  _CategoryBreakdown(analytics),
                                  const SizedBox(height: 22),
                                ],
                                Text(
                                  'Calculated only from your local ledger. '
                                  'Moves between your own accounts are '
                                  'excluded from both spending and income.',
                                  style: SpendWiseType.body.copyWith(
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      );
    },
  );

  static String _resolutionWord(AnalyticsResolution value) => value.cadence;
}

enum _InsightsView { river, flow, detail }

/// The in/out spine: one horizontal time axis with money in growing upward and
/// money out growing downward, drawn to a shared scale so the two sides are
/// directly comparable. This is the whole history in one object -- scroll it
/// sideways and you walk back through every period you have records for.
class FlowSpine extends StatelessWidget {
  const FlowSpine({
    super.key,
    required this.buckets,
    required this.currency,
    this.height = 252,
  });

  final List<AnalyticsBucket> buckets;
  final String currency;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) return SizedBox(height: height);
    final peak = buckets.fold<int>(
      1,
      (best, bucket) =>
          math.max(best, math.max(bucket.incomeMinor, bucket.spendingMinor)),
    );
    // Wide enough that a column is readable, narrow enough that a year of
    // months does not need six swipes.
    final columnWidth = buckets.length > 18 ? 34.0 : 46.0;

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
  });

  final AnalyticsBucket bucket;
  final int peak;
  final double width;
  final bool latest;

  @override
  Widget build(BuildContext context) {
    // Fixed arm and tick heights: the column has to fit an exact budget, and a
    // font that renders a hair taller than expected must clip a label rather
    // than overflow the spine.
    const armHeight = 84.0;
    final inHeight = (bucket.incomeMinor / peak) * armHeight;
    final outHeight = (bucket.spendingMinor / peak) * armHeight;
    final net = bucket.incomeMinor - bucket.spendingMinor;
    return Semantics(
      label:
          '${bucket.label}: '
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
            _Tick(
              text: bucket.label,
              color: latest ? SpendWiseColors.fg : SpendWiseColors.dim,
            ),
            const SizedBox(height: 3),
            _Tick(
              text: formatMinor(net, signed: true, cents: false),
              color: net >= 0 ? SpendWiseColors.keep : SpendWiseColors.spend,
            ),
          ],
        ),
      ),
    );
  }
}

/// A one-line figure on the spine, in a box tall enough for exactly one line.
class _Tick extends StatelessWidget {
  const _Tick({
    required this.text,
    required this.color,
    this.padding = EdgeInsets.zero,
  });

  static const height = 12.0;

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
        style: SpendWiseType.metaTight.copyWith(
          fontSize: 8.5,
          letterSpacing: .2,
          height: 1.15,
          color: color,
        ),
      ),
    ),
  );
}

class _BalanceSnapshot extends StatelessWidget {
  const _BalanceSnapshot({required this.accounts});

  final List<AccountViewData> accounts;

  @override
  Widget build(BuildContext context) {
    final currency = accounts.firstOrNull?.currency ?? 'PKR';
    final available = accounts
        .where((account) => account.isIncluded)
        .fold<int>(0, (sum, account) => sum + account.balance.minorUnits);
    final savings = accounts
        .where((account) => !account.isIncluded)
        .fold<int>(0, (sum, account) => sum + account.balance.minorUnits);
    final total = available + savings;
    final totalMoney = MoneyViewData(total, currency: currency);
    final availableMoney = MoneyViewData(available, currency: currency);
    final savingsMoney = MoneyViewData(savings, currency: currency);
    return Semantics(
      container: true,
      label:
          'Total tracked ${formatMoney(totalMoney)}. Available to spend ${formatMoney(availableMoney)}. Savings ${formatMoney(savingsMoney)}.',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total tracked',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  formatMoney(totalMoney),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _BalancePart(
                        label: 'Available to spend',
                        value: availableMoney,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 38,
                      color: SpendWiseColors.border,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _BalancePart(
                        label: 'Savings',
                        value: savingsMoney,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BalancePart extends StatelessWidget {
  const _BalancePart({required this.label, required this.value});

  final String label;
  final MoneyViewData value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 3),
      Text(
        formatMoney(value),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ],
  );
}

class _SummaryBand extends StatelessWidget {
  const _SummaryBand(this.analytics);

  final SpendingAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final change = analytics.spendingChangePercent;
    final changeColor = change == null || change <= 0
        ? SpendWiseColors.income
        : SpendWiseColors.expense;
    final cadence = 'per ${analytics.resolution.cadence}';
    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SpendWiseColors.edge)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Spent in this view'),
          const SizedBox(height: 6),
          Text(
            formatAmount(
              MoneyViewData(
                analytics.totalSpendingMinor,
                currency: analytics.currency,
              ),
            ),
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

class _TrendChart extends StatefulWidget {
  const _TrendChart(this.analytics);

  final SpendingAnalytics analytics;

  @override
  State<_TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<_TrendChart> {
  int? selectedIndex;

  @override
  void didUpdateWidget(covariant _TrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.analytics.resolution != widget.analytics.resolution ||
        oldWidget.analytics.category != widget.analytics.category) {
      selectedIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final analytics = widget.analytics;
    final selected =
        analytics.buckets[(selectedIndex ?? analytics.buckets.length - 1).clamp(
          0,
          analytics.buckets.length - 1,
        )];
    final maxValue = analytics.buckets.fold<int>(1, (maximum, bucket) {
      final value = math.max(bucket.spendingMinor, bucket.incomeMinor);
      return math.max(maximum, value);
    });
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${formatMoney(MoneyViewData(selected.spendingMinor, currency: analytics.currency))} spent',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (analytics.category == null)
                  _LegendDot(label: 'Income', color: SpendWiseColors.income),
                const SizedBox(width: 12),
                _LegendDot(label: 'Spent', color: SpendWiseColors.expense),
              ],
            ),
            const SizedBox(height: 18),
            // Twelve bars fit a phone; thirty do not. Past that the chart
            // scrolls at a readable bar width instead of squeezing every day
            // into three pixels and dropping its label.
            LayoutBuilder(
              builder: (context, constraints) {
                const minBarWidth = 26.0;
                final count = analytics.buckets.length;
                final scrolls = count * minBarWidth > constraints.maxWidth;
                final bars = [
                  for (var index = 0; index < count; index++)
                    SizedBox(
                      width: scrolls
                          ? minBarWidth
                          : constraints.maxWidth / count,
                      child: _BarColumn(
                        bucket: analytics.buckets[index],
                        maxValue: maxValue,
                        selected: index == (selectedIndex ?? count - 1),
                        showIncome: analytics.category == null,
                        currency: analytics.currency,
                        onTap: () => setState(() => selectedIndex = index),
                      ),
                    ),
                ];
                final row = Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: bars,
                );
                return SizedBox(
                  height: 190,
                  child: scrolls
                      ? SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: row,
                        )
                      : row,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BarColumn extends StatelessWidget {
  const _BarColumn({
    required this.bucket,
    required this.maxValue,
    required this.selected,
    required this.showIncome,
    required this.currency,
    required this.onTap,
  });

  final AnalyticsBucket bucket;
  final int maxValue;
  final bool selected;
  final bool showIncome;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spendHeight = bucket.spendingMinor == 0
        ? 3.0
        : 132 * bucket.spendingMinor / maxValue;
    final incomeHeight = bucket.incomeMinor == 0
        ? 3.0
        : 132 * bucket.incomeMinor / maxValue;
    final semantics =
        '${bucket.label}: ${formatMoney(MoneyViewData(bucket.spendingMinor, currency: currency))} spent${showIncome ? ', ${formatMoney(MoneyViewData(bucket.incomeMinor, currency: currency))} income' : ''}';
    return Semantics(
      button: true,
      selected: selected,
      label: semantics,
      child: Tooltip(
        message: semantics,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (showIncome)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 420),
                          curve: Curves.easeOutCubic,
                          width: 5,
                          height: incomeHeight,
                          decoration: BoxDecoration(
                            color: SpendWiseColors.income.withValues(
                              alpha: selected ? 1 : .58,
                            ),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      if (showIncome) const SizedBox(width: 2),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutCubic,
                        width: showIncome ? 9 : 14,
                        height: spendHeight,
                        decoration: BoxDecoration(
                          color: SpendWiseColors.expense.withValues(
                            alpha: selected ? 1 : .62,
                          ),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  bucket.label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: selected
                        ? Theme.of(context).colorScheme.onSurface
                        : SpendWiseColors.textSecondary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    fontSize: analyticsLabelSize(bucket.label),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static double analyticsLabelSize(String label) => label.length > 3 ? 9 : 10;
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown(this.analytics);

  final SpendingAnalytics analytics;

  /// The one ramp, so the donut, the bar on Home and the category rows all
  /// agree about which colour a category is.
  static List<Color> get colors => SpendWiseColors.categoryRamp;

  @override
  Widget build(BuildContext context) {
    if (analytics.categories.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text('Categorized spending will appear here.'),
        ),
      );
    }
    final shown = analytics.categories.take(6).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Semantics(
              label:
                  'Category spending chart. ${shown.map((item) => '${item.category} ${(item.fraction * 100).round()} percent').join(', ')}',
              child: SizedBox(
                width: 116,
                height: 116,
                child: CustomPaint(
                  painter: _DonutPainter(
                    fractions: shown.map((item) => item.fraction).toList(),
                    colors: colors,
                  ),
                  child: Center(
                    child: Text(
                      '${analytics.categories.length}\ncategories',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                children: [
                  for (var index = 0; index < shown.length; index++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: colors[index % colors.length],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              shown[index].category,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${(shown[index].fraction * 100).round()}%',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.fractions, required this.colors});

  final List<double> fractions;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.butt;
    var start = -math.pi / 2;
    for (var index = 0; index < fractions.length; index++) {
      final sweep = math.pi * 2 * fractions[index];
      paint.color = colors[index % colors.length];
      canvas.drawArc(
        rect.deflate(9),
        start,
        math.max(0, sweep - .025),
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.fractions != fractions || oldDelegate.colors != colors;
}
