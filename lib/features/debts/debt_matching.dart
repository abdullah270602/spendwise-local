/// Whether an entry already in the ledger looks like a payment against a loan
/// that is still open.
///
/// A bank alert for a repayment is indistinguishable from any other credit:
/// money arrived, from a name. Nothing in the alert says it closes anything.
/// So the app cannot settle a loan by itself -- but it can notice, and ask.
///
/// The line this file will not cross is settling anything automatically. A
/// wrong guess closes a loan that is still out, and a loan the owner believes
/// is settled is money they will never chase. Every match here is a question.
library;

import 'package:flutter/foundation.dart';

import '../shell/spendwise_view_model.dart';

/// How firmly an entry looks like a payment against a particular loan.
enum DebtMatchStrength {
  /// The amount is exactly what is still out, and the name matches too.
  exact,

  /// One of the two, not both.
  likely,
}

@immutable
class DebtMatch {
  const DebtMatch({
    required this.debt,
    required this.strength,
    required this.reason,
  });

  final DebtViewData debt;
  final DebtMatchStrength strength;

  /// Why this was suggested, in words the owner can check against the entry.
  /// A suggestion nobody can audit is just an assertion.
  final String reason;
}

/// Open loans this entry could be a payment against, strongest first.
///
/// Returns nothing rather than something weak: a list of maybes attached to
/// every credit that arrives would train the owner to dismiss the one that
/// mattered.
List<DebtMatch> debtMatchesFor({
  required TransactionViewData transaction,
  required Iterable<DebtViewData> debts,
  int limit = 3,
}) {
  // Already answered. Re-asking a question the owner has settled is how a
  // helpful prompt becomes noise.
  if (transaction.debtId != null) return const [];
  // A move between the owner's own accounts is not a repayment to anybody.
  if (transaction.kind == TransactionKind.transfer) return const [];

  final amount = transaction.amount.minorUnits.abs();
  if (amount == 0) return const [];
  final incoming = transaction.kind == TransactionKind.income;
  final words = _words(transaction.title);

  final matches = <DebtMatch>[];
  for (final debt in debts) {
    final outstanding = _roomFor(debt);
    if (outstanding <= 0) continue;
    // Money coming in settles what was lent out; money going out settles what
    // was borrowed, or passes on what was only ever being held.
    if (incoming != debt.lent) continue;
    if (debt.principal.currency != transaction.amount.currency) continue;
    // Nothing can repay a loan that did not exist yet. Compared as days
    // rather than instants: a loan opened at noon and repaid that morning is
    // an ordering the owner cannot see and would not accept as a reason.
    if (_startOfDay(debt.openedAt)
        .isAfter(_startOfDay(transaction.occurredAt))) {
      continue;
    }
    // More than is still out is not a repayment of this loan on its own --
    // it is a repayment plus something else, and the app cannot say how much
    // of it was which. The owner can still attach it by hand.
    if (amount > outstanding) continue;

    final named = _namesMatch(debt.counterparty, words);
    final whole = amount == outstanding;
    // A loan with nothing out is one somebody already settled by typing the
    // figure in. "Exactly what is still out" would be nonsense on it.
    final byHand = debt.outstanding.minorUnits <= 0;
    if (!named && !whole) continue;

    matches.add(
      DebtMatch(
        debt: debt,
        strength: named && whole
            ? DebtMatchStrength.exact
            : DebtMatchStrength.likely,
        reason: _reasonFor(named: named, whole: whole, byHand: byHand),
      ),
    );
  }

  matches.sort((a, b) {
    final byStrength = a.strength.index.compareTo(b.strength.index);
    if (byStrength != 0) return byStrength;
    // The most recent loan first: an older one of the same size is more
    // likely to be the one already half forgotten.
    final byDate = b.debt.openedAt.compareTo(a.debt.openedAt);
    if (byDate != 0) return byDate;
    return a.debt.counterparty.compareTo(b.debt.counterparty);
  });
  return matches.length > limit ? matches.sublist(0, limit) : matches;
}

