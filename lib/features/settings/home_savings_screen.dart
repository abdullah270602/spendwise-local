import 'package:flutter/material.dart';

import '../../widgets/chooser_kit.dart';
import '../dashboard/home_preview.dart';
import '../dashboard/home_savings.dart';
import '../shell/spendwise_view_model.dart';

/// Two questions about saving, not one list of seven.
///
/// Whether saving comes out of the figure and whether an extra line appears
/// beneath the shape are unrelated decisions, and folding them into a single
/// run of options meant every choice silently cancelled a choice you had not
/// realised you were making. Separated, they compose: you can show only what
/// you can spend *and* still see what you put away.
class HomeSavingsScreen extends StatefulWidget {
  const HomeSavingsScreen({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<HomeSavingsScreen> createState() => _HomeSavingsScreenState();
}

class _HomeSavingsScreenState extends State<HomeSavingsScreen> {
  static const styleKey = 'home_savings';
  static const extraKey = 'home_savings_extra';

  SpendWiseViewModel get viewModel => widget.viewModel;

  HomeSavingsStyle get _style =>
      HomeSavingsStyle.fromId(viewModel.uiViewPreference(styleKey));

  HomeSavingsExtra get _extra => HomeSavingsExtra.resolve(
    viewModel.uiViewPreference(extraKey),
    viewModel.uiViewPreference(styleKey),
    legacyOn: viewModel.uiShowSavingsOnHome,
  );

  void _chooseStyle(HomeSavingsStyle style) {
    // Writing the extra too pins whatever was being inherited from the old
    // combined setting, so choosing a style cannot silently drop the line
    // underneath as a side effect.
    final extra = _extra;
    viewModel.uiSetViewPreference(styleKey, style.id);
    viewModel.uiSetViewPreference(extraKey, extra.id);
    _syncLegacySwitch(style, extra);
    setState(() {});
  }

  void _chooseExtra(HomeSavingsExtra extra) {
    viewModel.uiSetViewPreference(extraKey, extra.id);
    _syncLegacySwitch(_style, extra);
    setState(() {});
  }

  /// The original on/off switch still drives anything that has not moved over.
  /// Savings are "shown" if either half of the choice mentions them.
  void _syncLegacySwitch(HomeSavingsStyle style, HomeSavingsExtra extra) =>
      viewModel.uiSetShowSavingsOnHome(
        style != HomeSavingsStyle.off || extra != HomeSavingsExtra.none,
      );

  @override
  Widget build(BuildContext context) {
    final style = _style;
    final extra = _extra;
    final figures = homeFigures(viewModel);
    final hasSavings = viewModel.accounts.any((account) => !account.isIncluded);

    return ChooserScreen(
      title: 'Savings on Home',
      preview: HomePreview(figures: figures, style: style, extra: extra),
      children: [
        if (!hasSavings)
          const ChoiceGroup(
            label: 'No savings accounts yet',
            caption:
                'Mark an account as Savings and these start meaning something.',
            first: true,
            children: [],
          ),
        ChoiceGroup(
          label: 'In the figure',
          caption: 'Whether saving comes out of what is left.',
          first: hasSavings,
          children: [
            for (final option in HomeSavingsStyle.values)
              ChoiceRow(
                title: option.title,
                detail: option.detail,
                selected: option == style,
                onTap: () => _chooseStyle(option),
              ),
          ],
        ),
        ChoiceGroup(
          label: 'Underneath',
          caption: 'An extra line below the shape. It changes no figure above.',
          children: [
            for (final option in HomeSavingsExtra.values)
              ChoiceRow(
                title: option.title,
                detail: option.detail,
                selected: option == extra,
                onTap: () => _chooseExtra(option),
              ),
          ],
        ),
      ],
    );
  }
}
