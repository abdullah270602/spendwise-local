import '../shell/spendwise_view_model.dart';

/// A Review rule: one question that resolves many alerts at once.
///
/// The old inbox listed every uncertain transaction and asked the user to
/// confirm each. That is the opposite of saving anyone time -- if ten alerts
/// are uncertain for the same reason, there is one question, not ten. A rule
/// names the reason, quotes the evidence, and carries the decision that
/// answers it for the whole group.
class ReviewRule {
  const ReviewRule({
    required this.id,
    required this.count,
    required this.unit,
    required this.claim,
    required this.decision,
    required this.actionLabel,
    this.evidence,
    this.highlights = const [],
    this.alternative,
    this.needsAccount = false,
    this.needsCategory = false,
    this.alertPackage,
    this.readableAlerts = 0,
  });

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

  final ReviewDecision decision;
  final String actionLabel;

  /// The action cannot run until the user picks a target.
  final bool needsAccount;
  final bool needsCategory;

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

  // 0. A shared source delivered money it could not place. These never became
  //    transactions, so they are invisible to every rule below -- and they are
  //    the single most common way a real payment goes missing.
  final byApp = <String, List<AlertViewData>>{};
  for (final alert in unroutedAlerts) {
    byApp.putIfAbsent(alert.sourceLabel, () => []).add(alert);
  }
  final appNames = byApp.keys.toList()
    ..sort((a, b) => byApp[b]!.length.compareTo(byApp[a]!.length));
  for (final app in appNames) {
    final group = byApp[app]!;
    rules.add(
      ReviewRule(
        id: 'route-alerts:$app',
        count: group.length,
        unit: group.length == 1 ? 'alert from $app' : 'alerts from $app',
        claim:
            '$app carries more than one bank, and these did not name one '
            'SpendWise recognises.',
        evidence: _trim(group.first.body),
        actionLabel: group.length == 1
            ? 'File it under one account'
            : 'File all ${group.length} under one account',
        alternative: 'Read ${group.length == 1 ? 'it' : 'them'} first',
        needsAccount: true,
        alertPackage: group.first.packageName,
        readableAlerts: group.length,
        decision: ReviewDecision(
          kind: ReviewDecisionKind.routeAlerts,
          alertIds: [for (final alert in group) alert.id],
        ),
      ),
    );
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
        actionLabel: misread.length == 1
            ? 'Treat it as money out'
            : 'Treat all ${misread.length} as money out',
        alternative: 'They really were money in',
        decision: ReviewDecision(
          kind: ReviewDecisionKind.redirect,
          transactionIds: [for (final item in misread) item.id],
        ),
      ),
    );
  }

  // 2. No account matched. Nothing reaches a balance until this is answered,
  //    so it outranks categorisation.
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
            ? 'No account matched — you have not set one up yet.'
            : 'No account matched. Nothing here has reached a balance.',
        evidence: _sampleBody(unrouted),
        actionLabel: unrouted.length == 1
            ? 'Choose its account'
            : 'Send all ${unrouted.length} to one account',
        alternative: accounts.isEmpty ? null : 'Handle them one by one',
        needsAccount: true,
        decision: ReviewDecision(
          kind: ReviewDecisionKind.route,
          transactionIds: [for (final item in unrouted) item.id],
        ),
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
        claim: 'Money moved between accounts you own — not spending.',
        evidence: _sampleTitles(ownMoves),
        actionLabel: ownMoves.length == 1
            ? 'Yes, that was my own move'
            : 'Yes, all ${ownMoves.length} were my own moves',
        alternative: 'Some went to someone else',
        decision: ReviewDecision(
          kind: ReviewDecisionKind.confirm,
          transactionIds: [for (final item in ownMoves) item.id],
        ),
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
        actionLabel: uncategorised.length == 1
            ? 'File it'
            : 'File all ${uncategorised.length} together',
        alternative: 'They belong in different categories',
        needsCategory: true,
        decision: ReviewDecision(
          kind: ReviewDecisionKind.categorize,
          transactionIds: [for (final item in uncategorised) item.id],
        ),
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
            : 'Read cleanly — $out out, ${group.length - out} in.',
        evidence: _sampleTitles(group),
        actionLabel: group.length == 1
            ? 'Confirm it'
            : 'Confirm all ${group.length}',
        alternative: 'Check them one by one',
        decision: ReviewDecision(
          kind: ReviewDecisionKind.confirm,
          transactionIds: [for (final item in group) item.id],
        ),
      ),
    );
  }

  // 6. Raw alerts that never became transactions, already grouped per app by
  //    the controller.
  for (final review in reviews) {
    if (review.reason != ReviewReason.parseFailed) continue;
    final package = review.id.startsWith('unparsed:')
        ? review.id.substring('unparsed:'.length)
        : '';
    final app = _appName(review.title);
    final count = _leadingCount(review.title) ?? 1;
    rules.add(
      ReviewRule(
        id: review.id,
        count: count,
        unit: app == null
            ? (count == 1
                  ? 'alert SpendWise cannot read'
                  : 'alerts SpendWise cannot read')
            : 'unread from $app',
        claim: app == null
            ? 'Nothing here parsed as a transaction.'
            : 'Nothing from $app parsed as a transaction.',
        evidence: _reasonOnly(review.description),
        actionLabel: count == 1
            ? 'Not a transaction — drop it'
            : 'Not transactions — drop all $count',
        alternative: 'Read ${count == 1 ? 'it' : 'them'} first',
        alertPackage: package.isEmpty ? null : package,
        readableAlerts: count,
        decision: ReviewDecision(
          kind: ReviewDecisionKind.dismissSource,
          packageName: package,
        ),
      ),
    );
  }

  // The first three rules change what the numbers say, so they keep their
  // order. Everything after is housekeeping, and there the biggest pile should
  // be the first thing offered -- a one-alert question above a ten-alert one
  // reads as busywork.
  bool isUrgent(ReviewRule rule) =>
      rule.id.startsWith('route-alerts:') ||
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
