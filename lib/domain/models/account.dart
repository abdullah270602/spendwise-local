enum AccountType { bank, wallet, cash, card, other }

final class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    this.currency = 'PKR',
    this.notificationPackages = const <String>{},
    this.archived = false,
  });

  final String id;
  final String name;
  final AccountType type;
  final String currency;
  final Set<String> notificationPackages;
  final bool archived;
}
