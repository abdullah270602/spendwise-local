import '../models/canonical_transaction.dart';
import '../models/event_candidate.dart';
import '../models/own_identity.dart';
import '../models/raw_observation.dart';

final class ReconciliationResult {
  const ReconciliationResult({
    required this.transactions,
    this.decisions = const [],
  });
  final List<CanonicalTransaction> transactions;
  final List<ReconciliationDecision> decisions;
  int get reviewCount => transactions.where((item) => item.needsReview).length;
}

/// Deterministically reduces interpreted evidence into ledger transactions.
/// Input ordering has no effect on the output.
final class Reconciler {
  const Reconciler({
    this.duplicateWindow = const Duration(minutes: 3),
    this.transferWindow = const Duration(minutes: 10),
    this.ownIdentity = const OwnIdentity(),
    this.cashAccountId,
    this.cashRoutingFrom,
    this.ownAccountTransferWindow = const Duration(hours: 48),
  });

  final Duration duplicateWindow;
  final Duration transferWindow;

  /// The user's own name(s) and per-account number suffixes.
  ///
  /// A counterparty naming another tracked account (by its registered number
  /// suffix) identifies the destination, so that pair may settle across the
  /// much wider [ownAccountTransferWindow] — interbank settlement can take
  /// far longer than the default [transferWindow]. A counterparty that only
  /// matches the account holder's name is weaker: it marks the leg as
  /// self-directed without saying where the money landed, so it raises
  /// confidence within the normal window only.
  final OwnIdentity ownIdentity;

  /// Where withdrawn cash lands, when the ledger keeps a cash account.
  ///
  /// Null means the owner has no cash account, and a withdrawal stays what it
  /// has always been: an expense. Nothing here creates one -- the reconciler
  /// reads a ledger, it does not shape it.
  final String? cashAccountId;

  /// The moment cash started being tracked, and the reason this is not simply
  /// "route every withdrawal".
  ///
  /// Reconciliation rebuilds automatic transactions from stored evidence, so
  /// without a cutoff the first run after this feature arrived would reach
  /// back through every withdrawal the owner had ever made and declare the
  /// lot of it cash still in their pocket. Months of money already spent
  /// would reappear as money available to spend. A withdrawal older than this
  /// keeps the meaning it had when it was filed.
  final DateTime? cashRoutingFrom;

  bool _routesToCash(EventCandidate item) {
    final cash = cashAccountId;
    final from = cashRoutingFrom;
    if (cash == null || from == null) return false;
    if (item.type != CandidateType.cashWithdrawal) return false;
    // Cash withdrawn from the cash account itself is not a movement.
    if (item.accountId == cash) return false;
    return !item.occurredAt.isBefore(from);
  }

  final Duration ownAccountTransferWindow;

