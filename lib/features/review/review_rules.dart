import '../debts/debt_matching.dart';
import '../shell/spendwise_view_model.dart';

/// A Review rule: one question that resolves many alerts at once.
///
/// The old inbox listed every uncertain transaction and asked the user to
/// confirm each. That is the opposite of saving anyone time -- if ten alerts
/// are uncertain for the same reason, there is one question, not ten. A rule
/// names the reason, quotes the evidence, and carries the decision that
/// answers it for the whole group.
/// One answer a rule offers.
///
/// The requirements live here rather than on the rule because a rule can offer
/// several answers that need different things: attaching alerts to an account
/// needs an account, filing them as transactions needs a direction, and
/// dropping them needs nothing. Hanging those flags off the rule forced every
/// answer to share one set, which is why the rule that most needed a second
/// answer could not have one.
class ReviewAction {
  const ReviewAction({
    required this.label,
    required this.decision,
    this.needsAccount = false,
    this.needsCategory = false,
    this.needsDirection = false,
    this.destructive = false,
  });

  final String label;
  final ReviewDecision decision;

  /// The action cannot run until the user picks a target.
  final bool needsAccount;
  final bool needsCategory;

  /// The action cannot run until the user says which way the money went. The
  /// parser read everything else; this is the half it could not.
  final bool needsDirection;

  /// Throws evidence away, so it is drawn last and quietest. It is still a
  /// real answer -- a rule that only offers destruction is not offering a
  /// choice, and a rule that hides it forces the user to file spam.
  final bool destructive;
}

class ReviewRule {
  const ReviewRule({
    required this.id,
    required this.count,
    required this.unit,
    required this.claim,
    required this.actions,
    this.evidence,
    this.highlights = const [],
    this.alternative,
    this.alertPackage,
    this.readableAlerts = 0,
  }) : assert(actions.length > 0, 'a question with no answer is a statement');

  /// Stable across rebuilds so a resolving row does not jump.
  final String id;

  /// How many alerts this one tap settles.
  final int count;

  /// Reads under the count: "alerts from Meezan".
  final String unit;

  /// What SpendWise believes about them, in the user's words.
  final String claim;

  /// A verbatim sample so the belief is checkable, not asserted.
  final String? evidence;

  /// Phrases inside [evidence] that carried the decision.
  final List<String> highlights;

  /// The escape hatch, when there is one.
  final String? alternative;

  /// Every answer on offer, the constructive one first. The screen draws the
  /// first as the primary action and the rest beneath it, in order.
  final List<ReviewAction> actions;

  ReviewAction get primary => actions.first;

  /// Set when the rule is about raw alerts rather than parsed transactions,
  /// so the screen can offer to open the alerts themselves. A rule the user
  /// cannot check is an assertion, not an explanation.
  final String? alertPackage;
  final int readableAlerts;

  bool get opensAlertReader => readableAlerts > 0;
}

const _uncategorized = {'uncategorized', 'unknown', 'other', ''};

/// Phrases that mean money left the account even though the sentence leads
/// with a credit verb -- the single most common misread in Pakistani bank SMS,
/// and the reason a pile of card purchases can land as income.
final _debitInCreditClothing = RegExp(
  r'credited\s+to\b(?![^.]*\byour\s+account\b)|from\s+your\s+(?:account|a/?c)',
  caseSensitive: false,
);

