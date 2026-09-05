import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/category_picker.dart';
import '../../widgets/shape_kit.dart';
import '../settings/source_selection_screen.dart';
import '../shell/spendwise_view_model.dart';
import '../transactions/transaction_details_screen.dart';
import 'review_rules.dart';

/// Review asks questions, not permissions. Fourteen uncertain alerts are not
/// fourteen decisions — they are usually two, and answering one settles the
/// whole group. One-by-one is still there for anyone who wants it.
class ReviewInboxScreen extends StatefulWidget {
  const ReviewInboxScreen({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<ReviewInboxScreen> createState() => _ReviewInboxScreenState();
}

class _ReviewInboxScreenState extends State<ReviewInboxScreen> {
  String? applying;

  @override
  Widget build(BuildContext context) {
    final rules = buildReviewRules(
      transactions: widget.viewModel.transactions,
      reviews: widget.viewModel.reviews,
      accounts: widget.viewModel.accounts,
      unroutedAlerts: widget.viewModel.uiUnroutedAlerts,
    );
    final alerts = rules.fold<int>(0, (sum, rule) => sum + rule.count);

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SpendWiseTheme.gutter,
                18,
                SpendWiseTheme.gutter,
                0,
              ),
              child: rules.isEmpty
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$alerts ${alerts == 1 ? 'alert' : 'alerts'}, '
                          '${rules.length} ${rules.length == 1 ? 'decision' : 'decisions'}.',
                          style: SpendWiseType.statement,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          'Answer once and SpendWise applies it to the rest.',
                          style: SpendWiseType.body.copyWith(fontSize: 13.5),
                        ),
                      ],
                    ),
            ),
          ),
          if (rules.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: RestState(
                headline: 'Nothing needs you.',
                detail:
                    'Every alert SpendWise captured was clear enough to '
                    'file on its own. Anything it cannot read will show up '
                    'here as a question, not a pile.',
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: SpendWiseTheme.gutter,
              ),
              sliver: SliverList.builder(
                itemCount: rules.length,
                itemBuilder: (context, index) => _RuleBlock(
                  rule: rules[index],
                  busy: applying == rules[index].id,
                  locked: applying != null,
                  onApply: () => _apply(rules[index]),
                  onAlternative: () => _alternative(rules[index]),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                SpendWiseTheme.gutter,
                22,
                SpendWiseTheme.gutter,
                96 + MediaQuery.viewPaddingOf(context).bottom,
              ),
                child: Container(
                  padding: const EdgeInsets.only(top: 13),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: SpendWiseColors.line),
                    ),
                  ),
                  child: Text(
                    rules.length == 1
                        ? 'Answering it clears the inbox.'
                        : 'Answering all ${rules.length} clears the inbox.',
                    style: SpendWiseType.body.copyWith(fontSize: 12.5),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _apply(ReviewRule rule) async {
    var decision = rule.decision;

    if (rule.needsAccount) {
      final accountId = await _pickAccount();
      if (accountId == null) return;
      decision = ReviewDecision(
        kind: decision.kind,
        transactionIds: decision.transactionIds,
        alertIds: decision.alertIds,
        accountId: accountId,
      );
    } else if (rule.needsCategory) {
      final category = await _pickCategory();
      if (category == null) return;
      decision = ReviewDecision(
        kind: ReviewDecisionKind.categorize,
        transactionIds: decision.transactionIds,
        category: category,
      );
    }

    setState(() => applying = rule.id);
    try {
      await widget.viewModel.uiApplyReviewDecision(decision);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            rule.count == 1
                ? 'Done — 1 alert settled.'
                : 'Done — ${rule.count} alerts settled in one go.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not apply that: $error')));
    } finally {
      if (mounted) setState(() => applying = null);
    }
  }

  /// The escape hatch. A rule about raw alerts opens the alerts themselves;
  /// a rule about parsed transactions opens them one at a time.
  void _alternative(ReviewRule rule) {
    if (rule.opensAlertReader) {
      _showAlerts(rule);
      return;
    }
    final ids = rule.decision.transactionIds.toSet();
    final items = widget.viewModel.transactions
        .where((item) => ids.contains(item.id))
        .toList();
    if (items.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        maxChildSize: .92,
        builder: (context, controller) => ListView.builder(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
            SpendWiseTheme.gutter,
            0,
            SpendWiseTheme.gutter,
            24,
          ),
          itemCount: items.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      items.length == 1
                          ? 'One alert, up close'
                          : '${items.length} alerts, one at a time',
                      style: SpendWiseType.title,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Swipe right to confirm, left to delete. Tap to open '
                      'the alert it came from.',
                      style: SpendWiseType.body.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              );
            }
            final item = items[index - 1];
            return _Swipeable(
              id: item.id,
              onConfirm: () => _confirmOne(item),
              onDelete: () => _deleteOne(item, sheetContext),
              child: RegisterRow(
                name: item.title,
                meta: [
                  item.category,
                  if (item.accountName.isNotEmpty) item.accountName,
                ].join(' · '),
                amount: formatAmount(item.amount),
                amountColor: switch (item.kind) {
                  TransactionKind.income => SpendWiseColors.keep,
                  TransactionKind.transfer => SpendWiseColors.mine,
                  TransactionKind.expense => SpendWiseColors.spend,
                },
                ownTransfer: item.kind == TransactionKind.transfer,
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => TransactionDetailsScreen(
                        viewModel: widget.viewModel,
                        transaction: item,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmOne(TransactionViewData item) async {
    try {
      await widget.viewModel.uiApplyReviewDecision(
        ReviewDecision(
          kind: ReviewDecisionKind.confirm,
          transactionIds: [item.id],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not confirm: $error')));
    }
  }

  /// Closes the sheet before deleting. A snackbar raised from inside a modal
  /// sheet renders behind it, so the Undo would be visible but untappable --
  /// an undo you cannot reach is worse than no undo at all.
  Future<void> _deleteOne(
    TransactionViewData item,
    BuildContext sheetContext,
  ) async {
    if (Navigator.canPop(sheetContext)) Navigator.pop(sheetContext);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.viewModel.deleteTransaction(item.id);
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Transaction deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => widget.viewModel.restoreTransaction(item.id),
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not delete: $error')),
      );
    }
  }

  /// The raw alerts, verbatim. Every rule above is a claim about these; this
  /// is where the user checks the claim rather than taking it on trust.
  void _showAlerts(ReviewRule rule) {
    final alerts = widget.viewModel.uiAlerts(
      packageName: rule.alertPackage,
      onlyUnresolved: true,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .78,
        maxChildSize: .94,
        builder: (context, controller) => Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(
                  SpendWiseTheme.gutter,
                  0,
                  SpendWiseTheme.gutter,
                  12,
                ),
                itemCount: alerts.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alerts.length == 1
                                ? 'The alert, verbatim'
                                : '${alerts.length} alerts, verbatim',
                            style: SpendWiseType.title,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Exactly what arrived, and what SpendWise made of it.',
                            style: SpendWiseType.body.copyWith(fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  }
                  return _AlertCard(alert: alerts[index - 1]);
                },
              ),
            ),
            // Pinned: on a pile of twenty alerts this was previously the last
            // row of the list, which is to say invisible.
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  SpendWiseTheme.gutter,
                  8,
                  SpendWiseTheme.gutter,
                  12,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => SourceSelectionScreen(
                            viewModel: widget.viewModel,
                          ),
                        ),
                      );
                    },
                    child: const Text('Manage notification sources'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickAccount() {
    final accounts = widget.viewModel.accounts;
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add an account first — there is nowhere to file these.',
          ),
        ),
      );
      return Future.value();
    }
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SpendWiseTheme.gutter,
                0,
                SpendWiseTheme.gutter,
                14,
              ),
              child: Text('Which account?', style: SpendWiseType.title),
            ),
            for (final account in accounts)
              ListTile(
                title: Text(account.name, style: SpendWiseType.row),
                subtitle: Text(
                  [
                    if (account.institution.isNotEmpty) account.institution,
                    if (account.suffix.isNotEmpty) '••${account.suffix}',
                  ].join(' · '),
                  style: SpendWiseType.metaTight,
                ),
                onTap: () => Navigator.pop(sheetContext, account.id),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickCategory() =>
      pickCategory(context, viewModel: widget.viewModel);
}