  ReconciliationResult reconcile(
    Iterable<EventCandidate> candidates, {
    Iterable<CanonicalTransaction> existing = const [],
  }) {
    final sorted = candidates.toList()
      ..sort((a, b) => _candidateKey(a).compareTo(_candidateKey(b)));
    // Both passes below compare every leg against every other, which turns
    // quadratic on a real ledger and stalls the isolate. Duplicates require
    // an identical account, direction, and amount, and transfers require an
    // identical amount, so bucketing on those first skips the comparisons
    // that could only ever score zero. Same output, far fewer comparisons.
    final legs = <_Leg>[];
    final duplicateBuckets = <String, List<_Leg>>{};
    for (final candidate in sorted) {
      final bucket = duplicateBuckets.putIfAbsent(
        _duplicateBucketKey(candidate),
        () => <_Leg>[],
      );
      final duplicate = bucket
          .where((leg) => _isDuplicate(leg, candidate))
          .toList();
      if (duplicate.length == 1) {
        duplicate.single.candidates.add(candidate);
      } else {
        final leg = _Leg([candidate]);
        legs.add(leg);
        bucket.add(leg);
      }
    }

    final amountBuckets = <String, List<_Leg>>{};
    for (final leg in legs) {
      amountBuckets
          .putIfAbsent(_amountBucketKey(leg.primary), () => <_Leg>[])
          .add(leg);
    }
    final transferOptions = <_Leg, List<_Leg>>{
      for (final leg in legs)
        leg: (amountBuckets[_amountBucketKey(leg.primary)] ?? const <_Leg>[])
            .where(
              (other) =>
                  other != leg && _isTransferPair(leg.primary, other.primary),
            )
            .toList(),
    };

    final transactions = <CanonicalTransaction>[];
    final decisions = <ReconciliationDecision>[];
    final consumed = <_Leg>{};
    for (final leg in legs) {
      if (consumed.contains(leg)) continue;
      final opposites = transferOptions[leg]!;
      if (opposites.length == 1) {
        final other = opposites.single;
        if (!consumed.contains(other) && transferOptions[other]!.length == 1) {
          transactions.add(_transfer(leg, other));
          decisions.add(
            _decision(
              ReconciliationDecisionType.pairTransfer,
              [leg, other],
              _transferScore(leg.primary, other.primary),
              [
                'Opposing account legs matched by amount, time, reference, and counterparty signals.',
              ],
            ),
          );
          consumed.addAll([leg, other]);
          continue;
        }
      }
      final ambiguous = opposites.isNotEmpty;
      transactions.add(_single(leg, needsReview: ambiguous));
      if (leg.candidates.length > 1) {
        decisions.add(
          _decision(
            ReconciliationDecisionType.mergeEvidence,
            [leg],
            1,
            ['Evidence shares a strong duplicate identity.'],
          ),
        );
      }
      if (ambiguous) {
        decisions.add(
          _decision(
            ReconciliationDecisionType.keepSeparate,
            [leg, ...opposites],
            0.5,
            ['Multiple plausible matches; preserved separately for review.'],
          ),
        );
      }
      consumed.add(leg);
    }

    // User-created and locked records are immutable. Evidence may only attach
    // to an editable automatic transaction with the same stable identity.
    for (final old in existing) {
      final index = transactions.indexWhere((fresh) => fresh.id == old.id);
      if (index < 0) {
        transactions.add(old);
      } else if (old.locked || old.origin == TransactionOrigin.manual) {
        transactions[index] = old;
      } else {
        transactions[index] = transactions[index].copyWith(
          evidenceIds: {...old.evidenceIds, ...transactions[index].evidenceIds},
        );
      }
    }
    transactions.sort((a, b) {
      final time = b.occurredAt.compareTo(a.occurredAt);
      return time != 0 ? time : a.id.compareTo(b.id);
    });
    return ReconciliationResult(
      transactions: List.unmodifiable(transactions),
      decisions: List.unmodifiable(decisions),
    );
  }

  bool _isDuplicate(_Leg leg, EventCandidate candidate) {
    final first = leg.primary;
    if (first.accountId != candidate.accountId ||
        first.direction != candidate.direction ||
        first.amount != candidate.amount ||
        _difference(first.occurredAt, candidate.occurredAt) >
            _duplicateWindow(first, candidate)) {
      return false;
    }
    if (first.reference != null || candidate.reference != null) {
      return first.reference != null && first.reference == candidate.reference;
    }
    if (first.observation.evidenceFingerprint ==
        candidate.observation.evidenceFingerprint) {
      return true;
    }
    final distinctChannels =
        first.observation.sourcePackage !=
            candidate.observation.sourcePackage ||
        first.observation.kind != candidate.observation.kind;
    final sameCounterparty =
        _normalized(first.counterparty).isNotEmpty &&
        _normalized(first.counterparty) == _normalized(candidate.counterparty);
    final sameDescription =
        _normalized(first.description).isNotEmpty &&
        _normalized(first.description) == _normalized(candidate.description);
    return distinctChannels &&
        (sameCounterparty || sameDescription) &&
        _difference(first.occurredAt, candidate.occurredAt) <=
            const Duration(seconds: 90);
  }

  Duration _duplicateWindow(EventCandidate a, EventCandidate b) =>
      (a.observation.kind == ObservationKind.csvImport ||
              b.observation.kind == ObservationKind.csvImport) &&
          a.reference != null &&
          a.reference == b.reference
      ? const Duration(hours: 36)
      : duplicateWindow;

