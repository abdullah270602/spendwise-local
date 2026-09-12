import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../insights/river_view.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../capture/capture_state.dart';
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
  static const _preferenceKey = 'ledger_view';
  static const _spanKey = 'ledger_span';

  final searchController = TextEditingController();
  late DateTime month;
  late _LedgerView view;

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
    view = _LedgerView.fromId(
      widget.viewModel.uiViewPreference(_preferenceKey),
    );
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
          if (scoped && view == _LedgerView.chart)
            SliverToBoxAdapter(child: _chart(visible)),
          // The river reads the same entries the register does, scoped to the
          // same month. It used to live on Insights, where its heading showed
          // one period's totals over a list of the whole ledger -- a total
          // that could never reconcile with the entries beneath it.
          if (scoped && view == _LedgerView.river) ...[
            SliverToBoxAdapter(
              // Deliberately counts debt movements, unlike every figure on
              // Insights. This is a heading over a list of what moved, not a
              // reading of what was earned and spent: money held for somebody
              // else really did arrive and really did leave, and a total that
              // omitted it could not be reconciled against the rows beneath
              // it -- which is the exact fault this heading was moved here to
              // fix.
              child: RiverHeading(
                inTotal: visible
                    .where((item) => item.kind == TransactionKind.income)
                    .fold<int>(0, (sum, i) => sum + i.amount.minorUnits.abs()),
                outTotal: visible
                    .where((item) => item.kind == TransactionKind.expense)
                    .fold<int>(0, (sum, i) => sum + i.amount.minorUnits.abs()),
              ),
            ),
            RiverView(
              transactions: visible,
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
          ],
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
                      // No padding, so the label still ends at the gutter,
                      // but a full-size box behind it: this is the way out of
                      // a filtered ledger and it was 30px tall.
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(
                          kMinInteractiveDimension,
                          kMinInteractiveDimension,
                        ),
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
                // Showing every month used to have an answer of its own --
                // "Nothing recorded yet. / This is the whole ledger." -- and
                // it could only ever be read by somebody whose filter matched
                // nothing, because with no filter and a ledger that has
                // entries the register is not empty. The screen said the
                // ledger was empty directly above a header counting
                // "0 matches across all months", which is the app arguing
                // with itself about whether the entries exist.
                headline: all.isEmpty
                    ? 'Nothing recorded yet.'
                    : scoped
                    ? 'Nothing in ${DateFormat('MMMM').format(month)}.'
                    : 'No transaction matches that.',
                detail: all.isEmpty
                    ? captureIsOff(widget.viewModel)
                          ? captureOffDetail
                          : 'Bank alerts land here automatically once '
                                'notification access is on. You can also add '
                                'one by hand.'
                    : scoped
                    ? 'Step back a month, or show every month.'
                    : 'Try fewer words, or clear the filters.',
                action: all.isEmpty && captureIsOff(widget.viewModel)
                    ? ChooseSourcesButton(viewModel: widget.viewModel)
                    : scoped && all.isNotEmpty
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
        // The month and the controls sit on one line where there is room for
        // one, and stack where there is not. Five controls at the size a thumb
        // needs come to 240px, which leaves a 360dp phone 76px for a month
        // name that wants 112 -- and an ellipsised "Septemb..." is the header
        // paying for its own tap targets out of the one word on it that says
        // what you are looking at. Stacked, both lines start at the gutter:
        // the month is a heading and the controls are a bar beneath it, which
        // is what they look like anyway once they are no longer beside it.
        OverflowBar(
          alignment: MainAxisAlignment.spaceBetween,
          overflowAlignment: OverflowBarAlignment.start,
          overflowSpacing: 4,
          children: [
            if (scoped)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Step(
                    icon: Icons.chevron_left_rounded,
                    tooltip: 'Previous month',
                    onPressed: () => _stepMonth(-1),
                  ),
                  // Flexible so a long month name yields to the controls
                  // beside it rather than pushing them off the edge.
                  Flexible(
                    // A step is the one action this header exists for, and it
                    // used to replace the whole word outright -- "August"
                    // gone, "September" there, in the same frame the balance
                    // and every row beneath it also changed. A fade is enough
                    // to say a step happened without racing the heavier
                    // redraw underneath it.
                    child: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutQuint,
                      switchOutCurve: Curves.easeOutQuint,
                      child: Text(
                        DateFormat(_sameYear ? 'MMMM' : 'MMMM yyyy')
                            .format(month),
                        key: ValueKey(month),
                        style: SpendWiseType.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  _Step(
                    icon: Icons.chevron_right_rounded,
                    tooltip: 'Next month',
                    onPressed: _atCurrentMonth ? null : () => _stepMonth(1),
                  ),
                ],
              )
            else
              Text(
                allMonths ? 'All months' : 'Every match',
                style: SpendWiseType.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Only offered when a month is actually being enforced. While
                // a search or filter is running the register is already
                // showing the whole ledger, so the control would claim to
                // change something it does not.
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
          ],
        ),
        const SizedBox(height: 12),
        // The same arrangement, for the same reason: raise the system font
        // and the toggle alone is most of the width, so the balance takes the
        // next line rather than squeezing its label into 80px and scaling its
        // figure down to fit -- which is what the Flexible here used to do,
        // and what it did instead of yielding was run 68px off the edge.
        OverflowBar(
          alignment: scoped
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.end,
          overflowAlignment: OverflowBarAlignment.end,
          overflowSpacing: 8,
          children: [
            if (scoped)
              ViewToggle(
                options: const ['Chart', 'River', 'Plain'],
                selected: view.index,
                onSelected: _setView,
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Eyebrow('Balance now'),
                const SizedBox(height: 3),
                // A balance long enough to fill the line on its own shrinks
                // rather than clipping.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  // Not `AnimatedMinor` itself -- that widget has no
                  // `maxLines`, and the single line this figure is forced
                  // onto is what lets the `FittedBox` above shrink it rather
                  // than let it wrap to two. Same duration and curve, so a
                  // balance that moves while this screen is open still reads
                  // as the same kind of event as every other figure that
                  // travels rather than jumps.
                  child: TweenAnimationBuilder<int>(
                    tween: IntTween(end: _currentBalance),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 800),
                    curve: Curves.easeOutQuint,
                    builder: (context, value, _) => Text(
                      formatMinor(value),
                      style: SpendWiseType.rowStrong.copyWith(fontSize: 19),
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
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

  /// What the owner can actually spend right now.
  ///
  /// Money held for somebody else landed in an account and looks exactly like
  /// their own money, so an account total overstates it: a balance is not a
  /// permission to spend. Accounts already takes it off the top for
  /// "Available to spend" (`accounts_screen.dart`), and "Balance now" is the
  /// same idea under a different name -- so it comes off here too. Without
  /// it, one everyday account holding nothing but a relative's 100,000 reads
  /// as 0 on Accounts and 100,000 on the Ledger, about the same money on the
  /// same day.
  ///
  /// It is derived from `uiDebts` rather than from a figure of its own
  /// because `uiDebts` is where Accounts derives it, and a second derivation
  /// of one number is a second chance for two screens to disagree.
  /// `LocalLedger.heldOutstandingMinor()` computes the same total, but it is
  /// not reachable from a view model, so nothing on screen can ask it.
  int get _currentBalance {
    final dashboard = widget.viewModel.dashboard;
    final balance =
        (dashboard.spendableBalance ?? dashboard.netWorth).minorUnits;
    return balance - _heldForOthers;
  }

  /// The money sitting in the everyday accounts that belongs to somebody
  /// else.
  ///
  /// Only what landed in an everyday account. A relative's funds paid
  /// straight into savings are not in this figure to begin with, so taking
  /// them off it would show the owner less of their own money than they
  /// have. A holding whose opening entry reached no account at all is
  /// counted, because the alternative is losing it entirely and a balance
  /// that is too high is the more dangerous of the two mistakes.
  int get _heldForOthers {
    final spendable = {
      for (final account in widget.viewModel.accounts)
        if (account.isIncluded) account.id,
    };
    return widget.viewModel.uiDebts
        .where(
          (item) =>
              item.isHeld &&
              !item.isSettled &&
              (item.accountId == null || spendable.contains(item.accountId)),
        )
        .fold<int>(0, (sum, item) => sum + item.outstanding.minorUnits);
  }

  /// How much one entry moved the figure printed above the chart.
  ///
  /// The walk-back below is only honest if it un-applies exactly what
  /// `_currentBalance` counts and nothing else. That figure is the total of
  /// the everyday accounts -- `LedgerSnapshot.spendableBalanceMinor` sums the
  /// accounts that are not savings, which is what [AccountViewData.isIncluded]
  /// marks -- less money held for somebody else. So there are exactly two
  /// things an entry can move, and three cases where an entry moves neither:
  ///
  /// * A transfer into savings leaves the total; a transfer out of savings
  ///   rejoins it; a transfer between two everyday accounts moves money the
  ///   total already contains on both sides and changes nothing. Skipping
  ///   every transfer -- which this did -- drew a line that contradicted the
  ///   number directly above it the moment anybody saved.
  /// * Spending from a savings account, or income landing in one, never
  ///   touches the spendable total either.
  /// * Held money moves the account and the held total by the same amount in
  ///   the same direction, so what is left over is unchanged whether it is
  ///   arriving or being handed on. (Settling a held debt by typing an amount
  ///   rather than attaching an entry moves the held total with no entry to
  ///   find; nothing in the register can represent that.)
  int _spendableDelta(
    TransactionViewData item,
    Set<String> spendable,
    Set<String> heldDebts,
  ) {
    if (heldDebts.contains(item.debtId)) return 0;
    final amount = item.amount.minorUnits.abs();
    switch (item.kind) {
      case TransactionKind.income:
        return spendable.contains(item.accountId) ? amount : 0;
      case TransactionKind.expense:
        return spendable.contains(item.accountId) ? -amount : 0;
      case TransactionKind.transfer:
        var delta = 0;
        if (spendable.contains(item.accountId)) delta -= amount;
        if (spendable.contains(item.toAccountId)) delta += amount;
        return delta;
    }
  }

  /// End-of-day balances for the scoped month, reconstructed backwards from
  /// today's balance so the right-hand end of the line is always the number
  /// printed above it.
  List<int> _balanceSeries(List<TransactionViewData> visible) {
    final spendable = {
      for (final account in widget.viewModel.accounts)
        if (account.isIncluded) account.id,
    };
    final heldDebts = {
      for (final debt in widget.viewModel.uiDebts)
        if (debt.isHeld) debt.id,
    };
    final days = DateTime(month.year, month.month + 1, 0).day;
    final deltas = List<int>.filled(days, 0);
    for (final item in visible) {
      final local = item.occurredAt.toLocal();
      deltas[local.day - 1] += _spendableDelta(item, spendable, heldDebts);
    }
    // Only the current month ends at today's balance; a past month ends where
    // the months after it began, which we walk back to from today.
    var running = _currentBalance;
    if (!_atCurrentMonth) {
      final cutoff = DateTime(month.year, month.month + 1);
      for (final item in widget.viewModel.transactions) {
        final local = item.occurredAt.toLocal();
        if (local.isBefore(cutoff)) continue;
        running -= _spendableDelta(item, spendable, heldDebts);
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

  void _setView(int index) {
    setState(() => view = _LedgerView.values[index]);
    widget.viewModel.uiSetViewPreference(_preferenceKey, view.id);
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
    // These five are packed against each other, which is exactly where a
    // target below the guideline costs you the wrong month or the wrong
    // sheet. The icon is unchanged; the box behind it is not.
    padding: const EdgeInsets.all(6),
    constraints: const BoxConstraints(
      minWidth: kMinInteractiveDimension,
      minHeight: kMinInteractiveDimension,
    ),
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

/// How the month is drawn.
///
/// The river came from Insights, where it answered "what happened" -- which is
/// this screen's question, not that one's. Here it is a third way to read the
/// same month, sharing the toggle that was already deciding between the
/// balance chart and the plain register, so it costs the screen no new chrome.
enum _LedgerView {
  chart(id: 'chart'),
  river(id: 'river'),
  plain(id: 'plain');

  const _LedgerView({required this.id});

  final String id;

  static _LedgerView fromId(String? id) {
    for (final value in values) {
      if (value.id == id) return value;
    }
    return chart;
  }
}
