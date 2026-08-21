enum SourceType { bankApp, walletApp, sms, statement, manual, other }

final class Source {
  const Source({
    required this.id,
    required this.name,
    required this.type,
    this.accountId,
    this.packageNames = const {},
    this.senderIds = const {},
    this.enabled = true,
  });

  final String id;
  final String name;
  final SourceType type;
  final String? accountId;
  final Set<String> packageNames;
  final Set<String> senderIds;
  final bool enabled;
}
