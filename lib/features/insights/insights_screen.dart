import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../shell/spendwise_view_model.dart';
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
                  // The only choice left in the header is how far back to
                  // look. There used to be a second toggle above it choosing
                  // between three views, two of which drew the same numbers
                  // as each other or as another screen.
                  ViewToggle(
                    options: [
                      for (final value in AnalyticsResolution.values)
                        value.shortLabel,
                    ],
                    selected: AnalyticsResolution.values.indexOf(resolution),
                    onSelected: (index) => setState(() {
                      resolution = AnalyticsResolution.values[index];
                    }),
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
                        SliverToBoxAdapter(
                          child: FlowSpine(
                            buckets: analytics.buckets,
                            currency: analytics.currency,
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
                              if (category == null) ...[
                                const Eyebrow('Where your money went'),
                                const SizedBox(height: 12),
                                _CategoryBreakdown(analytics),
                                const SizedBox(height: 24),
                              ],
                              Text(
                                'Every ${_resolutionWord(resolution)} you have '
                                'records for, in and out on one scale. Scroll '
                                'the spine sideways to walk back through your '
                                'whole history.',
                                style: SpendWiseType.body.copyWith(
                                  fontSize: 12.5,
                                  color: SpendWiseColors.dim,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Calculated only from your local ledger. Moves '
                                'between your own accounts are excluded from '
                                'both spending and income, and so is money '
                                'lent, borrowed or held for someone else — '
                                'none of it was earned or spent.',
                                style: SpendWiseType.body.copyWith(
                                  fontSize: 12.5,
                                  color: SpendWiseColors.dim,
                                ),
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

  static String _resolutionWord(AnalyticsResolution value) => value.cadence;
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

/// Where the money went, drawn the way Home draws it.
///
/// This was a donut beside a list of the same six categories -- the same
/// numbers stated twice, once through arc length, which the eye reads worse
/// than bar length, and once as text. The bar was also quietly dishonest: it
/// trimmed every sweep by a fixed amount so the segments would separate,
/// which could clip a small category to nothing while its row still printed
/// a confident 1%.
class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown(this.analytics);

  final SpendingAnalytics analytics;

  /// The one ramp, so this bar, the bar on Home and the category rows all
  /// agree about which colour a category is.
  static List<Color> get colors => SpendWiseColors.categoryRamp;

  @override
  Widget build(BuildContext context) {
    if (analytics.categories.isEmpty) {
      return Text(
        'Categorised spending will appear here.',
        style: SpendWiseType.body.copyWith(fontSize: 13),
      );
    }
    final shown = analytics.categories.take(6).toList();
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
            colors: [
              for (var i = 0; i < shown.length; i++) colors[i % colors.length],
            ],
          ),
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < shown.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  color: colors[i % colors.length],
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    shown[i].category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SpendWiseType.row,
                  ),
                ),
                Text(
                  formatAmount(
                    MoneyViewData(
                      shown[i].amountMinor,
                      currency: analytics.currency,
                    ),
                    cents: false,
                  ),
                  style: SpendWiseType.rowStrong,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