  bool _isTransferPair(EventCandidate a, EventCandidate b) =>
      _transferScore(a, b) >= 0.7;

  double _transferScore(EventCandidate a, EventCandidate b) {
    if (a.accountId == b.accountId ||
        a.direction == b.direction ||
        a.amount != b.amount) {
      return 0;
    }
    final namesOppositeAccount = _namesOppositeAccount(a, b);
    final ownNameLegs = _ownNameLegs(a, b);
    final age = _difference(a.occurredAt, b.occurredAt);
    final lateCsv =
        a.observation.kind == ObservationKind.csvImport ||
        b.observation.kind == ObservationKind.csvImport;
    // Only naming the opposite account earns the wider settlement window.
    // An own-name match says "this leg was mine" but not where it landed, so
    // widening on it would merge any two same-amount legs a day apart.
    final window = namesOppositeAccount
        ? (ownAccountTransferWindow > transferWindow
              ? ownAccountTransferWindow
              : transferWindow)
        : (lateCsv ? const Duration(hours: 36) : transferWindow);
    if (age > window) {
      return 0;
    }
    var score = age <= const Duration(minutes: 3)
        ? 0.7
        : (lateCsv ? 0.55 : 0.6);
    if (a.reference != null && a.reference == b.reference) score += 0.3;
    final ac = _normalized(a.counterparty), bc = _normalized(b.counterparty);
    if (ac.isNotEmpty &&
        bc.isNotEmpty &&
        (ac.contains(bc) || bc.contains(ac))) {
      score += 0.15;
    }
    if (namesOppositeAccount) {
      score += 0.35;
    } else if (ownNameLegs > 0) {
      score += ownNameLegs == 2 ? 0.3 : 0.2;
    }
    return score.clamp(0, 1);
  }

  /// Strong signal: one leg's counterparty carries the *other* account's
  /// registered number suffix, which names the destination outright.
  bool _namesOppositeAccount(EventCandidate a, EventCandidate b) =>
      ownIdentity.matchesAccount(a.counterparty, b.accountId) ||
      ownIdentity.matchesAccount(b.counterparty, a.accountId);

  /// Weak signal: how many legs name the account holder themselves. Enough to
  /// lift a genuine self-transfer over the threshold inside the normal
  /// window, never enough to widen that window.
  int _ownNameLegs(EventCandidate a, EventCandidate b) =>
      (ownIdentity.matchesOwnName(a.counterparty) ? 1 : 0) +
      (ownIdentity.matchesOwnName(b.counterparty) ? 1 : 0);

  CanonicalTransaction _single(_Leg leg, {required bool needsReview}) {
    final item = leg.primary;
    // Money withdrawn as cash did not leave the owner, it changed pocket. It
    // is the one transfer the app asserts from a single alert rather than by
    // pairing two: a wallet full of notes never sends a notification, so the
    // opposing leg cannot exist and waiting for it would mean waiting
    // forever.
    if (_routesToCash(item)) {
      return CanonicalTransaction(
        id: _stableId('cash', [
          item.accountId,
          '${item.amount.minorUnits}',
          _identity(leg),
        ]),
        kind: TransactionKind.transfer,
        amount: item.amount,
        occurredAt: _earliest(leg.candidates),
        evidenceIds: leg.evidenceIds,
        fromAccountId: item.accountId,
        toAccountId: cashAccountId,
        description: item.description,
        needsReview: needsReview || item.confidence < 0.8,
        reconciliationState: needsReview || item.confidence < 0.8
            ? ReconciliationState.needsReview
            : ReconciliationState.probable,
      );
    }
    return CanonicalTransaction(
      id: _stableId('single', [
        item.accountId,
        item.direction.name,
        '${item.amount.minorUnits}',
        _identity(leg),
      ]),
      kind: item.direction == EntryDirection.debit
          ? TransactionKind.expense
          : TransactionKind.income,
      amount: item.amount,
      occurredAt: _earliest(leg.candidates),
      evidenceIds: leg.evidenceIds,
      accountId: item.accountId,
      description: item.description,
      needsReview: needsReview || item.confidence < 0.8,
      reconciliationState: needsReview || item.confidence < 0.8
          ? ReconciliationState.needsReview
          : (leg.candidates.length > 1
                ? ReconciliationState.confirmed
                : ReconciliationState.probable),
    );
  }

