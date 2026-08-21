enum CategoryKind { expense, income, transfer }

final class Category {
  const Category({
    required this.id,
    required this.name,
    required this.kind,
    this.parentId,
    this.icon,
    this.colorValue,
    this.archived = false,
  });

  final String id;
  final String name;
  final CategoryKind kind;
  final String? parentId;
  final String? icon;
  final int? colorValue;
  final bool archived;
}
