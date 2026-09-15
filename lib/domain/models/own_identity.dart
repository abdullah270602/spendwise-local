/// Deterministic recognition of "this counterparty is me" — used to treat a
/// bank/wallet leg as a transfer between the user's own tracked accounts even
/// when the opposing leg is a weak match (delayed settlement, no shared
/// reference). Empty by default, so behavior is unchanged until the user
/// configures their name(s) or an account's number suffix.
final class OwnIdentity {
  const OwnIdentity({
    this.names = const {},
    this.accountSuffixes = const {},
    this.accountAliases = const {},
  });

  /// The user's own name variants, as they might appear as a counterparty in
  /// bank/wallet SMS or notification text (e.g. "YOUR FULL NAME").
  final Set<String> names;

  /// accountId -> digits-only account-number suffix used to recognize a debit
  /// aimed at that specific tracked account (e.g. "4821").
  final Map<String, String> accountSuffixes;

  /// accountId -> the words that name that account in free text: its own
  /// name and its institution's ("pocket", "northbank ltd", "northbank").
  ///
  /// Only ever used together with the number tail, never alone -- a bank's
  /// name appears in every marketing line it sends.
  final Map<String, Set<String>> accountAliases;

  /// Shortest suffix that can single out an account inside free text. Two or
  /// three digits collide with dates, quantities, and reference fragments far
  /// too often to be treated as identifying.
  static const minimumSuffixDigits = 4;

  bool get isConfigured =>
      names.isNotEmpty ||
      accountSuffixes.values.any((s) => s.length >= minimumSuffixDigits);

  bool matchesOwnName(String? counterparty) {
    if (names.isEmpty) return false;
    final normalized = _normalizeName(counterparty);
    if (normalized.isEmpty) return false;
    return names.any((name) => normalized.contains(_normalizeName(name)));
  }

  bool matchesAccount(String? counterparty, String accountId) {
    final suffix = accountSuffixes[accountId];
    if (suffix == null ||
        suffix.length < minimumSuffixDigits ||
        counterparty == null) {
      return false;
    }
    final digits = counterparty.replaceAll(RegExp(r'\D'), '');
    return digits.isNotEmpty && digits.contains(suffix);
  }

  /// Accounts this text names outright, by writing one of their aliases
  /// immediately in front of their registered number tail -- "Northbank-9001",
  /// "Southbank 9002", "pocket#9003".
  ///
  /// This is how one alert manages to name both ends of a movement by
  /// itself. A wallet top-up says where the money came from ("Rs. 10,000
  /// loaded through Northbank-9001 linked account") and the funding bank often
  /// sends nothing at all, so waiting for an opposing leg waits forever.
  ///
  /// Both halves are required. A bare tail is not enough: four digits
  /// collide with amounts, dates and reference fragments constantly, and
  /// reading "PKR 90,010" as an account ending 9001 would invent a transfer
  /// out of a payment. A bare name is not enough either, for the same reason
  /// the router does not trust one. Together they are specific enough to act
  /// on.
  Set<String> accountsNamedWithNumber(String text) {
    final haystack = text.toLowerCase();
    final found = <String>{};
    for (final entry in accountSuffixes.entries) {
      final suffix = entry.value.replaceAll(RegExp(r'\D'), '');
      if (suffix.length < minimumSuffixDigits) continue;
      for (final alias in accountAliases[entry.key] ?? const <String>{}) {
        final normalized = alias.toLowerCase().trim();
        if (normalized.length < 3) continue;
        // Alias, then at most a little punctuation or the words a sentence
        // puts between a bank and its number, then the tail. Masking
        // characters are allowed because that is how banks print a tail.
        final pattern = RegExp(
          '${RegExp.escape(normalized)}'
          r'[\s\-_#:.]{0,3}(?:a\/?c|acct|account|no|ending(?:\s+in)?)?'
          r'[\s\-_#:.]{0,3}[*x•]{0,6}\s*\d{0,8}?'
          '${RegExp.escape(suffix)}'
          r'(?!\d)',
          caseSensitive: false,
        );
        if (pattern.hasMatch(haystack)) {
          found.add(entry.key);
          break;
        }
      }
    }
    return found;
  }

  static String _normalizeName(String? value) =>
      ' ${(value ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()} ';
}
