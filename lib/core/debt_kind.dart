/// Whose money it was, which is a different question from which way it moved.
///
/// A ledger built on bank alerts sees only that an amount left or arrived. The
/// person knows the rest, and there turned out to be three stories, not two.
///
/// The third is the one that has no name in ordinary accounting: money that
/// lands in your account and was never yours. A brother sends funds to pass to
/// your father; a friend parks money with you; someone asks you to forward it
/// on. You are the courier. It is not income, and paying it onward is not
/// spending -- but crucially it is also not *borrowing*, because borrowed
/// money is yours to spend until you give it back and held money never is.
///
/// That difference is the whole reason this exists rather than being filed
/// under "I owe them": it decides whether the money shows up in what you can
/// spend. Get it wrong and someone else's money sits inside your budget.
enum DebtKind {
  /// Money that went out and is coming back. Still yours the whole time.
  lent(
    id: 'lent',
    title: 'I lent it out',
    detail: 'It went out, and it is coming back. Still yours meanwhile.',
    categoryId: 'lent',
    categoryName: 'Lent out',
    partyLabel: 'Who owes you',
    openLabel: 'Record what they owe',
  ),

  /// Money that came in and goes back later. Yours to spend until it does.
  borrowed(
    id: 'borrowed',
    title: 'I borrowed it',
    detail: 'It came in and goes back later. Yours to spend until then.',
    categoryId: 'borrowed',
    categoryName: 'Borrowed',
    partyLabel: 'Who you owe',
    openLabel: 'Record what you owe',
  ),

  /// Money that came in and was never yours.
  holding(
    id: 'holding',
    title: "I'm holding it for someone",
    detail:
        'It landed in your account but it is not yours to spend. Passing it '
        'on is not spending, and it stays out of what you can spend.',
    categoryId: 'holding',
    categoryName: 'Held for someone',
    partyLabel: 'Who it belongs to',
    openLabel: 'Record what you are holding',
  );

  const DebtKind({
    required this.id,
    required this.title,
    required this.detail,
    required this.categoryId,
    required this.categoryName,
    required this.partyLabel,
    required this.openLabel,
  });

  final String id;
  final String title;
  final String detail;
  final String categoryId;
  final String categoryName;

  /// What to call the other person on the entry form. "Who owes you" and
  /// "who it belongs to" are not the same relationship.
  final String partyLabel;
  final String openLabel;

  /// Whether the money is the user's own while they hold it.
  ///
  /// The single question the whole enum exists to answer. Lent money is still
  /// theirs, borrowed money is theirs to spend until repaid, held money never
  /// is -- so only held money comes out of what they can spend.
  bool get isTheirs => this != holding;

  /// How the debt sits in the accounts: money owed *to* the user, or money the
  /// user owes onward. Holding is a species of owing -- you owe it to whoever
  /// it belongs to -- which is why it stores as a borrowing that was never
  /// yours rather than as a direction of its own.
  bool get owedToUser => this == lent;

  /// Stored as two columns rather than one, because that is what these
  /// actually are: [owedToUser] is which way the money moved, and holding is a
  /// flag on top of it saying the money was never the user's. Encoding it as a
  /// third `direction` value would have meant rebuilding the debts table, and
  /// `transactions.debt_id` cascades on delete.
  static DebtKind fromStorage({required String direction, required bool held}) {
    if (held) return holding;
    return direction == 'lent' ? lent : borrowed;
  }

  String get storedDirection => owedToUser ? 'lent' : 'borrowed';
  bool get storedHeld => this == holding;

  static DebtKind fromId(String? id) {
    for (final kind in values) {
      if (kind.id == id) return kind;
    }
    return lent;
  }
}
