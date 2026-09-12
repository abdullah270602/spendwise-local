import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/failure_text.dart';
import '../../app/theme.dart';
import '../../widgets/category_picker.dart';
import '../../widgets/shape_kit.dart';
import '../capture/capture_state.dart';
import '../settings/source_selection_screen.dart';
import '../shell/spendwise_view_model.dart';
import '../transactions/transaction_details_screen.dart';
import 'review_rules.dart';

/// What the ledger held at one moment: how many entries it has, and how much
/// of the question being answered was still open.
typedef _Reading = ({int entries, int waiting});

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

  /// Which answer is running, so its own button carries the spinner.
  ReviewAction? applyingAction;

  /// The rule that was just answered, held for a moment after the ledger has
  /// stopped returning it.
  ///
  /// Without this the card simply vanished and the list jumped up a slot,
  /// which reads as lag however fast the work was, and the only confirmation
  /// was a toast at the bottom edge -- easy to miss entirely on a screen the
  /// user has scrolled. The answer is now stated where the question was.
  ReviewRule? settled;
  String? settledId;

  /// What the answer settled, and how much it was asked to settle. Two numbers
  /// because they are allowed to differ, and the difference is the user's to
  /// see: an answer that reached only half the pile has to say half.
  int settledCount = 0;
  int settledOf = 0;

  /// What "drop" hid, so it can be put back. Null for answers that are not
  /// destructive: filing and attaching are undone by editing the entry they
  /// created, which the ledger already offers.
  Map<String, String>? undoStatuses;

  @override
  Widget build(BuildContext context) {
    final rules = buildReviewRules(
      transactions: widget.viewModel.transactions,
      reviews: widget.viewModel.reviews,
      accounts: widget.viewModel.accounts,
      unroutedAlerts: widget.viewModel.uiUnroutedAlerts,
      debts: widget.viewModel.uiDebts,
    );
    final alerts = rules.fold<int>(0, (sum, rule) => sum + rule.count);

    // The answered rule is gone from the ledger's own list, so it is spliced
    // back at its old position for as long as its answer is on screen. Its
    // place in the order is part of the answer: it says which question was
    // just settled.
    final answered = settled;
    final shown = answered == null || rules.any((r) => r.id == answered.id)
        ? rules
        : [...rules, answered];
    // The rest state waits until the answer has been read. An answer that
    // clears the last question used to be replaced instantly by "Nothing
    // needs you", which is the one moment the user most needs to be told what
    // just happened -- and if the answer settled less than it was asked to,
    // an empty screen is the app claiming otherwise.
    final resting = shown.isEmpty;
    final gap = captureGap(widget.viewModel);

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
          if (resting)
            SliverFillRemaining(
              hasScrollBody: false,
              // "Every alert SpendWise captured was clear enough to file on
              // its own" is a report on work that never happened when nothing
              // is being read -- and it is the state a new install is in, so
              // it was the first thing most people saw here. An empty inbox
              // means the app is working only when capture is running.
              child: gap == null
                  ? const RestState(
                      headline: 'Nothing needs you.',
                      detail:
                          'Every alert SpendWise captured was clear enough to '
                          'file on its own. Anything it cannot read will show '
                          'up here as a question, not a pile.',
                    )
                  : RestState(
                      headline: 'Nothing has been captured.',
                      detail: gap.detail,
                      action: gap.action,
                    ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: SpendWiseTheme.gutter,
              ),
              sliver: SliverList.builder(
                itemCount: shown.length,
                itemBuilder: (context, index) {
                  final rule = shown[index];
                  if (rule.id == settledId) {
                    return _SettledBlock(
                      count: settledCount,
                      of: settledOf,
                      onUndo: undoStatuses == null ? null : _undo,
                      onDone: _clearSettled,
                    );
                  }
                  return _RuleBlock(
                    rule: rule,
                    busyAction: applying == rule.id ? applyingAction : null,
                    locked: applying != null,
                    onApply: (action) => _apply(rule, action),
                    onAlternative: () => _alternative(rule),
                  );
                },
              ),
            ),
            if (rules.isNotEmpty)
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

  Future<void> _apply(ReviewRule rule, ReviewAction action) async {
    var decision = action.decision;

    // Asked one after another rather than one instead of another: filing needs
    // both the account and the direction, and collecting only the direction
    // was how the answer came to be applied with nothing to apply it to. The
    // account goes first because it is the question that can turn out to have
    // no answer at all, and finding that out afterwards wastes the other one.
    if (action.needsAccount) {
      final accountId = await _pickAccount();
      if (accountId == null || !mounted) return;
      decision = _answered(decision, accountId: accountId);
    }
    if (action.needsDirection) {
      final expense = await _askDirection(rule);
      if (expense == null || !mounted) return;
      decision = _answered(decision, expense: expense);
    }
    if (action.needsCategory) {
      final category = await _pickCategory();
      if (category == null || !mounted) return;
      decision = _answered(decision, category: category);
    }

    // Captured before the change, because afterwards there is no query that
    // can tell which rows this particular answer touched.
    final undo = decision.kind == ReviewDecisionKind.dismissSource
        ? widget.viewModel.uiUnresolvedAlertStatuses(decision.packageName)
        : null;

    // What the rule covers is what the answer is meant to settle; what the
    // ledger managed is a different number, and it is the one the user is
    // owed. Filing cannot rescue an alert with no readable amount, and an
    // answer about an app names the app rather than a list of rows, so the
    // size of the job is not knowable until it has run. Reading the ledger on
    // either side of the answer is the only figure that is a fact rather than
    // an expectation, and this screen exists to print facts.
    final before = _read(decision);

    setState(() {
      applying = rule.id;
      applyingAction = action;
    });
    try {
      await widget.viewModel.uiApplyReviewDecision(decision);
      if (!mounted) return;
      setState(() {
        settled = rule;
        settledId = rule.id;
        settledCount = _settledBetween(decision, before, _read(decision));
        settledOf = before.waiting;
        undoStatuses = undo != null && undo.isNotEmpty ? undo : null;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failureText('Could not apply that', error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          applying = null;
          applyingAction = null;
        });
      }
    }
  }

  /// One question answered, folded back into the decision. Every other field
  /// is carried through: a rule that needs two answers would otherwise lose
  /// the first one to the second, and an alert answer that loses its package
  /// name stops naming the alerts it is about.
  ReviewDecision _answered(
    ReviewDecision decision, {
    String? accountId,
    bool? expense,
    String? category,
  }) => ReviewDecision(
    kind: decision.kind,
    transactionIds: decision.transactionIds,
    alertIds: decision.alertIds,
    packageName: decision.packageName,
    accountId: accountId ?? decision.accountId,
    expense: expense ?? decision.expense,
    category: category ?? decision.category,
  );

  /// One reading of the ledger. Taken either side of an answer, the difference
  /// between two of them is what the answer did, which is not always what it
  /// was asked to do.
  _Reading _read(ReviewDecision decision) => (
    entries: widget.viewModel.transactions.length,
    waiting: switch (decision.kind) {
      ReviewDecisionKind.fileAlerts ||
      ReviewDecisionKind.routeAlerts ||
      ReviewDecisionKind.dismissSource =>
        widget.viewModel.uiUnresolvedAlertStatuses(decision.packageName).length,
      _ =>
        widget.viewModel.transactions
            .where(
              (item) =>
                  decision.transactionIds.contains(item.id) && !item.isReviewed,
            )
            .length,
    },
  );

  /// What an answer settled, in the terms that answer was given in.
  ///
  /// Filing and attaching are judged by what they wrote, not by how much of
  /// the inbox they emptied: an alert whose amount is still unreadable is
  /// marked read-and-ignored rather than left waiting, so an inbox that empties
  /// is no evidence at all that anything reached the ledger. Everything else
  /// settles by leaving the queue, which is exactly what it promised to do.
  int _settledBetween(
    ReviewDecision decision,
    _Reading before,
    _Reading after,
  ) => switch (decision.kind) {
    ReviewDecisionKind.fileAlerts || ReviewDecisionKind.routeAlerts =>
      (after.entries - before.entries).clamp(0, before.waiting),
    _ => (before.waiting - after.waiting).clamp(0, before.waiting),
  };

  void _clearSettled() {
    if (!mounted) return;
    setState(() {
      settled = null;
      settledId = null;
      undoStatuses = null;
    });
  }

  Future<void> _undo() async {
    final statuses = undoStatuses;
    if (statuses == null) return;
    _clearSettled();
    try {
      await widget.viewModel.uiRestoreAlerts(statuses);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failureText('Could not undo that', error))),
      );
    }
  }

  /// The escape hatch. A rule about raw alerts opens the alerts themselves;
  /// a rule about parsed transactions opens them one at a time.
  void _alternative(ReviewRule rule) {
    if (rule.opensAlertReader) {
      _showAlerts(rule);
      return;
    }
    final ids = rule.primary.decision.transactionIds.toSet();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failureText('Could not confirm', error))),
      );
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
        SnackBar(content: Text(failureText('Could not delete', error))),
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

  /// The one thing the parser could not read. Everything else about these
  /// alerts -- the amount, who it was with, the reference -- it already has.
  Future<bool?> _askDirection(ReviewRule rule) => showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rule.count == 1
                ? 'Which way did the money go?'
                : 'Which way did the money go, for all ${rule.count}?',
            style: SpendWiseType.title,
          ),
          const SizedBox(height: 6),
          Text(
            'SpendWise read the amount but not the direction.',
            style: SpendWiseType.body.copyWith(fontSize: 12.5),
          ),
          const SizedBox(height: 18),
          PrimaryAction(
            label: 'Money out',
            onPressed: () => Navigator.pop(sheetContext, true),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Navigator.pop(sheetContext, false),
            child: const Text('Money in'),
          ),
        ],
      ),
    ),
  );

  Future<String?> _pickAccount() {
    // Never the cash pocket. These are bank alerts looking for somewhere to
    // land, and cash is the one account no alert can belong to -- offering it
    // to somebody who has added nothing else files their bank's money into
    // their pocket, silently and wrongly.
    final accounts = widget.viewModel.accounts
        .where((item) => !item.isCash)
        .toList(growable: false);
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add an account first. There is nowhere to file these.',
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
    required this.busyAction,
    required this.locked,
    required this.onApply,
    required this.onAlternative,
  });

  final ReviewRule rule;

  /// The answer the user actually tapped, while it is running.
  ///
  /// Keyed to the action rather than the rule because a rule now offers
  /// three: tapping "Drop it" used to spin the *primary* button, which the
  /// user had not touched, while the button they did touch just went grey.
  final ReviewAction? busyAction;
  final bool locked;

  /// Takes the answer the user tapped, since a rule can offer several.
  final void Function(ReviewAction action) onApply;
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
          label: rule.primary.label,
          busy: busyAction == rule.primary,
          onPressed: locked && busyAction != rule.primary
              ? null
              : () => onApply(rule.primary),
        ),
        // The follow-up answers share one row at equal width. Stacked, the
        // wider button read as the more important one purely because its
        // label was longer, which is not a judgement the layout should be
        // making. Beyond two they stack, since three across a phone leaves
        // room for a word each.
        if (rule.actions.length > 1) ...[
          const SizedBox(height: 9),
          if (rule.actions.length == 3)
            Row(
              children: [
                Expanded(
                  child: _SecondaryAction(
                    action: rule.actions[1],
                    busy: busyAction == rule.actions[1],
                    enabled: !locked,
                    onPressed: onApply,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _SecondaryAction(
                    action: rule.actions[2],
                    busy: busyAction == rule.actions[2],
                    enabled: !locked,
                    onPressed: onApply,
                  ),
                ),
              ],
            )
          else
            for (final action in rule.actions.skip(1)) ...[
              _SecondaryAction(
                action: action,
                busy: busyAction == action,
                enabled: !locked,
                onPressed: onApply,
              ),
              if (action != rule.actions.last) const SizedBox(height: 9),
            ],
        ],
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
/// A follow-up answer.
///
/// Full-width by design: the row above decides how much space it gets, so two
/// of these side by side are the same size whatever their labels say.
/// The answer, stated where the question was.
///
/// Holds long enough to be read and to be taken back, then collapses out of
/// the list. The undo lives here rather than in a toast at the bottom edge:
/// dropping alerts is the one answer with no other way back, and a
/// confirmation the user has to go looking for is not a confirmation.
class _SettledBlock extends StatefulWidget {
  const _SettledBlock({
    required this.count,
    required this.of,
    required this.onUndo,
    required this.onDone,
  });

  /// What the ledger settled, counted rather than assumed.
  final int count;

  /// What the question covered. Equal to [count] most of the time; when it is
  /// not, the shortfall is stated instead of rounded up, and the question
  /// comes back underneath for whatever is left of it.
  final int of;
  final Future<void> Function()? onUndo;
  final VoidCallback onDone;

  @override
  State<_SettledBlock> createState() => _SettledBlockState();
}

class _SettledBlockState extends State<_SettledBlock> {
  static const _hold = Duration(seconds: 4);
  static const _collapse = Duration(milliseconds: 260);

  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    // A shorter hold when there is nothing to take back: the line is then
    // only a receipt, and a receipt does not need four seconds.
    _timer = Timer(
      widget.onUndo == null ? const Duration(milliseconds: 1200) : _hold,
      _leave,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _leave() {
    if (!mounted) return;
    setState(() => _leaving = true);
    Future<void>.delayed(_collapse, () {
      if (mounted) widget.onDone();
    });
  }

  /// The whole point of the line. An answer that reached nothing says so, and
  /// one that reached part of the pile names the part, because the alternative
  /// is a receipt for work the ledger never did.
  String get _receipt {
    if (widget.count == 0) return 'Nothing settled.';
    if (widget.count < widget.of) {
      return '${widget.count} of ${widget.of} alerts settled.';
    }
    return widget.count == 1
        ? '1 alert settled.'
        : '${widget.count} alerts settled.';
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final undo = widget.onUndo;
    return AnimatedSize(
      duration: reduce ? Duration.zero : _collapse,
      curve: Curves.easeIn,
      alignment: Alignment.topCenter,
      child: _leaving
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 26, bottom: 4),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 11),
                    color: SpendWiseColors.keep,
                  ),
                  Expanded(
                    child: Text(
                      _receipt,
                      style: SpendWiseType.body.copyWith(fontSize: 13.5),
                    ),
                  ),
                  if (undo != null)
                    TextButton(
                      onPressed: () {
                        _timer?.cancel();
                        undo();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: SpendWiseColors.fg,
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text('Undo'),
                    ),
                ],
              ),
            ),
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.action,
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  final ReviewAction action;

  /// Shown on the button that was tapped. The primary carries its spinner on
  /// a filled ground, so it draws in the background tone; this one is an
  /// outline, so it draws in the foreground.
  final bool busy;
  final bool enabled;
  final void Function(ReviewAction action) onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: enabled && !busy ? () => onPressed(action) : null,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(46),
      foregroundColor: action.destructive ? SpendWiseColors.spend : null,
    ),
    child: busy
        ? SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: action.destructive
                  ? SpendWiseColors.spend
                  : SpendWiseColors.fg,
            ),
          )
        : Text(
            action.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
  );
}

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