class _Swipeable extends StatelessWidget {
  const _Swipeable({
    required this.id,
    required this.child,
    required this.onConfirm,
    required this.onDelete,
  });

  final String id;
  final Widget child;
  final Future<void> Function() onConfirm;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) => Dismissible(
    key: ValueKey('review-$id'),
    background: _SwipeHint(
      label: 'CONFIRM',
      tone: SpendWiseColors.keep,
      alignment: Alignment.centerLeft,
    ),
    secondaryBackground: _SwipeHint(
      label: 'DELETE',
      tone: SpendWiseColors.spend,
      alignment: Alignment.centerRight,
    ),
    onDismissed: (direction) {
      if (direction == DismissDirection.startToEnd) {
        onConfirm();
      } else {
        onDelete();
      }
    },
    child: child,
  );
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint({
    required this.label,
    required this.tone,
    required this.alignment,
  });

  final String label;
  final Color tone;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Container(
    color: tone,
    alignment: alignment,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Text(
      label,
      style: const TextStyle(
        fontFamily: SpendWiseType.sans,
        fontSize: 11,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w700,
        color: SpendWiseColors.bg,
      ),
    ),
  );
}

/// One captured alert: when it arrived, what it said, and where it ended up.
class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final AlertViewData alert;

  @override
  Widget build(BuildContext context) {
    final stamp = alert.observedAt;
    final when =
        '${stamp.day.toString().padLeft(2, '0')} '
        '${_months[stamp.month - 1]} '
        '${stamp.hour.toString().padLeft(2, '0')}:'
        '${stamp.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.only(top: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SpendWiseColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$when · ${alert.sourceLabel}'.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SpendWiseType.metaTight,
                ),
              ),
              Text(
                _statusLabel(alert),
                style: SpendWiseType.metaTight.copyWith(
                  color: _statusColor(alert),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          if (alert.title.isNotEmpty) ...[
            Text(alert.title, style: SpendWiseType.rowStrong),
            const SizedBox(height: 3),
          ],
          Text(
            alert.body,
            style: SpendWiseType.meta.copyWith(
              fontSize: 11.5,
              color: SpendWiseColors.fg,
              height: 1.5,
            ),
          ),
          if (alert.reason case final reason? when reason.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(reason, style: SpendWiseType.body.copyWith(fontSize: 12)),
          ],
        ],
      ),
    );
  }

  static const _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];

  static String _statusLabel(AlertViewData alert) {
    if (alert.reachedLedger) return alert.accountName ?? 'FILED';
    if (alert.ignored) return 'IGNORED';
    return alert.accountName == null ? 'NO ACCOUNT' : 'UNREAD';
  }

  static Color _statusColor(AlertViewData alert) => alert.reachedLedger
      ? SpendWiseColors.keep
      : alert.ignored
      ? SpendWiseColors.dim
      : SpendWiseColors.spend;
}

