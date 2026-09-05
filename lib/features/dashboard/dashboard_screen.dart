import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../settings/settings_screen.dart';
import '../shell/spendwise_view_model.dart';

/// Home is one idea: of everything that arrived this month, this much is still
/// yours and this much is gone -- drawn to true proportion, then zoomed into
/// the part that left. No cards, no metric grid, no trend chart.
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
    final now = DateTime.now();
    final month = DateFormat('MMMM').format(now);

    final received = data.incomeThisMonth.minorUnits;
    final spent = data.spendingThisMonth.minorUnits;
    final kept = received - spent;
    final anything = received != 0 || spent != 0;

    final categories = [...data.categorySpending]
      ..sort((a, b) => b.amount.minorUnits.compareTo(a.amount.minorUnits));
    final categoryTotal = categories.fold<int>(
      0,
      (sum, item) => sum + item.amount.minorUnits,
    );

    final ownMoves = viewModel.transactions.where((item) {
      final local = item.occurredAt.toLocal();
      return item.kind == TransactionKind.transfer &&
          local.year == now.year &&
          local.month == now.month;
    }).toList();

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SpendWiseTheme.gutter,
                14,
                SpendWiseTheme.gutter - 8,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Eyebrow('$month · what happened to it'),
                  ),
                  IconButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => SettingsScreen(viewModel: viewModel),
                      ),
                    ),
                    tooltip: 'Settings and privacy',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.tune_rounded,
                      size: 19,
                      color: SpendWiseColors.dim,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!anything && viewModel.uiShowSavingsOnHome)
            SliverToBoxAdapter(
              child: _SavingsStrip(
                accounts: viewModel.accounts,
                onTap: onOpenAccounts,
              ),
            ),
          if (!anything)
            SliverToBoxAdapter(
              child: RestState(
                headline: 'Nothing has moved in $month yet.',
                detail: viewModel.notificationAccessGranted
                    ? 'The moment a bank alert arrives, this becomes the shape '
                          'of your month.'
                    : 'Turn on notification access and SpendWise will start '
                          'reading your bank alerts.',
                action: viewModel.notificationAccessGranted
                    ? null
                    : OutlinedButton(
                        onPressed: viewModel.requestNotificationAccess,
                        child: const Text('Turn on notification access'),
                      ),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  SpendWiseTheme.gutter,
                  8,
                  SpendWiseTheme.gutter,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RECEIVED ${formatMinor(received)}',
                      style: SpendWiseType.metaTight,
                    ),
                    const SizedBox(height: 6),
                    Semantics(
                      label:
                          'Of ${formatMinor(received)} received, '
                          '${formatMinor(kept)} is still yours and '
                          '${formatMinor(spent)} was spent.',
                      child: FlowShape(
                        receivedMinor: received,
                        keptMinor: kept,
                        spentMinor: spent,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _Legend(received: received, kept: kept, spent: spent),
                  ],
                ),
              ),
            ),
            if (categories.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SpendWiseTheme.gutter,
                    26,
                    SpendWiseTheme.gutter,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.only(top: 13),
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: SpendWiseColors.line),
                          ),
                        ),
                        child: Eyebrow(
                          received > 0
                              ? 'The ${_percent(spent, received)}, up close'
                              : 'Where it went',
                          trailing: Text(
                            '${categories.length} '
                            '${categories.length == 1 ? 'category' : 'categories'}',
                            style: SpendWiseType.eyebrow,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentBar(
                        weights: [
                          for (final item in categories)
                            categoryTotal == 0
                                ? 1
                                : item.amount.minorUnits / categoryTotal,
                        ],
                        colors: [
                          for (var i = 0; i < categories.length; i++)
                            SpendWiseColors.category(i),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: SpendWiseTheme.gutter,
              ),
              sliver: SliverList.builder(
                itemCount: categories.length,
                itemBuilder: (context, index) => _CategoryRow(
                  item: categories[index],
                  color: SpendWiseColors.category(index),
                  onTap: onSeeLedger,
                ),
              ),
            ),
            if (viewModel.uiShowSavingsOnHome)
              SliverToBoxAdapter(
                child: _SavingsStrip(
                  accounts: viewModel.accounts,
                  onTap: onOpenAccounts,
                ),
              ),
            SliverToBoxAdapter(
              child: _LoansNote(
                viewModel: viewModel,
                onOpenAccounts: onOpenAccounts,
              ),
            ),
            if (ownMoves.isNotEmpty)
              SliverToBoxAdapter(
                child: _OwnMovesNote(
                  moves: ownMoves,
                  onTap: onOpenAccounts,
                ),
              ),
            SliverToBoxAdapter(
              child: _TrayScan(viewModel: viewModel),
            ),
          ],
          SliverToBoxAdapter(
            child: SizedBox(
              height: 96 + MediaQuery.viewPaddingOf(context).bottom,
            ),
          ),
        ],
      ),
    );
  }

  static String _percent(int part, int whole) {
    if (whole <= 0) return '0%';
    final value = (part / whole) * 100;
    return '${value < 10 ? value.toStringAsFixed(1) : value.round()}%';
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.received,
    required this.kept,
    required this.spent,
  });

  final int received;
  final int kept;
  final int spent;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: _LegendEntry(
          label: kept < 0 ? 'Overspent' : 'Still yours',
          value: formatMinor(kept, cents: false),
          note: received > 0
              ? '${DashboardScreen._percent(kept.abs(), received)} of what came in'
              : 'nothing came in this month',
          color: kept < 0 ? SpendWiseColors.spend : SpendWiseColors.fg,
        ),
      ),
      _LegendEntry(
        label: 'Gone',
        value: formatMinor(spent, cents: false),
        note: DashboardScreen._percent(spent, received),
        color: SpendWiseColors.spend,
        alignRight: true,
      ),
    ],
  );
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({
    required this.label,
    required this.value,
    required this.note,
    required this.color,
    this.alignRight = false,
  });

  final String label;
  final String value;
  final String note;
  final Color color;
  final bool alignRight;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: alignRight
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      Eyebrow(label),
      const SizedBox(height: 4),
      Text(value, style: SpendWiseType.amount.copyWith(color: color)),
      const SizedBox(height: 2),
      Text(note, style: SpendWiseType.body.copyWith(fontSize: 12.5)),
    ],
  );
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.item,
    required this.color,
    required this.onTap,
  });

  final CategorySpendViewData item;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(width: 9, height: 9, color: color),
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
            formatAmount(item.amount, cents: false),
            style: SpendWiseType.rowStrong,
          ),
        ],
      ),
    ),
  );
}

