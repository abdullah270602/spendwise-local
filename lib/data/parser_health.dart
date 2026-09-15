/// What the parser is actually managing, per source, from evidence the
/// ledger already stores.
///
/// This exists because the one number that decides how the parser should
/// grow was nowhere on screen: how much of what a given bank sends does the
/// app read without asking. Every part of it — the raw alert, its parse
/// status, the reason it failed, which parser read it — has been recorded
/// since the beginning and never reported.
///
/// Deliberately not a score. A source can be at 100% because it sends two
/// messages a month, and a source can be at 60% because it sends a daily
/// balance summary the app is right to skip. The counts and the reasons are
/// the point; a single percentage would hide both.
library;

/// One source's record: an app, or an SMS sender.
final class SourceCoverage {
  const SourceCoverage({
    required this.sourceId,
    required this.label,
    required this.packageName,
    required this.institution,
    required this.parsed,
    required this.review,
    required this.error,
    required this.ignored,
    required this.parsers,
    required this.reasons,
    required this.firstSeen,
    required this.lastSeen,
  });

  final String? sourceId;
  final String label;
  final String? packageName;
  final String? institution;

  /// Read cleanly, with an amount and a direction.
  final int parsed;

  /// An amount was found but something about it was unsettled.
  final int review;

  /// Readable in principle, but no account is attached yet.
  final int error;

  /// No amount at all: OTPs, delivery notices, marketing. Correctly skipped,
  /// and excluded from [attempted] because counting them as failures would
  /// punish the parser for declining to invent transactions.
  final int ignored;

  /// parser id -> how many alerts that parser read.
  ///
  /// Worth reading literally rather than as a score. Today every definition
  /// the app ships is a generic *shape* — "sent to X from your account",
  /// "charged at X" — and not one of them is written for a named bank, so a
  /// source read entirely by `pk.card.purchase` is being recognised by its
  /// sentence structure and nothing more. When `parser_definitions` is
  /// finally wired and definitions can name an institution, this is where
  /// that shows up.
  final Map<String, int> parsers;

  /// Why alerts did not land, commonest first. These are the sentences the
  /// parser itself wrote, so they name the gap rather than describing it.
  final List<ReasonCount> reasons;

  final DateTime? firstSeen;
  final DateTime? lastSeen;

  int get attempted => parsed + review + error;
  int get total => attempted + ignored;

  /// Of the alerts that looked like money, how many the app read without
  /// asking. Null when nothing has looked like money yet, because zero out
  /// of zero is not zero.
  double? get coverage => attempted == 0 ? null : parsed / attempted;

  /// Parsers of last resort: no known sentence shape matched, and the alert
  /// was read only because it carried one amount and one direction word.
  ///
  /// This is the honest measure of how much of a source the app does not
  /// recognise. It still gets the money right most of the time, which is
  /// exactly why it is worth counting separately — a source living here is
  /// one bank rewording a message away from silence.
  static const lastResortParsers = {
    'pk.generic.fallback',
    'pk.generic.debit',
    'pk.generic.credit',
    'pakistan.generic.notification',
  };

  int get onLastResort => parsers.entries
      .where((entry) => lastResortParsers.contains(entry.key))
      .fold(0, (sum, entry) => sum + entry.value);
}

final class ReasonCount {
  const ReasonCount(this.reason, this.count);
  final String reason;
  final int count;
}

/// Every source, worst coverage first, plus the totals.
final class ParserHealth {
  const ParserHealth({required this.sources});

  final List<SourceCoverage> sources;

  int get parsed => sources.fold(0, (sum, item) => sum + item.parsed);
  int get review => sources.fold(0, (sum, item) => sum + item.review);
  int get error => sources.fold(0, (sum, item) => sum + item.error);
  int get ignored => sources.fold(0, (sum, item) => sum + item.ignored);
  int get attempted => parsed + review + error;

  double? get coverage => attempted == 0 ? null : parsed / attempted;

  /// Sources sending money alerts the app cannot read. The working list for
  /// deciding what the parser learns next.
  List<SourceCoverage> get needingWork => sources
      .where((item) => item.review + item.error > 0)
      .toList()
    ..sort((a, b) => (b.review + b.error).compareTo(a.review + a.error));
}
