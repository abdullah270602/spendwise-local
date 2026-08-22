enum ObservationKind { notification, csvImport, manual }

final class RawNotificationSnapshot {
  const RawNotificationSnapshot({
    required this.packageName,
    required this.postedAt,
    this.notificationKey,
    this.title,
    this.text,
    this.bigText,
    this.subText,
    this.sender,
  });

  final String packageName;
  final DateTime postedAt;
  final String? notificationKey;
  final String? title;
  final String? text;
  final String? bigText;
  final String? subText;
  final String? sender;

  String get combinedText => [title, text, bigText, subText]
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .join(' ');
}

/// Immutable evidence exactly as received. It is not itself a transaction.
final class RawObservation {
  const RawObservation({
    required this.id,
    required this.kind,
    required this.observedAt,
    required this.body,
    this.sourcePackage,
    this.title,
    this.accountId,
    this.externalId,
    this.sourceId,
    this.receivedAt,
    this.snapshot,
    this.importBatchId,
    this.importRowNumber,
    this.metadata = const {},
  });

  final String id;
  final ObservationKind kind;
  final DateTime observedAt;
  final String body;
  final String? sourcePackage;
  final String? title;
  final String? accountId;
  final String? externalId;
  final String? sourceId;
  final DateTime? receivedAt;
  final RawNotificationSnapshot? snapshot;
  final String? importBatchId;
  final int? importRowNumber;
  final Map<String, String> metadata;

  String get evidenceFingerprint {
    final importedFingerprint = metadata['dedupeFingerprint']?.trim();
    if (importedFingerprint?.isNotEmpty == true) return importedFingerprint!;
    final normalized = '${sourcePackage ?? ''}|${accountId ?? ''}|$body'
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return externalId?.trim().isNotEmpty == true ? externalId! : normalized;
  }
}

typedef RawEvent = RawObservation;

final class EvidenceLink {
  const EvidenceLink({
    required this.observationId,
    required this.candidateId,
    required this.parserId,
    required this.parserVersion,
    required this.confidence,
    required this.reasons,
  });
  final String observationId;
  final String candidateId;
  final String parserId;
  final int parserVersion;
  final double confidence;
  final List<String> reasons;
}