/// Savings are deliberately absent from the month's shape -- money set aside
/// is neither kept nor spent this month. When the user asks to see it on Home,
/// it appears as its own band beneath the shape rather than being folded into
/// figures that would then mean something different.
class _SavingsStrip extends StatelessWidget {
  const _SavingsStrip({required this.accounts, required this.onTap});

  final List<AccountViewData> accounts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final savings = accounts.where((a) => !a.isIncluded).toList();
    if (savings.isEmpty) return const SizedBox.shrink();
    final total = savings.fold<int>(
      0,
      (sum, account) => sum + account.balance.minorUnits,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SpendWiseTheme.gutter,
        22,
        SpendWiseTheme.gutter,
        0,
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(top: 13),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: SpendWiseColors.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow(
                'Held back · savings',
                trailing: Text(
                  formatMinor(total, cents: false),
                  style: SpendWiseType.rowStrong.copyWith(fontSize: 14),
                ),
              ),
              const SizedBox(height: 10),
              for (final account in savings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 15,
                        color: SpendWiseColors.keep,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          account.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SpendWiseType.row.copyWith(fontSize: 13.5),
                        ),
                      ),
                      Text(
                        formatMinor(
                          account.balance.minorUnits,
                          cents: false,
                        ),
                        style: SpendWiseType.rowStrong.copyWith(fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                'Not counted as kept or spent this month.',
                style: SpendWiseType.body.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lending is the other reason the spend figure is smaller than a naive sum
/// of outgoing alerts, so it gets the same one-line treatment.
class _LoansNote extends StatelessWidget {
  const _LoansNote({required this.viewModel, required this.onOpenAccounts});

  final SpendWiseViewModel viewModel;
  final VoidCallback onOpenAccounts;

  @override
  Widget build(BuildContext context) {
    final open = viewModel.uiDebts.where((item) => !item.isSettled).toList();
    if (open.isEmpty) return const SizedBox.shrink();
    final lentOut = open.where((item) => item.lent).fold<int>(
      0,
      (sum, item) => sum + item.outstanding.minorUnits,
    );
    final owed = open.where((item) => !item.lent).fold<int>(
      0,
      (sum, item) => sum + item.outstanding.minorUnits,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SpendWiseTheme.gutter,
        20,
        SpendWiseTheme.gutter,
        0,
      ),
      child: InkWell(
        onTap: onOpenAccounts,
        child: Container(
          padding: const EdgeInsets.only(top: 13),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: SpendWiseColors.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (lentOut > 0)
                _LoanLine(
                  amount: lentOut,
                  tail: 'is out on loan — still yours, not spending.',
                  tone: SpendWiseColors.keep,
                ),
              if (lentOut > 0 && owed > 0) const SizedBox(height: 7),
              if (owed > 0)
                _LoanLine(
                  amount: owed,
                  tail: 'you owe — arrived, but not yours to keep.',
                  tone: SpendWiseColors.spend,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoanLine extends StatelessWidget {
  const _LoanLine({
    required this.amount,
    required this.tail,
    required this.tone,
  });

  final int amount;
  final String tail;
  final Color tone;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        margin: const EdgeInsets.only(right: 9, top: 5),
        width: 6,
        height: 6,
        color: tone,
      ),
      Expanded(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${formatMinor(amount, cents: false)} ',
                style: SpendWiseType.row.copyWith(
                  fontWeight: FontWeight.w600,
                  color: tone,
                ),
              ),
              TextSpan(
                text: tail,
                style: SpendWiseType.body.copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// The one place Home mentions own-account transfers: they are the reason the
/// spend figure above is smaller than a naive sum of outgoing alerts, so the
/// number is worth stating rather than hiding.
class _OwnMovesNote extends StatelessWidget {
  const _OwnMovesNote({required this.moves, required this.onTap});

  final List<TransactionViewData> moves;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = moves.fold<int>(
      0,
      (sum, item) => sum + item.amount.minorUnits.abs(),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SpendWiseTheme.gutter,
        20,
        SpendWiseTheme.gutter,
        0,
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(top: 13),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: SpendWiseColors.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(right: 8, top: 1),
                child: Text(
                  '⇄',
                  style: TextStyle(fontSize: 14, color: SpendWiseColors.mine),
                ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${formatMinor(total, cents: false)} ',
                        style: SpendWiseType.row.copyWith(
                          fontWeight: FontWeight.w600,
                          color: SpendWiseColors.mine,
                        ),
                      ),
                      TextSpan(
                        text: moves.length == 1
                            ? 'moved between your own accounts — not counted as spending.'
                            : 'moved between your own accounts across '
                                  '${moves.length} transfers — not counted as spending.',
                        style: SpendWiseType.body.copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Deliberately the quietest control on the screen. It exists because Android
/// can drop a notification before the listener wakes, not because anyone should
/// be pressing it every day.
class _TrayScan extends StatefulWidget {
  const _TrayScan({required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<_TrayScan> createState() => _TrayScanState();
}

class _TrayScanState extends State<_TrayScan> {
  bool running = false;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(SpendWiseTheme.gutter, 24, 0, 0),
    child: Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: running ? null : _scan,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: SpendWiseColors.dim,
          textStyle: SpendWiseType.metaTight.copyWith(
            color: SpendWiseColors.dim,
          ),
        ),
        child: Text(
          running ? 'SCANNING TRAY…' : 'MISSING SOMETHING? SCAN THE TRAY',
        ),
      ),
    ),
  );

  Future<void> _scan() async {
    setState(() => running = true);
    try {
      final result = await widget.viewModel.uiScanNotificationTray();
      if (!mounted) return;
      final message = switch (result.status) {
        NotificationTrayScanViewStatus.accessRequired =>
          'Notification access is off, so the tray cannot be read.',
        NotificationTrayScanViewStatus.listenerUnavailable =>
          'The capture service is not running yet. Try again in a moment.',
        NotificationTrayScanViewStatus.completed when result.queuedCount == 0 =>
          'Nothing new in the tray — everything there is already recorded.',
        NotificationTrayScanViewStatus.completed =>
          'Picked up ${result.queuedCount} '
              '${result.queuedCount == 1 ? 'alert' : 'alerts'} from the tray.',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not read the tray: $error')));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }
}
