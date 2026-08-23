import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';
import '../insights/insights_screen.dart';
import '../transactions/transaction_details_screen.dart';

const _categoryColors = [
  SpendWiseColors.accent,
  SpendWiseColors.warning,
  SpendWiseColors.expense,
  Color(0xFF7AB8FF),
  Color(0xFFB89CFF),
  Color(0xFF65C7C1),
];

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.viewModel,
    required this.onSeeLedger,
    required this.onOpenAccounts,
  });
  final SpendWiseViewModel viewModel;
  final VoidCallback onSeeLedger;
  final VoidCallback onOpenAccounts;
  @override
  Widget build(BuildContext context) {
    final data = viewModel.dashboard;
    final availableBalance = data.spendableBalance ?? data.netWorth;
    final savingsBalance = data.savingsBalance ?? const MoneyViewData(0);
    final showSavings = viewModel.uiShowSavingsOnHome;
    final homeAccounts = showSavings
        ? viewModel.accounts
        : viewModel.accounts.where((account) => account.isIncluded).toList();
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
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          title: const Row(
            children: [
              SpendWiseMark(size: 34),
              SizedBox(width: 11),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SpendWise'),
                  Text(
                    'Private. Local. Yours.',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: .3,
                      color: SpendWiseColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: () => _openInsights(context),
              tooltip: 'Open spending insights',
              icon: const Icon(Icons.insights_rounded),
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
                            'Available to spend',
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
                        formatMoney(availableBalance),
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
                      if (showSavings && savingsBalance.minorUnits != 0) ...[
                        const SizedBox(height: 10),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: onOpenAccounts,
                          icon: const Icon(Icons.savings_outlined, size: 18),
                          label: Text(
                            '${formatMoney(savingsBalance)} saved separately',
                          ),
                        ),
                      ],
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
                            for (final (index, item) in categories
                                .take(5)
                                .indexed)
                              _CategoryBar(
                                item,
                                color: _categoryColors[index %
                                    _categoryColors.length],
                              ),
                          ],
                        ),
                ),
              ),
              if (homeAccounts.isNotEmpty) ...[
                const SizedBox(height: 20),
                const SectionHeading('Account balances'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 106,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: homeAccounts.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final account = homeAccounts[index];
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
              ],
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
  const _CategoryBar(this.item, {required this.color});
  final CategorySpendViewData item;
  final Color color;
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
                color: color,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
