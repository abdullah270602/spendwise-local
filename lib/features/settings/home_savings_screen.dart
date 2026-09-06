import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../dashboard/dashboard_screen.dart';
import '../dashboard/home_savings.dart';
import '../shell/spendwise_view_model.dart';

/// Choosing how saving appears on Home.
///
/// These are not skins on one answer. "What I put away" is a flow and belongs
/// in the shape; "what I have set aside" is a balance and cannot go there
/// without changing what the figures beside it mean. Each option is therefore
/// described by the question it answers, and shown against the real figures,
/// because the difference between them is invisible in the abstract.
class HomeSavingsScreen extends StatefulWidget {
  const HomeSavingsScreen({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<HomeSavingsScreen> createState() => _HomeSavingsScreenState();
}

class _HomeSavingsScreenState extends State<HomeSavingsScreen> {
  SpendWiseViewModel get viewModel => widget.viewModel;

  HomeSavingsStyle get _current => HomeSavingsStyle.fromId(
    viewModel.uiViewPreference('home_savings'),
    legacyOn: viewModel.uiShowSavingsOnHome,
  );

  void _choose(HomeSavingsStyle style) {
    viewModel.uiSetViewPreference('home_savings', style.id);
    // The old switch still drives anything that has not moved over yet, so it
    // is kept in step rather than left to contradict the choice.
    viewModel.uiSetShowSavingsOnHome(style != HomeSavingsStyle.off);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final savings = viewModel.accounts.where((a) => !a.isIncluded).toList();
    final now = DateTime.now();
    final (from, to) = viewModel.uiHomePeriod.resolve(now);
    final saved = savedInWindow(
      transactions: viewModel.transactions,
      savingsAccountIds: {for (final account in savings) account.id},
      from: from,
      to: to,
    );
    final held = savings.fold<int>(
      0,
      (sum, account) => sum + account.balance.minorUnits,
    );
    final dashboard = viewModel.dashboard;
    // Home's arithmetic, not an approximation of it. The whole reason this
    // preview draws the real widgets is that a preview which can disagree
    // with the screen it previews is worse than showing nothing.
    final heldDebtIds = {
      for (final debt in viewModel.uiDebts)
        if (debt.isHeld) debt.id,
    };
    final dueIn = debtInflowInWindow(
      transactions: viewModel.transactions,
      from: from,
      to: to,
      heldDebtIds: heldDebtIds,
    );
    final dueOut = debtOutflowInWindow(
      transactions: viewModel.transactions,
      from: from,
      to: to,
      heldDebtIds: heldDebtIds,
    );
    final received = dashboard.incomeThisMonth.minorUnits + dueIn;
    final spent = dashboard.spendingThisMonth.minorUnits;
    final kept = received - spent - dueOut;

    return Scaffold(
      appBar: AppBar(title: const Text('How Home counts savings')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          SpendWiseTheme.gutter,
          8,
          SpendWiseTheme.gutter,
          32 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          if (savings.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Text(
                'You have no savings accounts yet. Mark an account as Savings '
                'and these start meaning something.',
                style: SpendWiseType.body.copyWith(fontSize: 13),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Text(
                'Over the period Home covers you put away '
                '${formatMinor(saved, cents: false)}, and hold '
                '${formatMinor(held, cents: false)} in total.',
                style: SpendWiseType.body.copyWith(fontSize: 13),
              ),
            ),
          // One preview, at the size Home draws it, showing whatever is
          // selected. Six thumbnails said the same thing six times over and
          // none of them at a size where the difference was legible.
          _Preview(
            style: current,
            receivedMinor: received,
            keptMinor: kept,
            spentMinor: spent,
            savedMinor: saved,
            heldMinor: held,
          ),
          const SizedBox(height: 22),
          for (final style in HomeSavingsStyle.values)
            _Choice(
              style: style,
              selected: style == current,
              onTap: () => _choose(style),
            ),
          const SizedBox(height: 20),
          Text(
            'A balance and a movement answer different questions, so the shape '
            'only ever draws the movement. What you hold stays a band beneath '
            'it, where it cannot change what the figures above mean.',
            style: SpendWiseType.body.copyWith(
              fontSize: 12.5,
              color: SpendWiseColors.dim,
            ),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final HomeSavingsStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? SpendWiseColors.keep : SpendWiseColors.edge,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.only(top: 2, right: 13),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? SpendWiseColors.keep : SpendWiseColors.edge,
                  width: 1.5,
                ),
                color: selected ? SpendWiseColors.keep : Colors.transparent,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(style.title, style: SpendWiseType.rowStrong),
                  const SizedBox(height: 3),
                  Text(
                    style.detail,
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
    ),
  );
}

/// Home's own widgets, at Home's own size, drawn from the real figures.
///
/// Not an illustration of the choice -- the choice itself, rendered by the
/// same code the dashboard uses, so it cannot quietly stop matching.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.style,
    required this.receivedMinor,
    required this.keptMinor,
    required this.spentMinor,
    required this.savedMinor,
    required this.heldMinor,
  });

  final HomeSavingsStyle style;
  final int receivedMinor;
  final int keptMinor;
  final int spentMinor;
  final int savedMinor;
  final int heldMinor;

  @override
  Widget build(BuildContext context) {
    final aside = style.setsSavingAside && savedMinor > 0 ? savedMinor : 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        border: Border.all(color: SpendWiseColors.edge),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('On Home  ${formatMinor(receivedMinor, cents: false)} in'),
          const SizedBox(height: 10),
          FlowShape(
            height: 150,
            animate: false,
            receivedMinor: receivedMinor,
            keptMinor: style == HomeSavingsStyle.available
                ? keptMinor - aside
                : keptMinor,
            spentMinor: spentMinor,
            savedMinor: savedMinor,
            saved: switch (style) {
              HomeSavingsStyle.siblings => SavedTreatment.branch,
              HomeSavingsStyle.divided => SavedTreatment.inset,
              HomeSavingsStyle.seam => SavedTreatment.seam,
              _ => SavedTreatment.none,
            },
          ),
          const SizedBox(height: 14),
          MonthLegend(
            received: receivedMinor,
            kept: keptMinor,
            spent: spentMinor,
            savedMinor: savedMinor,
            setsSavingAside: style.setsSavingAside,
            namesTheSaving: style.namesTheSaving,
          ),
          if (style == HomeSavingsStyle.balance ||
              style == HomeSavingsStyle.moved) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 11),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: SpendWiseColors.line)),
              ),
              child: style == HomeSavingsStyle.balance
                  ? Eyebrow(
                      'Savings',
                      trailing: Text(
                        formatMinor(heldMinor, cents: false),
                        style: SpendWiseType.rowStrong.copyWith(fontSize: 14),
                      ),
                    )
                  : Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: formatMinor(savedMinor.abs(), cents: false),
                            style: SpendWiseType.rowStrong.copyWith(
                              fontSize: 15,
                            ),
                          ),
                          TextSpan(
                            text: savedMinor < 0
                                ? ' taken back out of savings.'
                                : ' put away this period.',
                            style: SpendWiseType.body.copyWith(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
