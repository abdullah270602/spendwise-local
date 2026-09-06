import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
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
    final received = dashboard.incomeThisMonth.minorUnits;
    final spent = dashboard.spendingThisMonth.minorUnits;
    final kept = received - spent;

    return Scaffold(
      appBar: AppBar(title: const Text('Savings on Home')),
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
          for (final style in HomeSavingsStyle.values)
            _Choice(
              style: style,
              selected: style == current,
              onTap: () => _choose(style),
              // Drawn from the real figures. Described in words these options
              // are indistinguishable -- the whole difference is what they
              // look like, so the choice has to be shown, not explained.
              preview: _Preview(
                style: style,
                receivedMinor: received,
                keptMinor: kept,
                spentMinor: spent,
                savedMinor: saved,
                heldMinor: held,
              ),
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
    required this.preview,
  });

  final HomeSavingsStyle style;
  final bool selected;
  final VoidCallback onTap;
  final Widget preview;

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
                  const SizedBox(height: 12),
                  preview,
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// What Home will actually look like, at a size that fits beside the words.
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
    final aside = style == HomeSavingsStyle.siblings && savedMinor > 0
        ? savedMinor
        : 0;
    final headline = keptMinor - aside;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FlowShape(
          height: 62,
          animate: false,
          receivedMinor: receivedMinor,
          keptMinor: keptMinor,
          spentMinor: spentMinor,
          savedMinor: savedMinor,
          saved: switch (style) {
            HomeSavingsStyle.siblings => SavedTreatment.branch,
            HomeSavingsStyle.divided => SavedTreatment.inset,
            HomeSavingsStyle.seam => SavedTreatment.seam,
            _ => SavedTreatment.none,
          },
        ),
        const SizedBox(height: 8),
        // The words under the shape move with it: counting saving out of the
        // headline means the headline is no longer "still yours".
        Row(
          children: [
            Expanded(
              child: _Chip(
                label: aside > 0 ? 'AVAILABLE' : 'STILL YOURS',
                value: formatMinor(headline, cents: false),
                color: SpendWiseColors.fg,
              ),
            ),
            if (aside > 0)
              _Chip(
                label: 'SAVED',
                value: formatMinor(aside, cents: false),
                color: SpendWiseColors.mine,
              ),
            _Chip(
              label: 'GONE',
              value: formatMinor(spentMinor, cents: false),
              color: SpendWiseColors.spend,
            ),
          ],
        ),
        if (style == HomeSavingsStyle.balance ||
            style == HomeSavingsStyle.moved) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.only(top: 7),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: SpendWiseColors.line)),
            ),
            child: Text(
              style == HomeSavingsStyle.balance
                  ? 'SAVINGS  ${formatMinor(heldMinor, cents: false)}'
                  : '${formatMinor(savedMinor, cents: false)} put away',
              style: SpendWiseType.metaTight,
            ),
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: SpendWiseType.metaTight.copyWith(fontSize: 8)),
        const SizedBox(height: 1),
        Text(
          value,
          style: SpendWiseType.rowStrong.copyWith(fontSize: 12, color: color),
        ),
      ],
    ),
  );
}
