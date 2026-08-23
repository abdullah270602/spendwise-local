import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';
import 'spending_analytics.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  AnalyticsResolution resolution = AnalyticsResolution.months;
  String? category;

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
      return Scaffold(
        appBar: AppBar(title: const Text('Insights')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
              child: _BalanceSnapshot(accounts: widget.viewModel.accounts),
            ),
            Expanded(
              child: widget.viewModel.transactions.isEmpty
                  ? const EmptyState(
                      icon: Icons.insights_outlined,
                      title: 'No trends yet',
                      message: 'Once transactions reach your ledger, SpendWise will compare spending across days, months, years, and categories.',
                    )
                  : CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
                          sliver: SliverToBoxAdapter(
                            child: SegmentedButton<AnalyticsResolution>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(
                                  value: AnalyticsResolution.days,
                                  label: Text('Days'),
                                ),
                                ButtonSegment(
                                  value: AnalyticsResolution.months,
                                  label: Text('Months'),
                                ),
                                ButtonSegment(
                                  value: AnalyticsResolution.years,
                                  label: Text('Years'),
                                ),
                              ],
                              selected: {resolution},
                              onSelectionChanged: (value) => setState(() {
                                resolution = value.first;
                              }),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 46,
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
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
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 36),
                          sliver: SliverList.list(
                            children: [
                              _SummaryBand(analytics),
                              const SizedBox(height: 22),
                              SectionHeading(
                                category == null
                                    ? 'Money moving over time'
                                    : '$category spending over time',
                              ),
                              const SizedBox(height: 8),
                              _TrendChart(analytics),
                              const SizedBox(height: 22),
                              if (category == null) ...[
                                const SectionHeading('Where your money went'),
                                const SizedBox(height: 8),
                                _CategoryBreakdown(analytics),
                                const SizedBox(height: 22),
                              ],
                              const SizedBox(height: 18),
                              Text(
                                'Calculated only from your local ledger. Transfers are excluded from spending and income.',
                                style: Theme.of(context).textTheme.bodySmall,
                                textAlign: TextAlign.center,
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
    final cadence = switch (analytics.resolution) {
      AnalyticsResolution.days => 'per day',
      AnalyticsResolution.months => 'per month',
      AnalyticsResolution.years => 'per year',
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SpendWiseColors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SpendWiseColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spent in this view',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 5),
          Text(
            formatMoney(
              MoneyViewData(
                analytics.totalSpendingMinor,
                currency: analytics.currency,
              ),
            ),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SummaryItem(
                  label: 'Average $cadence',
                  value: formatMoney(
                    MoneyViewData(
                      analytics.averagePerBucketMinor,
                      currency: analytics.currency,
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 38, color: SpendWiseColors.border),
              const SizedBox(width: 14),
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
                const _LegendDot(
                  label: 'Spent',
                  color: SpendWiseColors.expense,
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 190,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var index = 0; index < analytics.buckets.length; index++)
                    Expanded(
                      child: _BarColumn(
                        bucket: analytics.buckets[index],
                        maxValue: maxValue,
                        selected:
                            index ==
                            (selectedIndex ?? analytics.buckets.length - 1),
                        showIncome: analytics.category == null,
                        currency: analytics.currency,
                        onTap: () => setState(() => selectedIndex = index),
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

  static const colors = [
    SpendWiseColors.accent,
    SpendWiseColors.warning,
    SpendWiseColors.expense,
    Color(0xFF7AB8FF),
    Color(0xFFB89CFF),
    Color(0xFF65C7C1),
  ];

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