/// Groups everything still awaiting a decision into as few rules as possible.
/// Order matters: a specific, confident rule must come before the catch-all,
/// or every alert collapses into "confirm these" and the user learns nothing.
List<ReviewRule> buildReviewRules({
  required List<TransactionViewData> transactions,
  required List<ReviewViewData> reviews,
  required List<AccountViewData> accounts,
  List<AlertViewData> unroutedAlerts = const [],
  List<DebtViewData> debts = const [],
}) {
  final pending = transactions.where((item) => !item.isReviewed).toList();
  final claimed = <String>{};
  final rules = <ReviewRule>[];

  List<TransactionViewData> take(bool Function(TransactionViewData) predicate) {
    final matched = pending
        .where((item) => !claimed.contains(item.id) && predicate(item))
        .toList();
    claimed.addAll(matched.map((item) => item.id));
    return matched;
  }

  // Alerts that look like money but reached no account are a *subset* of the
  // alerts an app failed to deliver, not a separate pile: both queries filter
  // on the same parse_status, and one adds `account_id IS NULL`. Asking about
  // them separately counted the same alert twice and put the same alert on
  // screen as two questions with two different answers. They are kept here
  // only to quote a real body, and are answered by the per-app rule below.
  final unroutedByPackage = <String, List<AlertViewData>>{};
  for (final alert in unroutedAlerts) {
    final package = alert.packageName;
    if (package == null || package.isEmpty) continue;
    unroutedByPackage.putIfAbsent(package, () => []).add(alert);
  }

  // 1. Direction is wrong. Highest value: it changes the numbers, not just the
  //    review state, so it has to be asked before anything gets confirmed.
  final misread = take(
    (item) =>
        item.kind == TransactionKind.income &&
        item.evidence.any((e) => _debitInCreditClothing.hasMatch(e.body)),
  );
  if (misread.isNotEmpty) {
    final sample = misread.first.evidence
        .where((e) => _debitInCreditClothing.hasMatch(e.body))
        .first;
    rules.add(
      ReviewRule(
        id: 'redirect',
        count: misread.length,
        unit: _fromSource(misread),
        claim: 'Money "credited to" someone else, from your account.',
        evidence: _trim(sample.body),
        highlights: const ['credited to', 'from your account'],
        alternative: 'They really were money in',
        actions: [
          ReviewAction(
            label: misread.length == 1
                ? 'Treat it as money out'
                : 'Treat all ${misread.length} as money out',
            decision: ReviewDecision(
              kind: ReviewDecisionKind.redirect,
              transactionIds: [for (final item in misread) item.id],
            ),
          ),
        ],
      ),
    );
  }

  // 2. No account matched. Nothing reaches a balance until this is answered,
  //    so it outranks categorisation.
  // 2. A loan coming home. Second only to a misread direction, and for the
  //    same reason: confirming one of these as ordinary money is not a
  //    filing mistake, it is a month that says the owner earned what they
  //    only got back. Asked per loan, because the answer names one.
  //
  //    Each entry goes to its *best* loan rather than to the first one that
  //    fits. Two loans of the same size both match a payment of that size on
  //    the amount alone, and whichever was asked first would otherwise claim
  //    a payment that carries the other one's name.
  // Only loans with money still out. Correcting one that was settled by
  // typing the figure in is a deliberate act on the loan itself, not a
  // question to put in front of somebody clearing their alerts.
  final stillOut = debts
      .where((debt) => debt.outstanding.minorUnits > 0)
      .toList();
  final byLoan = <String, List<TransactionViewData>>{};
  for (final item in pending) {
    if (claimed.contains(item.id)) continue;
    final best = debtMatchesFor(transaction: item, debts: stillOut).firstOrNull;
    if (best == null) continue;
    byLoan.putIfAbsent(best.debt.id, () => []).add(item);
  }
  for (final debt in stillOut) {
    final candidates = byLoan[debt.id] ?? const <TransactionViewData>[];
    if (candidates.isEmpty) continue;
    claimed.addAll(candidates.map((item) => item.id));
    final one = candidates.length == 1;
    final incoming = debt.lent;
    rules.add(
      ReviewRule(
        id: 'loan-${debt.id}',
        count: candidates.length,
        unit: _fromSource(candidates),
        claim: incoming
            ? '${debt.counterparty} has money out with you. This looks '
                  'like it coming back.'
            : 'This looks like ${debt.counterparty} being paid back.',
        evidence: _sampleTitles(candidates),
        actions: [
          ReviewAction(
            label: one
                ? 'Record it against the loan'
                : 'Record all ${candidates.length} against the loan',
            decision: ReviewDecision(
              kind: ReviewDecisionKind.settleLoan,
              transactionIds: [for (final item in candidates) item.id],
              debtId: debt.id,
            ),
          ),
          // The refusal has to be an answer too. Without it the question
          // has no way to go away, and a rule that cannot be answered no
          // is a rule that outlives the truth.
          ReviewAction(
            label: incoming
                ? 'No, it is ordinary money in'
                : 'No, it is ordinary spending',
            decision: ReviewDecision(
              kind: ReviewDecisionKind.confirm,
              transactionIds: [for (final item in candidates) item.id],
            ),
          ),
        ],
      ),
    );
  }

  // Both must be missing: a transaction can carry a readable account label
  // without an id (manual entries, legacy rows), and claiming those are
  // unrouted would send the user shopping for an account they already picked.
  final unrouted = take(
    (item) =>
        item.kind != TransactionKind.transfer &&
        item.accountId == null &&
        item.accountName.trim().isEmpty,
  );
  if (unrouted.isNotEmpty) {
    rules.add(
      ReviewRule(
        id: 'route',
        count: unrouted.length,
        unit: _fromSource(unrouted),
        claim: accounts.isEmpty
            ? 'No account matched. You have not set one up yet.'
            : 'No account matched. Nothing here has reached a balance.',
        evidence: _sampleBody(unrouted),
        alternative: accounts.isEmpty ? null : 'Handle them one by one',
        actions: [
          ReviewAction(
            label: unrouted.length == 1
                ? 'Choose its account'
                : 'Send all ${unrouted.length} to one account',
            needsAccount: true,
            decision: ReviewDecision(
              kind: ReviewDecisionKind.route,
              transactionIds: [for (final item in unrouted) item.id],
            ),
          ),
        ],
      ),
    );
  }

  // 3. Own-account moves. These are the ones the user most wants recognised,
  //    and confirming them keeps them out of the spend figure.
  final ownMoves = take((item) => item.kind == TransactionKind.transfer);
  if (ownMoves.isNotEmpty) {
    rules.add(
      ReviewRule(
        id: 'transfer',
        count: ownMoves.length,
        unit: ownMoves.length == 1
            ? 'suspected own transfer'
            : 'suspected own transfers',
        claim: 'Money moved between accounts you own. Not spending.',
        evidence: _sampleTitles(ownMoves),
        alternative: 'Some went to someone else',
        actions: [
          ReviewAction(
            label: ownMoves.length == 1
                ? 'Yes, that was my own move'
                : 'Yes, all ${ownMoves.length} were my own moves',
            decision: ReviewDecision(
              kind: ReviewDecisionKind.confirm,
              transactionIds: [for (final item in ownMoves) item.id],
            ),
          ),
        ],
      ),
    );
  }

  // 4. Filed but uncategorised. Cosmetic next to the above, so it comes last
  //    among the shaped rules.
  final uncategorised = take(
    (item) =>
        item.kind == TransactionKind.expense &&
        _uncategorized.contains(item.category.trim().toLowerCase()),
  );
  if (uncategorised.isNotEmpty) {
    rules.add(
      ReviewRule(
        id: 'categorize',
        count: uncategorised.length,
        unit: _fromSource(uncategorised),
        claim: 'Read correctly, but not filed under anything yet.',
        evidence: _sampleTitles(uncategorised),
        alternative: 'They belong in different categories',
        actions: [
          ReviewAction(
            label: uncategorised.length == 1
                ? 'File it'
                : 'File all ${uncategorised.length} together',
            needsCategory: true,
            decision: ReviewDecision(
              kind: ReviewDecisionKind.categorize,
              transactionIds: [for (final item in uncategorised) item.id],
            ),
          ),
        ],
      ),
    );
  }

  // 5. Everything else, grouped by the account it landed on, so "confirm these"
  //    is still a statement about something rather than a bulk button.
  final remaining = take((_) => true);
  final byAccount = <String, List<TransactionViewData>>{};
  for (final item in remaining) {
    byAccount.putIfAbsent(item.accountName, () => []).add(item);
  }
  final accountNames = byAccount.keys.toList()
    ..sort((a, b) => byAccount[b]!.length.compareTo(byAccount[a]!.length));
  for (final name in accountNames) {
    final group = byAccount[name]!;
    final out = group.where((i) => i.kind == TransactionKind.expense).length;
    rules.add(
      ReviewRule(
        id: 'confirm:$name',
        count: group.length,
        unit: name.isEmpty
            ? (group.length == 1 ? 'alert' : 'alerts')
            : 'from $name',
        claim: out == group.length
            ? 'Read as money out. The amounts and merchants look clean.'
            : out == 0
            ? 'Read as money in. The amounts and senders look clean.'
            : 'Read cleanly. $out out, ${group.length - out} in.',
        evidence: _sampleTitles(group),
        alternative: 'Check them one by one',
        actions: [
          ReviewAction(
            label: group.length == 1
                ? 'Confirm it'
                : 'Confirm all ${group.length}',
            decision: ReviewDecision(
              kind: ReviewDecisionKind.confirm,
              transactionIds: [for (final item in group) item.id],
            ),
          ),
        ],
      ),
    );
  }

  // 6. One question per app, covering every alert of its that never reached
  //    the ledger -- whichever way it failed.
  //
  //    This used to be two rules. One asked about alerts that read as money
  //    but named no account; the other about alerts that did not parse at
  //    all. The first set is contained in the second, so a single alert
  //    appeared twice, under two different claims, offering two different
  //    answers -- and the "no account" version offered no way to say "this is
  //    not a transaction", which left promotional SMS with nothing to do but
  //    be filed into an account.
  for (final review in reviews) {
    if (review.reason != ReviewReason.parseFailed) continue;
    final package = review.id.startsWith('unparsed:')
        ? review.id.substring('unparsed:'.length)
        : '';
    final app = _appName(review.title);
    final count = _leadingCount(review.title) ?? 1;
    final one = count == 1;
    final them = one ? 'it' : 'them';
    // A real body beats a description of why there is no body.
    final stuck = unroutedByPackage[package] ?? const [];
    rules.add(
      ReviewRule(
        id: review.id,
        count: count,
        unit: app == null
            ? (one ? 'alert' : 'alerts')
            : (one ? 'alert from $app' : 'alerts from $app'),
        claim: app == null
            ? 'Nothing here reached your ledger.'
            : one
            ? 'One alert from $app never reached your ledger.'
            : '$count alerts from $app never reached your ledger.',
        evidence: stuck.isNotEmpty
            ? _trim(stuck.first.body)
            : _reasonOnly(review.description),
        alternative: 'Read $them first',
        alertPackage: package.isEmpty ? null : package,
        readableAlerts: count,
        // Three answers, always the same three, in the order a person would
        // try them. Attaching an account is first because it is the fix that
        // also teaches SpendWise where the app's future alerts belong.
        actions: [
          ReviewAction(
            label: one
                ? 'Attach it to an account'
                : 'Attach all $count to an account',
            needsAccount: true,
            decision: ReviewDecision(
              kind: ReviewDecisionKind.routeAlerts,
              alertIds: [for (final alert in stuck) alert.id],
              packageName: package,
            ),
          ),
          ReviewAction(
            // Verb first, and the two follow-ups are the same shape so they
            // can share a row without one looking like the important one.
            label: one ? 'File it' : 'File all $count',
            // Filing writes an entry, and an entry that belongs to no account
            // reaches no balance -- the ledger will not store one. So when any
            // of these alerts never found an account, the direction alone is
            // half an answer: the ledger skipped every one of them and the
            // screen still said they were settled. Asked only when it is
            // genuinely missing, because the alerts of an app that already has
            // an account need no second question.
            needsAccount: stuck.isNotEmpty,
            needsDirection: true,
            decision: ReviewDecision(
              kind: ReviewDecisionKind.fileAlerts,
              packageName: package,
            ),
          ),
          ReviewAction(
            label: one ? 'Drop it' : 'Drop all $count',
            destructive: true,
            decision: ReviewDecision(
              kind: ReviewDecisionKind.dismissSource,
              packageName: package,
            ),
          ),
        ],
      ),
    );
  }

  // The first three rules change what the numbers say, so they keep their
  // order. Everything after is housekeeping, and there the biggest pile should
  // be the first thing offered -- a one-alert question above a ten-alert one
  // reads as busywork.
  bool isUrgent(ReviewRule rule) =>
      const {'redirect', 'route', 'transfer'}.contains(rule.id);
  final head = rules.where(isUrgent).toList();
  final tail = rules.where((rule) => !isUrgent(rule)).toList()
    ..sort((a, b) => b.count.compareTo(a.count));
  return [...head, ...tail];
}

