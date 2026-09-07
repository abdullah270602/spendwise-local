import 'package:flutter/material.dart';

import '../../widgets/chooser_kit.dart';
import '../dashboard/home_categories.dart';
import '../dashboard/home_preview.dart';
import '../shell/spendwise_view_model.dart';

/// Choosing how much of the breakdown Home draws.
///
/// The bar is what the preview is for. It is drawn to true proportion, which
/// is exactly why the middle option keeps a line for everything it does not
/// name: dropping the tail would stretch the survivors to fill the bar, and a
/// category worth a fifth of the month would be drawn as though it were worth
/// twice that.
class HomeCategoriesScreen extends StatefulWidget {
  const HomeCategoriesScreen({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<HomeCategoriesScreen> createState() => _HomeCategoriesScreenState();
}

class _HomeCategoriesScreenState extends State<HomeCategoriesScreen> {
  static const _key = 'home_categories';

  SpendWiseViewModel get viewModel => widget.viewModel;

  HomeCategories get _current =>
      HomeCategories.fromId(viewModel.uiViewPreference(_key));

  void _choose(HomeCategories style) {
    viewModel.uiSetViewPreference(_key, style.id);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final spending = viewModel.dashboard.categorySpending;

    return ChooserScreen(
      title: 'Categories on Home',
      preview: CategoryPreview(spending: spending, style: current),
      children: [
        ChoiceGroup(
          label: 'Under the figures',
          caption: 'How much of where the money went Home draws.',
          first: true,
          children: [
            for (final style in HomeCategories.values)
              ChoiceRow(
                title: style.title,
                detail: style.detail,
                selected: style == current,
                onTap: () => _choose(style),
              ),
          ],
        ),
      ],
    );
  }
}