  CanonicalTransaction _transfer(_Leg first, _Leg second) {
    final debit = first.primary.direction == EntryDirection.debit
        ? first
        : second;
    final credit = identical(debit, first) ? second : first;
    return CanonicalTransaction(
      id: _stableId('transfer', [
        debit.primary.accountId,
        credit.primary.accountId,
        '${debit.primary.amount.minorUnits}',
        _identity(debit),
        _identity(credit),
      ]),
      kind: TransactionKind.transfer,
      amount: debit.primary.amount,
      occurredAt: _earliest([...debit.candidates, ...credit.candidates]),
      evidenceIds: {...debit.evidenceIds, ...credit.evidenceIds},
      fromAccountId: debit.primary.accountId,
      toAccountId: credit.primary.accountId,
      // Deliberately unnamed: the only names available here are opaque
      // account ids, and rendering "2cfe72de-... → 9f31a0c4-..." as the
      // transaction's name is worse than letting the UI label it and show
      // the resolved account names alongside.
      description: null,
      needsReview:
          debit.primary.confidence < 0.8 || credit.primary.confidence < 0.8,
      reconciliationState:
          debit.primary.confidence >= 0.8 && credit.primary.confidence >= 0.8
          ? ReconciliationState.confirmed
          : ReconciliationState.probable,
    );
  }

  String _identity(_Leg leg) {
    final identities =
        leg.candidates
            .map(
              (item) =>
                  item.reference ??
                  item.observation.externalId ??
                  item.observation.id,
            )
            .toList()
          ..sort();
    return identities.join(',');
  }

  /// Cheapest necessary conditions for [_isDuplicate], used to bucket legs so
  /// only plausible pairs are compared.
  String _duplicateBucketKey(EventCandidate item) =>
      '${item.accountId}|${item.direction.name}|${_amountBucketKey(item)}';

  /// Cheapest necessary condition for [_transferScore] — an unequal amount
  /// always scores zero.
  String _amountBucketKey(EventCandidate item) =>
      '${item.amount.minorUnits}|${item.amount.currency}';

  String _candidateKey(EventCandidate item) => [
    item.occurredAt.toUtc().microsecondsSinceEpoch.toString().padLeft(20, '0'),
    item.accountId,
    item.direction.name,
    item.amount.minorUnits,
    item.observation.id,
  ].join('|');

  Duration _difference(DateTime a, DateTime b) =>
      Duration(microseconds: (a.difference(b).inMicroseconds).abs());

  DateTime _earliest(Iterable<EventCandidate> values) => values
      .map((item) => item.occurredAt)
      .reduce((a, b) => a.isBefore(b) ? a : b);

  String _normalized(String? value) =>
      (value ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  String _stableId(String prefix, List<Object> values) {
    var hash = 0xcbf29ce484222325;
    for (final unit in values.join('|').codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return '$prefix:${hash.toRadixString(16).padLeft(16, '0')}';
  }

  ReconciliationDecision _decision(
    ReconciliationDecisionType type,
    List<_Leg> legs,
    double score,
    List<String> reasons,
  ) {
    final ids = legs
        .expand((leg) => leg.candidates.map((item) => item.id))
        .toSet();
    return ReconciliationDecision(
      id: _stableId('decision', [type.name, ...(ids.toList()..sort())]),
      type: type,
      candidateIds: ids,
      score: score,
      reasons: reasons,
    );
  }
}

final class _Leg {
  _Leg(this.candidates);
  final List<EventCandidate> candidates;
  EventCandidate get primary => candidates.first;
  Set<String> get evidenceIds =>
      candidates.map((item) => item.observation.id).toSet();
}
