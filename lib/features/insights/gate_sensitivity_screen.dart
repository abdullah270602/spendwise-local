import 'package:flutter/material.dart';

import '../../app/category_tones.dart';
import '../../app/theme.dart';
import '../../widgets/chooser_kit.dart';
import 'gate.dart';
import 'spending_analytics.dart';

/// Choosing what The Gate calls unusual.
///
/// Built from the same `ChooserScreen` / `ChoiceGroup` / `ChoiceRow` idiom as
/// every other question this app asks about how a screen is drawn -- one
/// pinned preview, held still, and the options that change it. The preview
/// above is a real `Gate`, drawn from real data, not an illustration of one:
/// tapping a level below visibly moves rows between its two bands, which is
/// the whole point of the setting.
class GateSensitivityScreen extends StatefulWidget {
  const GateSensitivityScreen({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.preview,
    required this.tones,
    required this.totalSpendingMinor,
    required this.currency,
  });

  final GateSensitivity selected;
  final ValueChanged<GateSensitivity> onSelected;

  /// Real category changes for a real period, so the preview can never
  /// describe a rule the screen would then draw differently.
  final List<CategoryAnalytics> preview;

  final CategoryTones tones;
  final int totalSpendingMinor;
  final String currency;

  @override
  State<GateSensitivityScreen> createState() => _GateSensitivityScreenState();
}

class _GateSensitivityScreenState extends State<GateSensitivityScreen> {
  late GateSensitivity sensitivity = widget.selected;

  /// Selection inside the preview is a demonstration, not a decision -- this
  /// screen has no category filter of its own for a tap to set. Held here
  /// only so the preview's rows answer a tap the same way the real board's
  /// do, rather than being the one `Gate` on the app that quietly ignores one.
  String? _previewSelected;

  void _choose(GateSensitivity value) {
    if (value == sensitivity) return;
    setState(() => sensitivity = value);
    widget.onSelected(value);
  }

  @override
  Widget build(BuildContext context) => ChooserScreen(
    title: 'What counts as moved',
    preview: Gate(
      changes: widget.preview,
      tones: widget.tones,
      sensitivity: sensitivity,
      totalSpendingMinor: widget.totalSpendingMinor,
      selected: _previewSelected,
      onSelect: (value) => setState(() => _previewSelected = value),
      currency: widget.currency,
    ),
    children: [
      ChoiceGroup(
        label: 'The corridor',
        caption:
            'How far a category has to move, up or down, before The Gate '
            'calls it out.',
        first: true,
        children: [
          for (final option in GateSensitivity.values)
            ChoiceRow(
              title: option.title,
              detail: option.detail,
              selected: option == sensitivity,
              onTap: () => _choose(option),
            ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(
          'Whatever you choose, a move under 1% of everything you spent '
          "this period never counts as loud. The corridor decides what's "
          "unusual — this floor decides what's trivial — and a setting can "
          'only tune the first one.',
          style: SpendWiseType.body.copyWith(
            fontSize: 12,
            color: SpendWiseColors.dim,
          ),
        ),
      ),
    ],
  );
}