class _RuleBlock extends StatelessWidget {
  const _RuleBlock({
    required this.rule,
    required this.busy,
    required this.locked,
    required this.onApply,
    required this.onAlternative,
  });

  final ReviewRule rule;
  final bool busy;
  final bool locked;
  final VoidCallback onApply;
  final VoidCallback onAlternative;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 20),
    padding: const EdgeInsets.only(top: 17),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: SpendWiseColors.edge)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${rule.count}',
              style: SpendWiseType.figure.copyWith(
                fontSize: 38,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.6,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                rule.unit,
                style: SpendWiseType.body.copyWith(fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(rule.claim, style: SpendWiseType.lead),
        if (rule.evidence case final evidence?) ...[
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.only(left: 11),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: SpendWiseColors.edge, width: 2),
              ),
            ),
            child: _Evidence(text: evidence, highlights: rule.highlights),
          ),
        ],
        const SizedBox(height: 13),
        PrimaryAction(
          label: rule.actionLabel,
          busy: busy,
          onPressed: locked && !busy ? null : onApply,
        ),
        if (rule.alternative case final alternative?) ...[
          const SizedBox(height: 9),
          InkWell(
            onTap: locked ? null : onAlternative,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      alternative,
                      style: SpendWiseType.body.copyWith(
                        fontSize: 12.5,
                        decoration: TextDecoration.underline,
                        decorationColor: SpendWiseColors.edge,
                      ),
                    ),
                  ),
                  Text('${rule.count}', style: SpendWiseType.metaTight),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// Quotes the alert verbatim and marks the phrases the decision turned on, so
/// the user can see why SpendWise thinks what it thinks rather than trust it.
class _Evidence extends StatelessWidget {
  const _Evidence({required this.text, required this.highlights});

  final String text;
  final List<String> highlights;

  @override
  Widget build(BuildContext context) {
    final base = SpendWiseType.meta.copyWith(fontSize: 11.5, height: 1.55);
    if (highlights.isEmpty) {
      return Text(text, style: base);
    }
    final pattern = RegExp(
      highlights.map(RegExp.escape).join('|'),
      caseSensitive: false,
    );
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: TextStyle(color: SpendWiseColors.spend),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }
}