/// The controller appends its own advice to the parser reason. The rule's
/// action button already says what to do, so the quote keeps only the reason.
String _reasonOnly(String description) => description
    .replaceAll(
      RegExp(
        r'\s*If .{1,40}? does not send payment alerts, dismiss them\.\s*$',
        caseSensitive: false,
      ),
      '',
    )
    .trim();

/// Pulls the app name out of the controller's "N unread alerts from X" title.
String? _appName(String title) {
  final match = RegExp(r'\bfrom\s+(.+)$').firstMatch(title.trim());
  final name = match?.group(1)?.trim();
  return name == null || name.isEmpty ? null : name;
}

String _fromSource(List<TransactionViewData> items) {
  final names = items
      .map((item) => item.accountName.trim())
      .where((name) => name.isNotEmpty)
      .toSet();
  final plural = items.length == 1 ? 'alert' : 'alerts';
  if (names.length == 1) return '$plural from ${names.first}';
  return plural;
}

String? _sampleBody(List<TransactionViewData> items) {
  for (final item in items) {
    for (final evidence in item.evidence) {
      if (evidence.body.trim().isNotEmpty) return _trim(evidence.body);
    }
  }
  return _sampleTitles(items);
}

String? _sampleTitles(List<TransactionViewData> items) {
  final titles = items
      .map((item) => item.title.trim())
      .where((title) => title.isNotEmpty)
      .toSet()
      .take(3)
      .toList();
  if (titles.isEmpty) return null;
  final more = items.length - titles.length;
  return more > 0 ? '${titles.join(' · ')} · +$more more' : titles.join(' · ');
}

String _trim(String body) {
  final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= 132 ? flat : '${flat.substring(0, 129)}…';
}

int? _leadingCount(String title) =>
    int.tryParse(RegExp(r'^\d+').firstMatch(title)?.group(0) ?? '');