String _reasonFor({
  required bool named,
  required bool whole,
  required bool byHand,
}) {
  final amount = byHand
      ? 'it is the amount already recorded by hand'
      : 'it is exactly what is still out';
  if (named && whole) return 'the name matches and $amount';
  return whole ? amount : 'the name matches';
}

/// How much of a loan an entry could still account for.
///
/// Normally what is still out. But a loan settled by typing an amount into
/// it is a loan whose money is recorded twice over: the loan says it came
/// home, and the entry that actually brought it home is still sitting in the
/// month as income. Nothing marks it settled *by an entry*, so the room to
/// correct that is exactly what was typed in by hand.
int _roomFor(DebtViewData debt) {
  final outstanding = debt.outstanding.minorUnits;
  if (outstanding > 0) return outstanding;
  return debt.settledByHand.minorUnits;
}

/// Open loans this entry could be attached to by hand, most recent first.
///
/// Wider than [debtMatchesFor] on purpose: the picker exists for the cases
/// the matcher was never going to catch -- a cousin whose name the bank
/// spells differently, a repayment of an odd amount, a loan repaid in two
/// halves. Only the direction is enforced, because that one is not a matter
/// of opinion: money arriving cannot be you repaying somebody.
List<DebtViewData> debtsOpenTo({
  required TransactionViewData transaction,
  required Iterable<DebtViewData> debts,
}) {
  if (transaction.kind == TransactionKind.transfer) return const [];
  final incoming = transaction.kind == TransactionKind.income;
  final open =
      debts
          .where((debt) => _roomFor(debt) > 0 && incoming == debt.lent)
          .toList()
        ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
  return open;
}

/// Whether any of the loan's counterparty words appears in the entry's title.
///
/// Whole words only. "Ali" inside "Alia" is not a name match, and a
/// three-letter substring is exactly the kind of coincidence that would settle
/// somebody else's loan.
bool _namesMatch(String counterparty, Set<String> titleWords) {
  if (titleWords.isEmpty) return false;
  for (final word in _words(counterparty)) {
    if (titleWords.contains(word)) return true;
  }
  return false;
}

/// Words of three letters or more, lowercased. Short tokens are dropped
/// because bank narrations are full of them -- "to", "a/c", "ref" -- and any
/// of them would match nearly everything.
Set<String> _words(String text) => text
    .toLowerCase()
    .split(RegExp('[^a-z0-9]+'))
    .where((word) => word.length >= 3)
    .toSet();

DateTime _startOfDay(DateTime moment) {
  final local = moment.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Entries already in the ledger that look like this loan coming home.
///
/// The mirror of [debtMatchesFor], and deliberately built on it rather than
/// beside it: two matchers that disagree would mean the loan screen and the
/// entry screen suggest different things about the same pair, and only one of
/// them could be right.
///
/// Newest first, because a loan is usually settled by the payment that just
/// arrived rather than one from months ago.
List<TransactionViewData> entriesMatching({
  required DebtViewData debt,
  required Iterable<TransactionViewData> transactions,
  int limit = 3,
}) {
  final outstanding = _roomFor(debt);
  if (outstanding <= 0) return const [];
  final found = <TransactionViewData>[];
  for (final item in transactions) {
    // Cheap tests first. This runs over the whole ledger every time a loan
    // is opened on screen, and the word matching underneath is the only
    // expensive part of it.
    if (item.debtId != null) continue;
    if (item.kind == TransactionKind.transfer) continue;
    if ((item.kind == TransactionKind.income) != debt.lent) continue;
    final amount = item.amount.minorUnits.abs();
    if (amount == 0 || amount > outstanding) continue;
    if (debtMatchesFor(transaction: item, debts: [debt]).isEmpty) continue;
    found.add(item);
  }
  found.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  return found.length > limit ? found.sublist(0, limit) : found;
}
