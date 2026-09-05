/// What is known about one of the user's accounts for routing purposes.
final class AccountProfile {
  const AccountProfile({
    required this.id,
    required this.name,
    this.institution = '',
    this.suffix = '',
  });

  final String id;
  final String name;
  final String institution;

  /// The account-number tail the user registered, digits only.
  final String suffix;
}

final class AccountRouting {
  const AccountRouting({
    required this.accountId,
    required this.score,
    required this.reason,
  });

  final String accountId;
  final int score;
  final String reason;
}

/// Decides which of the user's accounts an alert belongs to, from what the
/// alert itself says.
///
/// Attribution used to follow the delivering app, which works for a bank's
/// own app but collapses for SMS: every bank's messages arrive through the
/// one messaging app, so they all landed in whichever single account that
/// app was attached to. A Meezan message filed under UBL is wrong on its
/// face, and it also makes a genuine Meezan-to-UBL transfer look like two
/// entries on one account, which can never be paired.
///
/// Deliberately abstains when the evidence does not single out one account:
/// leaving an alert for review is recoverable, filing it against the wrong
/// account quietly corrupts balances.
final class AccountRouter {
  const AccountRouter();

  /// Account-number tails, read only where the text is actually talking
  /// about an account. Bare digit runs are avoided because an amount like
  /// "PKR 1,234" would otherwise match an account ending 1234.
  static final RegExp _accountNumberContext = RegExp(
    r'(?:a\/?c|acct|account|ending|ending\s+in|no\.?)\s*[:#]?\s*[*xX•\-\s]*(\d{4,})',
    caseSensitive: false,
  );
  static final RegExp _maskedNumber = RegExp(
    r'[*xX•]{2,}\s*(\d{4,})',
    caseSensitive: false,
  );

  AccountRouting? route({
    required String text,
    String? sender,
    required List<AccountProfile> accounts,
  }) {
    if (accounts.isEmpty) return null;
    final haystack = _normalize('${sender ?? ''} $text');
    final senderText = _normalize(sender ?? '');
    final fragments = _accountNumberFragments(text);

    AccountRouting? best;
    var runnerUp = 0;
    for (final account in accounts) {
      var score = 0;
      final reasons = <String>[];

      final suffix = account.suffix.replaceAll(RegExp(r'\D'), '');
      if (suffix.length >= 4 &&
          fragments.any(
            (fragment) =>
                fragment == suffix ||
                fragment.endsWith(suffix) ||
                suffix.endsWith(fragment),
          )) {
        score += 100;
        reasons.add('account ending $suffix');
      }

      final institution = _normalize(account.institution);
      if (institution.length >= 3) {
        if (_contains(senderText, institution)) {
          score += 60;
          reasons.add('sender names ${account.institution}');
        } else if (_contains(haystack, institution)) {
          score += 40;
          reasons.add('mentions ${account.institution}');
        }
      }

      final name = _normalize(account.name);
      if (name.length >= 3 && _contains(haystack, name)) {
        score += 30;
        reasons.add('mentions ${account.name}');
      } else {
        // "Meezan Debit" should still be recognised by a message that only
        // says "Meezan".
        for (final word in name.split(' ')) {
          if (word.length >= 4 && _contains(haystack, word)) {
            score += 20;
            reasons.add('mentions $word');
            break;
          }
        }
      }

      if (score == 0) continue;
      if (best == null || score > best.score) {
        runnerUp = best?.score ?? 0;
        best = AccountRouting(
          accountId: account.id,
          score: score,
          reason: reasons.join(', '),
        );
      } else if (score > runnerUp) {
        runnerUp = score;
      }
    }

    // A tie means the alert did not single out one account.
    if (best == null || best.score == runnerUp) return null;
    return best;
  }

  List<String> _accountNumberFragments(String text) => [
    for (final match in _accountNumberContext.allMatches(text))
      if (match.group(1) != null) match.group(1)!,
    for (final match in _maskedNumber.allMatches(text))
      if (match.group(1) != null) match.group(1)!,
  ];

  static bool _contains(String haystack, String needle) =>
      needle.isNotEmpty && ' $haystack '.contains(' $needle ');

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
