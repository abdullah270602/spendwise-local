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
    // Legs are paired first and filed second: pairing is what teaches the
    // single-leg rules which bank code belongs to which account.
    final unpaired = <_Unpaired>[];
    final pairedAccounts = <_PairedText>[];
    for (final leg in legs) {
      if (consumed.contains(leg)) continue;
      final opposites = transferOptions[leg]!;
      if (opposites.length == 1) {
        final other = opposites.single;
        if (!consumed.contains(other) && transferOptions[other]!.length == 1) {
          transactions.add(_transfer(leg, other));
          // Each leg's text described the *other* account, so that is where
          // its bank codes are recorded.
          pairedAccounts
            ..add(_PairedText(other.primary.accountId, _text(leg)))
            ..add(_PairedText(leg.primary.accountId, _text(other)));
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
      unpaired.add(_Unpaired(leg, ambiguous));
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

    // Every leg that found its partner has now told us something the next
    // one cannot work out alone: which bank a stretch of IBAN belongs to.
    // "S.OWNER PK11SBNKxx002" paired with an alert from the owner's other
    // bank says PK11SBNK is that account -- so when the same owner's name
    // turns up beside the same bank code weeks later and that bank sends
    // nothing at all, the money has a named origin instead of appearing out
    // of nowhere as income.
    final bankCodes = <String, String>{};
    for (final entry in pairedAccounts) {
      for (final code in _bankCodes(entry.text)) {
        bankCodes.update(
          code,
          (existing) => existing == entry.accountId ? existing : '',
          ifAbsent: () => entry.accountId,
        );
      }
    }
    bankCodes.removeWhere((_, accountId) => accountId.isEmpty);

    // A leg whose partner arrived *after* the owner had already answered.
    //
    // Banks do not settle together: one side alerts immediately, the other
    // an hour later or not at all. Somebody who fixes the first alert by
    // hand -- "this was a move to my other account" -- has answered the
    // question, and their answer is locked. When the second leg finally
    // turns up there is no longer a candidate for it to pair with, so it
    // used to stand alone and post as income. The transfer was counted and
    // then the same money was counted again as money earned: five thousand
    // moved, ten thousand in the ledger.
    //
    // So a late leg that corroborates an answered transfer is filed as more
    // evidence for it, not as a second event.
    final settled = existing
        .where(
          (item) =>
              item.kind == TransactionKind.transfer &&
              (item.locked || item.origin == TransactionOrigin.manual),
        )
        .toList();
    final lateEvidence = <String, Set<String>>{};
    // Which account and direction each piece of evidence speaks for, so a
    // transfer can tell whether a side is already accounted for.
    final sideOfEvidence = <String, String>{
      for (final leg in legs)
        for (final id in leg.evidenceIds)
          id: '${leg.primary.accountId}|${leg.primary.direction.name}',
    };

    for (final item in unpaired) {
      final corroborated = _corroborates(item.leg, settled, sideOfEvidence);
      if (corroborated != null) {
        lateEvidence
            .putIfAbsent(corroborated.id, () => <String>{})
            .addAll(item.leg.evidenceIds);
        decisions.add(
          _decision(
            ReconciliationDecisionType.pairTransfer,
            [item.leg],
            1,
            [
              'Late leg of a transfer the owner had already confirmed; '
                  'attached as evidence rather than posted again.',
            ],
          ),
        );
        continue;
      }
      transactions.add(
        _single(item.leg, needsReview: item.ambiguous, bankCodes: bankCodes),
      );
    }

    // User-created and locked records are immutable. Evidence may only attach
    // to an editable automatic transaction with the same stable identity.
    for (final old in existing) {
      final index = transactions.indexWhere((fresh) => fresh.id == old.id);
      if (index < 0) {
        final late = lateEvidence[old.id];
        transactions.add(
          late == null
              ? old
              : old.copyWith(evidenceIds: {...old.evidenceIds, ...late}),
        );
      } else if (old.locked || old.origin == TransactionOrigin.manual) {
        // The owner's answer stands; only the evidence behind it grows.
        transactions[index] = old.copyWith(
          evidenceIds: {...old.evidenceIds, ...?lateEvidence[old.id]},
        );
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
    // Two references that disagree are two different payments, and that is
    // the whole of what a reference can settle. A reference on one side and
    // none on the other says nothing at all -- yet this used to read it as a
    // mismatch and stop, which quietly made one whole class of duplicate
    // impossible to detect: a bank's SMS always carries a TID and the wallet
    // app reporting the same card tap never does, so every such pair was
    // declared distinct before any other signal was looked at, and the
    // payment landed in the ledger twice.
    if (first.reference != null && candidate.reference != null) {
      return first.reference == candidate.reference;
    }
    if (first.observation.evidenceFingerprint ==
        candidate.observation.evidenceFingerprint) {
      return true;
    }
    final distinctChannels =
        first.observation.sourcePackage !=
            candidate.observation.sourcePackage ||
        first.observation.kind != candidate.observation.kind;
    return distinctChannels &&
        _namesTheSameParty(first, candidate) &&
        _difference(first.occurredAt, candidate.occurredAt) <=
            const Duration(seconds: 90);
  }

  /// Whether two legs are talking about the same shop or person.
  ///
  /// Compared across both fields rather than field-for-field, because two
  /// apps rarely put a name in the same place: a bank's SMS names the
  /// merchant as the counterparty, the wallet app reporting the same card tap
  /// puts it in the notification's title and has no counterparty at all.
  ///
  /// One name containing the other counts, because the same shop arrives
  /// spelled differently and usually truncated -- "CORNER BAKERY L" on the
  /// SMS against "CORNER & BAKERY" from the wallet, which is the pair that
  /// put one
  /// payment into the ledger twice. Containment is allowed only from six
  /// characters up, so a three-letter fragment cannot marry two unrelated
  /// merchants, and only under everything demanded above: the same account,
  /// the same direction, the same amount, two different apps, ninety
  /// seconds.
  bool _namesTheSameParty(EventCandidate a, EventCandidate b) {
    final left = {_normalized(a.counterparty), _normalized(a.description)}
      ..removeWhere((value) => value.isEmpty);
    final right = {_normalized(b.counterparty), _normalized(b.description)}
      ..removeWhere((value) => value.isEmpty);
    for (final one in left) {
      for (final other in right) {
        if (one == other) return true;
        final shorter = one.length <= other.length ? one : other;
        final longer = identical(shorter, one) ? other : one;
        if (shorter.length >= 6 && longer.contains(shorter)) return true;
      }
    }
    return false;
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

  /// The answered transfer this lone leg is the other half of, if any.
  ///
  /// The strictest rule in this file, because getting it wrong *hides* money
  /// rather than duplicating it, and nothing on screen would ever say so. An
  /// early, looser version of it swallowed a stranger's payment of the same
  /// amount and a second payment out of the same account. Five conditions,
  /// and every one of them earned:
  ///
  /// 1. The amount matches exactly.
  /// 2. The leg is not already part of this transfer. The leg the owner
  ///    corrected is still a candidate on every later run; it regenerates
  ///    its own id and is preserved by the merge below, and absorbing it
  ///    here would delete the entry into itself.
  /// 3. It points the right way for one side of the transfer.
  /// 4. That side is not already accounted for. Without this, a *second*
  ///    payment out of the same account looks exactly like the first.
  /// 5. The far side names the owner. This is what separates the other half
  ///    of your own transfer from somebody else paying you the same amount
  ///    in the same hour.
  CanonicalTransaction? _corroborates(
    _Leg leg,
    List<CanonicalTransaction> settled,
    Map<String, String> sideOfEvidence,
  ) {
    final item = leg.primary;
    if (!ownIdentity.matchesOwnName(item.counterparty)) return null;
    final side = '${item.accountId}|${item.direction.name}';
    final window = ownAccountTransferWindow > transferWindow
        ? ownAccountTransferWindow
        : transferWindow;

    final matches = settled.where((transfer) {
      if (transfer.amount != item.amount) return false;
      if (_difference(transfer.occurredAt, item.occurredAt) > window) {
        return false;
      }
      if (transfer.evidenceIds.intersection(leg.evidenceIds).isNotEmpty) {
        return false;
      }
      final belongs = item.direction == EntryDirection.debit
          ? transfer.fromAccountId == item.accountId
          : transfer.toAccountId == item.accountId;
      if (!belongs) return false;
      final covered = transfer.evidenceIds
          .map((id) => sideOfEvidence[id])
          .whereType<String>()
          .toSet();
      return !covered.contains(side);
    }).toList();

    // Two answered transfers of the same amount between the same accounts
    // inside the window: nothing here can say which one this belongs to,
    // and guessing would hide a real second movement.
    return matches.length == 1 ? matches.single : null;
  }

  /// The text of every alert behind a leg, so a rule may read what the bank
  /// actually wrote and not only the fields the parser lifted out of it.
  String _text(_Leg leg) => leg.candidates
      .map(
        (item) => [
          item.observation.title ?? '',
          item.observation.body,
          item.counterparty ?? '',
        ].join(' '),
      )
      .join(' ');

  /// The one other account of the owner's that this leg's own text names
  /// outright, or null when it names none or names more than one.
  ///
  /// More than one is the case that matters: three wallets opened against the
  /// same phone number carry the same four-digit tail, so a message quoting
  /// it names all three and therefore none of them.
  String? _namedOppositeAccount(_Leg leg) {
    final named = ownIdentity
        .accountsNamedWithNumber(_text(leg))
        .where((id) => id != leg.primary.accountId)
        .toSet();
    return named.length == 1 ? named.single : null;
  }

  /// The bank-identifying head of every IBAN in a piece of text.
  ///
  /// An IBAN opens with a country code, two check digits and the bank's own
  /// identifier -- "PK11SBNK..." -- and banks print that head even when they
  /// mask everything after it. The head alone says which bank, never which
  /// customer, which is exactly why it is only ever used alongside a name.
  static final RegExp _ibanHead = RegExp(
    r'(?<![A-Za-z0-9])([A-Z]{2}[0-9]{2}[A-Z]{4})[0-9A-Zx*\u2022]*',
    caseSensitive: false,
  );

  Iterable<String> _bankCodes(String text) =>
      _ibanHead.allMatches(text).map((match) => match.group(1)!.toUpperCase());

  CanonicalTransaction _single(
    _Leg leg, {
    required bool needsReview,
    Map<String, String> bankCodes = const {},
  }) {
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
    // One alert can name both ends by itself. A wallet top-up says which
    // account funded it -- "Rs. 10,000 loaded through Northbank-9001 linked
    // account" -- and the funding bank sends nothing at all, so the opposing
    // leg the pairing pass is waiting for will never arrive. Booking it as
    // income was not merely a missing transfer: it counted money the owner
    // already had as money they had just earned.
    // Second way one alert names both ends: the owner's own name beside a
    // bank code already proven to be one of their accounts. Both halves are
    // required and neither is optional -- a bank code on its own belongs to
    // every customer of that bank, so "R.STRANGER PK11SBNKxx070" is a payment
    // to a stranger who banks where the owner also banks, and reading it as
    // a transfer would hide real money leaving.
    final viaBankCode = ownIdentity.matchesOwnName(item.counterparty)
        ? _bankCodes(_text(leg))
              .map((code) => bankCodes[code])
              .whereType<String>()
              .where((id) => id != item.accountId)
              .toSet()
        : const <String>{};

    final opposite =
        _namedOppositeAccount(leg) ??
        (viaBankCode.length == 1 ? viaBankCode.single : null);
    if (opposite != null) {
      final incoming = item.direction == EntryDirection.credit;
      return CanonicalTransaction(
        id: _stableId('self', [
          item.accountId,
          opposite,
          item.direction.name,
          '${item.amount.minorUnits}',
          _identity(leg),
        ]),
        kind: TransactionKind.transfer,
        amount: item.amount,
        occurredAt: _earliest(leg.candidates),
        evidenceIds: leg.evidenceIds,
        fromAccountId: incoming ? opposite : item.accountId,
        toAccountId: incoming ? item.accountId : opposite,
        description: item.description,
        needsReview: needsReview || item.confidence < 0.8,
        reconciliationState: needsReview || item.confidence < 0.8
            ? ReconciliationState.needsReview
            : ReconciliationState.probable,
      );
    }

    // Money arriving from the account holder themselves, with no opposing leg
    // to pair it against. It is almost certainly their own money moving --
    // the far side simply did not send an alert, which is routine -- but
    // nothing here says which account it left, so there is no transfer to
    // assert. What must not happen is the old behaviour: filing it as income
    // at full confidence, which inflated a month by the whole amount and gave
    // the owner nothing to notice. Asking is cheap; the question is precise.
    final fromSelf =
        item.direction == EntryDirection.credit &&
        ownIdentity.matchesOwnName(item.counterparty);

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
      needsReview: needsReview || fromSelf || item.confidence < 0.8,
      reconciliationState: needsReview || fromSelf || item.confidence < 0.8
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

/// A leg that found no partner, held back until pairing has finished.
final class _Unpaired {
  const _Unpaired(this.leg, this.ambiguous);
  final _Leg leg;
  final bool ambiguous;
}

/// The text of one half of a confirmed transfer, against the account that
/// half was describing.
final class _PairedText {
  const _PairedText(this.accountId, this.text);
  final String accountId;
  final String text;
}

final class _Leg {
  _Leg(this.candidates);
  final List<EventCandidate> candidates;
  EventCandidate get primary => candidates.first;
  Set<String> get evidenceIds =>
      candidates.map((item) => item.observation.id).toSet();
}
