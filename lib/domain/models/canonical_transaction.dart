import '../../core/money.dart';

enum TransactionKind { expense, income, transfer }

enum TransactionOrigin { automatic, manual }

enum ReconciliationState { confirmed, probable, needsReview }

enum ReconciliationDecisionType { mergeEvidence, pairTransfer, keepSeparate }

final class ReconciliationDecision {
  const ReconciliationDecision({
    required this.id,
    required this.type,
    required this.candidateIds,
    required this.score,
    required this.reasons,
    this.reversible = true,
  });
  final String id;
  final ReconciliationDecisionType type;
  final Set<String> candidateIds;
  final double score;
  final List<String> reasons;
  final bool reversible;
}

final class CanonicalTransaction {
  const CanonicalTransaction({
    required this.id,
    required this.kind,
    required this.amount,
    required this.occurredAt,
    required this.evidenceIds,
    this.accountId,
    this.fromAccountId,
    this.toAccountId,
    this.description,
    this.needsReview = false,
    this.locked = false,
    this.origin = TransactionOrigin.automatic,
    this.reconciliationState,
    this.decisionIds = const {},
  });

  final String id;
  final TransactionKind kind;
  final Money amount;
  final DateTime occurredAt;
  final Set<String> evidenceIds;
  final String? accountId;
  final String? fromAccountId;
  final String? toAccountId;
  final String? description;
  final bool needsReview;
  final bool locked;
  final TransactionOrigin origin;
  final ReconciliationState? reconciliationState;
  final Set<String> decisionIds;

  ReconciliationState get effectiveReconciliationState =>
      reconciliationState ??
      (needsReview
          ? ReconciliationState.needsReview
          : ReconciliationState.confirmed);

  CanonicalTransaction copyWith({Set<String>? evidenceIds}) =>
      CanonicalTransaction(
        id: id,
        kind: kind,
        amount: amount,
        occurredAt: occurredAt,
        evidenceIds: evidenceIds ?? this.evidenceIds,
        accountId: accountId,
        fromAccountId: fromAccountId,
        toAccountId: toAccountId,
        description: description,
        needsReview: needsReview,
        locked: locked,
        origin: origin,
        reconciliationState: reconciliationState,
        decisionIds: decisionIds,
      );
}
