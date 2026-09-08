import 'package:flutter/widgets.dart';

import '../features/shell/spendwise_view_model.dart';
import 'theme.dart';

/// Which tone a category is drawn in, and which slot it answers to.
///
/// Keyed to the app's own list of categories — system ones first, then the
/// user's, both alphabetical, which is the order the database returns — and
/// deliberately not to a category's position in whatever is being drawn right
/// now. Position moves every time spending does: a category that slipped from
/// third to fourth changed colour, so "the sage one" meant nothing from one
/// month to the next, and two screens showing the same month could disagree
/// with each other because they had ranked it differently.
///
/// The list only changes when a category is added or removed, which is rare,
/// and adding one never disturbs the system categories that most spending
/// falls under.
class CategoryTones {
  const CategoryTones._(this._slots);

  /// [known] is the app's stable category list. [present] is whatever is about
  /// to be drawn, so that anything not in the list still gets its own slot
  /// rather than colliding with a neighbour.
  factory CategoryTones({
    required Iterable<String> known,
    Iterable<String> present = const [],
  }) {
    final slots = <String, int>{};
    var next = 0;
    for (final name in known) {
      if (slots.containsKey(name)) continue;
      slots[name] = next++;
    }
    // A category the app has no row for yet — one read off a notification
    // before it has been filed — still has to be drawn, and drawn differently
    // from the category beside it. Sorted so it at least holds one tone for as
    // long as it stays unknown, rather than shuffling on every rebuild.
    final strangers =
        present.where((name) => !slots.containsKey(name)).toSet().toList()
          ..sort();
    for (final name in strangers) {
      slots[name] = next++;
    }
    return CategoryTones._(slots);
  }

  /// For previews and tests that have no ledger behind them: tone follows the
  /// order given, which is what every screen did before this existed.
  factory CategoryTones.positional(Iterable<String> names) =>
      CategoryTones(known: names);

  final Map<String, int> _slots;

  /// The category's slot, or its own stable place past the end if the app has
  /// never heard of it. Never negative, so it can always index the ramp.
  int slotOf(String category) => _slots[category] ?? _slots.length;

  Color of(String category) => SpendWiseColors.category(slotOf(category));

  /// The number a category answers to when one is printed beside it, as on
  /// the mixing desk's channel strip. One-based, because a channel numbered
  /// zero is not a thing anyone has seen on hardware.
  int channelOf(String category) => slotOf(category) + 1;
}

extension CategoryTonesFor on SpendWiseViewModel {
  /// Tones for whatever is about to be drawn, keyed to the ledger's own
  /// category order.
  ///
  /// On a view model with no ledger behind it — a preview, a test double —
  /// `uiCategories` is empty and this falls back to the order of what is
  /// present, which is what every screen did before.
  CategoryTones tonesFor(Iterable<String> present) => CategoryTones(
    known: uiCategories.map((item) => item.name),
    present: present,
  );
}
