/// Deterministic recognition of "this counterparty is me" — used to treat a
/// bank/wallet leg as a transfer between the user's own tracked accounts even
/// when the opposing leg is a weak match (delayed settlement, no shared
/// reference). Empty by default, so behavior is unchanged until the user
/// configures their name(s) or an account's number suffix.
final class OwnIdentity {
  const OwnIdentity({this.names = const {}, this.accountSuffixes = const {}});

  /// The user's own name variants, as they might appear as a counterparty in
  /// bank/wallet SMS or notification text (e.g. "ABDULLAH NASEEM").
  final Set<String> names;

  /// accountId -> digits-only account-number suffix used to recognize a debit
  /// aimed at that specific tracked account (e.g. "4821").
  final Map<String, String> accountSuffixes;

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

  static String _normalizeName(String? value) =>
      ' ${(value ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()} ';
}
