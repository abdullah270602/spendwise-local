import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';
import '../insights/insights_screen.dart';
import '../insights/spending_analytics.dart';
import '../transactions/transaction_details_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.viewModel,
    required this.onSeeLedger,
    required this.onOpenSettings,
    required this.onOpenAccounts,
  });
  final SpendWiseViewModel viewModel;
  final VoidCallback onSeeLedger;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAccounts;
  @override
  Widget build(BuildContext context) {
    final data = viewModel.dashboard;
    final recent = viewModel.transactions.take(5).toList();
    final netFlow =
        data.netCashFlow ??
        MoneyViewData(
          data.incomeThisMonth.minorUnits - data.spendingThisMonth.minorUnits,
          currency: data.incomeThisMonth.currency,
        );
    final categories = data.categorySpending.isNotEmpty
        ? data.categorySpending
        : _deriveCategories(
            viewModel.transactions,
            data.spendingThisMonth.currency,
          );
    final transfers = data.recentTransfers.isNotEmpty
        ? data.recentTransfers
        : viewModel.transactions
              .where((item) => item.kind == TransactionKind.transfer)
              .take(3)
              .toList();
    final monthlyAnalytics = SpendingAnalytics.calculate(
      transactions: viewModel.transactions,
      resolution: AnalyticsResolution.months,
    );
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SpendWise'),
              Text(
                'LOCAL LEDGER',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.8,
                  color: SpendWiseColors.accent,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: () => _openInsights(context),
              tooltip: 'Open spending insights',
              icon: const Icon(Icons.insights_rounded),
            ),
            IconButton(
              onPressed: onOpenSettings,
              tooltip: 'Open settings',
              icon: const Icon(Icons.settings_outlined),
            ),
            const SizedBox(width: 8),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
          sliver: SliverList.list(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Total balance',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const Spacer(),
                          const Icon(
                            Icons.lock_rounded,
                            size: 14,
                            color: SpendWiseColors.textSecondary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'On-device',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Text(
                        formatMoney(data.netWorth),
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        data.incomeThisMonth.minorUnits == 0
                            ? 'No income recorded this month'
                            : '${data.monthlyChangePercent.toStringAsFixed(1)}% of income retained',
                        style: TextStyle(
                          color: data.monthlyChangePercent >= 0
                              ? SpendWiseColors.income
                              : SpendWiseColors.expense,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      label: 'Income',
                      value: formatMoney(data.incomeThisMonth),
                      icon: Icons.south_west_rounded,
                      color: SpendWiseColors.income,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MetricCard(
                      label: 'Spent',
                      value: formatMoney(data.spendingThisMonth),
                      icon: Icons.north_east_rounded,
                      color: SpendWiseColors.expense,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              MetricCard(
                label: 'Net cash flow',
                value: formatMoney(netFlow, signed: true),
                icon: Icons.waterfall_chart_rounded,
                color: netFlow.minorUnits >= 0
                    ? SpendWiseColors.income
                    : SpendWiseColors.expense,
                detail: 'THIS MONTH',
              ),
              const SizedBox(height: 20),
              SectionHeading(
                'Spending trend',
                action: 'Explore',
                onAction: () => _openInsights(context),
              ),
              const SizedBox(height: 8),
              _TrendPreview(
                analytics: monthlyAnalytics,
                onTap: () => _openInsights(context),
              ),
              const SizedBox(height: 20),
              if (viewModel.accounts.isEmpty) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Finish setup',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Add your first account, then choose which financial apps SpendWise may observe.',
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: onOpenAccounts,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add an account'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              const SectionHeading('Spending by category'),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: categories.isEmpty
                      ? Text(
                          'No categorized spending this month',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      : Column(
                          children: [
                            for (final item in categories.take(5))
                              _CategoryBar(item),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 20),
              const SectionHeading('Account balances'),
              const SizedBox(height: 8),
              if (viewModel.accounts.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Add an account to start tracking balances.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 106,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: viewModel.accounts.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final account = viewModel.accounts[index];
                      return SizedBox(
                        width: 188,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  account.type.toLowerCase().contains('wallet')
                                      ? Icons.wallet_outlined
                                      : Icons.account_balance_outlined,
                                  color: SpendWiseColors.accent,
                                  size: 19,
                                ),
                                const Spacer(),
                                Text(
                                  account.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                Text(
                                  formatMoney(account.balance),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (transfers.isNotEmpty) ...[
                const SizedBox(height: 20),
                const SectionHeading('Transfer activity'),
                const SizedBox(height: 8),
                _TransactionCard(items: transfers, viewModel: viewModel),
              ],
              const SizedBox(height: 20),
              SectionHeading(
                'Recent activity',
                action: recent.isEmpty ? null : 'See all',
                onAction: onSeeLedger,
              ),
              const SizedBox(height: 4),
              if (recent.isEmpty)
                const EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'Quiet so far',
                  message: 'Captured financial events will become transactions here.',
                )
              else
                _TransactionCard(items: recent, viewModel: viewModel),
              if (!viewModel.notificationAccessGranted) ...[
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.notifications_active_outlined,
                          color: SpendWiseColors.warning,
                        ),
                        const SizedBox(width: 13),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Enable automatic capture',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Grant notification access in Android settings.',
                                style: TextStyle(
                                  color: SpendWiseColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: viewModel.requestNotificationAccess,
                          child: const Text('Enable'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static List<CategorySpendViewData> _deriveCategories(
    List<TransactionViewData> transactions,
    String currency,
  ) {
    final totals = <String, int>{};
    final now = DateTime.now();
    for (final item in transactions) {
      if (item.kind != TransactionKind.expense ||
          item.occurredAt.year != now.year ||
          item.occurredAt.month != now.month) {
        continue;
      }
      totals.update(
        item.category,
        (v) => v + item.amount.minorUnits.abs(),
        ifAbsent: () => item.amount.minorUnits.abs(),
      );
    }
    final max = totals.values.fold<int>(0, (a, b) => a > b ? a : b);
    final result =
        totals.entries
            .map(
              (e) => CategorySpendViewData(
                category: e.key,
                amount: MoneyViewData(e.value, currency: currency),
                fraction: max == 0 ? 0 : e.value / max,
              ),
            )
            .toList()
          ..sort((a, b) => b.amount.minorUnits.compareTo(a.amount.minorUnits));
    return result;
  }

  void _openInsights(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => InsightsScreen(viewModel: viewModel)),
  );
}

class _TrendPreview extends StatelessWidget {
  const _TrendPreview({required this.analytics, required this.onTap});

  final SpendingAnalytics analytics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final buckets = analytics.buckets.skip(6).toList();
    final maxValue = buckets.fold<int>(1, (maximum, bucket) {
      return bucket.spendingMinor > maximum ? bucket.spendingMinor : maximum;
    });
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatMoney(
                        MoneyViewData(
                          analytics.totalSpendingMinor,
                          currency: analytics.currency,
                        ),
                      ),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Last 12 months · tap for days, months, and years',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 92,
                height: 52,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final bucket in buckets)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 3),
                          child: Container(
                            height: bucket.spendingMinor == 0
                                ? 3
                                : 48 * bucket.spendingMinor / maxValue,
                            decoration: BoxDecoration(
                              color: SpendWiseColors.expense.withValues(
                                alpha: .72,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({required this.items, required this.viewModel});
  final List<TransactionViewData> items;
  final SpendWiseViewModel viewModel;
  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          TransactionTile(
            items[i],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TransactionDetailsScreen(
                  viewModel: viewModel,
                  transaction: items[i],
                ),
              ),
            ),
          ),
          if (i < items.length - 1) const Divider(height: 1, indent: 68),
        ],
      ],
    ),
  );
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar(this.item);
  final CategorySpendViewData item;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '${item.category} spending',
    value:
        '${formatMoney(item.amount)}, ${(item.fraction * 100).round()} percent of the largest category',
    child: Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.category,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                formatMoney(item.amount),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: item.fraction.clamp(0, 1),
                minHeight: 6,
                backgroundColor: SpendWiseColors.border,
                color: SpendWiseColors.accent,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
