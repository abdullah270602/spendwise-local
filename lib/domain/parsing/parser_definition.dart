import '../models/event_candidate.dart';
import '../models/raw_observation.dart';

final class ParserRule {
  const ParserRule({
    required this.id,
    required this.pattern,
    required this.direction,
    this.type = CandidateType.unknown,
    this.amountGroup = 'amount',
    this.referenceGroup = 'reference',
    this.counterpartyGroup = 'counterparty',
    this.confidence = 0.9,
  });

  final String id;
  final RegExp pattern;
  final EntryDirection direction;
  final CandidateType type;
  final String amountGroup;
  final String referenceGroup;
  final String counterpartyGroup;
  final double confidence;
}

final class ParserDefinition {
  const ParserDefinition({
    required this.id,
    required this.version,
    required this.rules,
    this.packageNames = const {},
    this.senders = const {},
  });

  final String id;
  final int version;
  final Set<String> packageNames;
  final Set<String> senders;
  final List<ParserRule> rules;

  bool supports(RawObservation raw) {
    final package = raw.snapshot?.packageName ?? raw.sourcePackage;
    final sender = raw.snapshot?.sender ?? raw.metadata['sender'];
    return (packageNames.isEmpty || packageNames.contains(package)) &&
        (senders.isEmpty || senders.contains(sender));
  }
}

enum ParseStatus { parsed, unsupported, ambiguous, invalid }

final class ParserResult {
  const ParserResult({
    required this.status,
    required this.parserId,
    required this.parserVersion,
    required this.confidence,
    required this.reasons,
    this.candidate,
  });

  final ParseStatus status;
  final String parserId;
  final int parserVersion;
  final double confidence;
  final List<String> reasons;
  final EventCandidate? candidate;
}

final class ParserRegistry {
  ParserRegistry([Iterable<ParserDefinition> definitions = const []])
    : _definitions = List.unmodifiable(definitions);

  final List<ParserDefinition> _definitions;
  List<ParserDefinition> get definitions => _definitions;

  Iterable<ParserDefinition> matching(RawObservation raw) =>
      _definitions.where((definition) => definition.supports(raw));

  ParserRegistry withDefinition(ParserDefinition definition) =>
      ParserRegistry([..._definitions, definition]);
}
