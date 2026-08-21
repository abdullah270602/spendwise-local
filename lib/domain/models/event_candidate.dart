import '../../core/money.dart';
import 'raw_observation.dart';

enum EntryDirection { debit, credit }

enum CandidateType {
  purchase,
  cashWithdrawal,
  fee,
  refund,
  income,
  transfer,
  unknown,
}

/// A deterministic interpretation of one raw observation.
final class EventCandidate {
  const EventCandidate({
    required this.id,
    required this.observation,
    required this.accountId,
    required this.amount,
    required this.direction,
    required this.occurredAt,
    this.counterparty,
    this.reference,
    this.description,
    this.confidence = 1,
    this.type = CandidateType.unknown,
    this.parserId = 'manual',
    this.parserVersion = 1,
    this.reasons = const [],
  }) : assert(confidence >= 0 && confidence <= 1);

  final String id;
  final RawObservation observation;
  final String accountId;
  final Money amount;
  final EntryDirection direction;
  final DateTime occurredAt;
  final String? counterparty;
  final String? reference;
  final String? description;
  final double confidence;
  final CandidateType type;
  final String parserId;
  final int parserVersion;
  final List<String> reasons;
}
