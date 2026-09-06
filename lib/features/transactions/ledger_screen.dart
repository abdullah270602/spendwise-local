import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../shell/spendwise_view_model.dart';
import 'transaction_details_screen.dart';

/// The Ledger is a balance line over a register. The chart is the month's
/// shape -- you can see salary land and the month step down from it -- and the
/// rows underneath are deliberately tight, with no per-row ornament, so twice
/// as many fit on screen. `Chart / Plain` takes the graph away and the choice
/// sticks.
class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  static const _preferenceKey = 'ledger_chart';
  static const _spanKey = 'ledger_span';

  final searchController = TextEditingController();
  late DateTime month;
  late bool showChart;

  /// Whether the register shows the whole ledger rather than one month.
  ///
  /// One month is the default because that is the question people ask most,
  /// and it keeps the balance chart meaningful. But everything older stayed
  /// reachable only by stepping back a month at a time, which is no way to
  /// find a payment from two years ago -- and "All months" appeared only as a
  /// side effect of searching, so there was no way to simply ask for it.
  late bool allMonths;
  bool searching = false;
  String query = '';
  TransactionKind? kind;
  String? accountId;
  String? category;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    month = DateTime(now.year, now.month);
    showChart = widget.viewModel.uiViewPreference(_preferenceKey) != 'plain';
    allMonths = widget.viewModel.uiViewPreference(_spanKey) == 'all';
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  /// A search or a filter is a question about the whole ledger, not about one
  /// month, so it drops the month scope rather than quietly hiding matches.
  bool get scoped =>
      !allMonths &&
      query.isEmpty &&
      kind == null &&
      accountId == null &&
      category == null;

  void _setAllMonths(bool value) {
    setState(() {
      allMonths = value;
      // Coming back to a single month lands on this one, not on wherever the
      // stepper happened to be left months ago.
      if (!value) {
        final now = DateTime.now();
        month = DateTime(now.year, now.month);
      }
    });
    widget.viewModel.uiSetViewPreference(_spanKey, value ? 'all' : 'month');
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.viewModel.transactions;
    final matches = all.where(_matches).toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final visible = scoped
        ? matches.where((item) {
            final local = item.occurredAt.toLocal();
            return local.year == month.year && local.month == month.month;
          }).toList()
        : matches;

    final groups = <DateTime, List<TransactionViewData>>{};
    for (final item in visible) {
      final local = item.occurredAt.toLocal();
      groups
          .putIfAbsent(DateTime(local.year, local.month, local.day), () => [])
          .add(item);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _header(context)),
          if (searching)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  SpendWiseTheme.gutter,
                  12,
                  SpendWiseTheme.gutter,
                  0,
                ),
                child: TextField(
                  controller: searchController,
                  autofocus: true,
                  onChanged: (value) => setState(() => query = value),
                  style: SpendWiseType.row,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Merchant, account, category…',
                    suffixIcon: IconButton(
                      onPressed: _closeSearch,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ),
                ),
              ),
            ),
          if (scoped && showChart) SliverToBoxAdapter(child: _chart(visible)),
          if (!scoped)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  SpendWiseTheme.gutter,
                  14,
                  SpendWiseTheme.gutter,
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Eyebrow(
                        '${visible.length} '
                        '${visible.length == 1 ? 'match' : 'matches'} '
                        'across all months',
                      ),
                    ),
                    TextButton(
                      onPressed: _clearSearchAndFilters,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ),
            ),
          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: RestState(
                headline: all.isEmpty
                    ? 'Nothing recorded yet.'
                    : scoped
                    ? 'Nothing in ${DateFormat('MMMM').format(month)}.'
                    : allMonths
                    ? 'Nothing recorded yet.'
                    : 'No transaction matches that.',
                detail: all.isEmpty
                    ? 'Bank alerts land here automatically once notification '
                          'access is on. You can also add one by hand.'
                    : scoped
                    ? 'Step back a month, or show every month.'
                    : allMonths
                    ? 'This is the whole ledger.'
                    : 'Try fewer words, or clear the filters.',
                action: scoped && all.isNotEmpty
                    ? OutlinedButton(
                        onPressed: () => _stepMonth(-1),
                        child: Text(
                          'Go to ${DateFormat('MMMM').format(DateTime(month.year, month.month - 1))}',
                        ),
                      )
                    : null,
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                SpendWiseTheme.gutter,
                6,
                SpendWiseTheme.gutter,
                96 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              sliver: SliverList.builder(
                itemCount: days.length,
                itemBuilder: (context, index) {
                  final day = days[index];
                  final rows = groups[day]!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: index == 0
                                  ? SpendWiseColors.edge
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                        child: RegisterDay(
                          label: DateFormat('EEE dd').format(day),
                          total: formatMinor(_net(rows), signed: true),
                        ),
                      ),
                      for (final item in rows) _row(context, item),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SpendWiseTheme.gutter,
      14,
      SpendWiseTheme.gutter,
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (scoped) ...[
              _Step(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Previous month',
                onPressed: () => _stepMonth(-1),
              ),
              const SizedBox(width: 2),
              // Flexible so a long month name yields to the controls rather
              // than pushing them off the edge -- "September 2024" plus four
              // icons does not fit a narrow phone otherwise.
              Flexible(
                child: Text(
                  DateFormat(_sameYear ? 'MMMM' : 'MMMM yyyy').format(month),
                  style: SpendWiseType.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              _Step(
                icon: Icons.chevron_right_rounded,
                tooltip: 'Next month',
                onPressed: _atCurrentMonth ? null : () => _stepMonth(1),
              ),
            ] else
              Flexible(
                child: Text(
                  allMonths ? 'All months' : 'Every match',
                  style: SpendWiseType.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const Spacer(),
            // Only offered when a month is actually being enforced. While a
            // search or filter is running the register is already showing the
            // whole ledger, so the control would claim to change something it
            // does not.
            if (query.isEmpty &&
                kind == null &&
                accountId == null &&
                category == null)
              _Step(
                icon: allMonths
                    ? Icons.calendar_month_rounded
                    : Icons.all_inclusive_rounded,
                tooltip: allMonths
                    ? 'Show one month at a time'
                    : 'Show every month',
                onPressed: () => _setAllMonths(!allMonths),
                active: allMonths,
              ),
            _Step(
              icon: Icons.search_rounded,
              tooltip: 'Search the ledger',
              onPressed: () => setState(() => searching = !searching),
              active: searching,
            ),
            _Step(
              icon: Icons.tune_rounded,
              tooltip: 'Filter the ledger',
              onPressed: () => _showFilters(context),
              active: _activeFilterCount > 0,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (scoped)
              ViewToggle(
                options: const ['Chart', 'Plain'],
                selected: showChart ? 0 : 1,
                onSelected: _setChart,
              ),
            const Spacer(),
            // A large balance and the toggle together are wider than a 360dp
            // phone. Neither is worth clipping, so the number wraps its label
            // and shrinks rather than running off the edge.
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Eyebrow('Balance now · $_currency'),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      formatMinor(_currentBalance),
                      style: SpendWiseType.rowStrong.copyWith(fontSize: 19),
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _chart(List<TransactionViewData> visible) {
    final points = _balanceSeries(visible);
    final last = DateTime(month.year, month.month + 1, 0).day;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SpendWiseTheme.gutter,
        10,
        SpendWiseTheme.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: 'Balance through ${DateFormat('MMMM').format(month)}',
            child: BalanceLine(points: points),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final tick in ['01', '10', '20', '$last'])
                Text(tick, style: SpendWiseType.metaTight),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, TransactionViewData item) {
    final own = item.kind == TransactionKind.transfer;
    final color = switch (item.kind) {
      TransactionKind.income => SpendWiseColors.keep,
      TransactionKind.transfer => SpendWiseColors.mine,
      TransactionKind.expense => SpendWiseColors.spend,
    };
    final meta = own
        ? 'Your own accounts'
        : [
            item.category,
            if (item.accountName.isNotEmpty) item.accountName,
          ].join(' · ');
    return RegisterRow(
      name: item.title,
      meta: meta,
      amount: formatAmount(item.amount),
      amountColor: color,
      ownTransfer: own,
      pending: !item.isReviewed,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => TransactionDetailsScreen(
            viewModel: widget.viewModel,
            transaction: item,
          ),
        ),
      ),
    );
  }

  // ---- data ------------------------------------------------------------

  bool get _sameYear => month.year == DateTime.now().year;

  bool get _atCurrentMonth {
    final now = DateTime.now();
    return month.year == now.year && month.month == now.month;
  }

  String get _currency => widget.viewModel.accounts.isEmpty
      ? 'PKR'
      : widget.viewModel.accounts.first.currency;

  int get _currentBalance {
    final dashboard = widget.viewModel.dashboard;
    return (dashboard.spendableBalance ?? dashboard.netWorth).minorUnits;
  }

  /// End-of-day balances for the scoped month, reconstructed backwards from
  /// today's balance so the right-hand end of the line is always the number
  /// printed above it.
  List<int> _balanceSeries(List<TransactionViewData> visible) {
    final days = DateTime(month.year, month.month + 1, 0).day;
    final deltas = List<int>.filled(days, 0);
    for (final item in visible) {
      final local = item.occurredAt.toLocal();
      if (item.kind == TransactionKind.transfer) continue;
      final sign = item.kind == TransactionKind.income ? 1 : -1;
      deltas[local.day - 1] += sign * item.amount.minorUnits.abs();
    }
    // Only the current month ends at today's balance; a past month ends where
    // the months after it began, which we walk back to from today.
    var running = _currentBalance;
    if (!_atCurrentMonth) {
      final cutoff = DateTime(month.year, month.month + 1);
      for (final item in widget.viewModel.transactions) {
        final local = item.occurredAt.toLocal();
        if (local.isBefore(cutoff)) continue;
        if (item.kind == TransactionKind.transfer) continue;
        final sign = item.kind == TransactionKind.income ? 1 : -1;
        running -= sign * item.amount.minorUnits.abs();
      }
    }
    final series = List<int>.filled(days, 0);
    for (var i = days - 1; i >= 0; i--) {
      series[i] = running;
      running -= deltas[i];
    }
    return series;
  }

  int _net(List<TransactionViewData> rows) => rows.fold<int>(0, (sum, item) {
    if (item.kind == TransactionKind.transfer) return sum;
    final sign = item.kind == TransactionKind.income ? 1 : -1;
    return sum + sign * item.amount.minorUnits.abs();
  });

  bool _matches(TransactionViewData item) {
    if (kind != null && item.kind != kind) return false;
    if (category != null && item.category != category) return false;
    if (accountId != null &&
        item.accountId != accountId &&
        item.toAccountId != accountId) {
      return false;
    }
    if (query.isEmpty) return true;
    final haystack =
        '${item.title} ${item.subtitle} ${item.category} ${item.accountName}';
    return haystack.toLowerCase().contains(query.toLowerCase());
  }

  int get _activeFilterCount =>
      [kind, accountId, category].where((value) => value != null).length;

  // ---- actions ---------------------------------------------------------

  void _setChart(int index) {
    setState(() => showChart = index == 0);
    widget.viewModel.uiSetViewPreference(
      _preferenceKey,
      showChart ? 'chart' : 'plain',
    );
  }

  void _stepMonth(int delta) =>
      setState(() => month = DateTime(month.year, month.month + delta));

  void _closeSearch() => setState(() {
    searching = false;
    query = '';
    searchController.clear();
  });

  void _clearSearchAndFilters() => setState(() {
    query = '';
    kind = null;
    accountId = null;
    category = null;
    searching = false;
    searchController.clear();
  });

  void _showFilters(BuildContext context) {
    var draftKind = kind;
    var draftAccountId = accountId;
    var draftCategory = category;
    final categories =
        widget.viewModel.transactions
            .map((item) => item.category)
            .toSet()
            .toList()
          ..sort();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refresh) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              SpendWiseTheme.gutter,
              0,
              SpendWiseTheme.gutter,
              24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Narrow the ledger', style: SpendWiseType.title),
                const SizedBox(height: 20),
                const Eyebrow('Kind'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final value in TransactionKind.values)
                      ChoiceChip(
                        label: Text(switch (value) {
                          TransactionKind.expense => 'Money out',
                          TransactionKind.income => 'Money in',
                          TransactionKind.transfer => 'Between your accounts',
                        }),
                        selected: draftKind == value,
                        onSelected: (selected) =>
                            refresh(() => draftKind = selected ? value : null),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                const Eyebrow('Account'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: draftAccountId,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Every account'),
                    ),
                    for (final account in widget.viewModel.accounts)
                      DropdownMenuItem<String?>(
                        value: account.id,
                        child: Text(account.name),
                      ),
                  ],
                  onChanged: (value) => refresh(() => draftAccountId = value),
                ),
                const SizedBox(height: 14),
                const Eyebrow('Category'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: draftCategory,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Every category'),
                    ),
                    for (final value in categories)
                      DropdownMenuItem<String?>(
                        value: value,
                        child: Text(value),
                      ),
                  ],
                  onChanged: (value) => refresh(() => draftCategory = value),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => refresh(() {
                          draftKind = null;
                          draftAccountId = null;
                          draftCategory = null;
                        }),
                        child: const Text('Clear'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          setState(() {
                            kind = draftKind;
                            accountId = draftAccountId;
                            category = draftCategory;
                          });
                          Navigator.pop(sheetContext);
                        },
                        child: const Text('Apply'),
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

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.all(6),
    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    icon: Icon(
      icon,
      size: 20,
      color: onPressed == null
          ? SpendWiseColors.line
          : active
          ? SpendWiseColors.fg
          : SpendWiseColors.dim,
    ),
  );
}
