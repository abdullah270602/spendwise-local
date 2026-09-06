import 'package:flutter/material.dart';

import '../../app/palette.dart';
import '../../app/theme.dart';
import '../../main.dart';
import '../../widgets/chooser_kit.dart';
import '../dashboard/home_preview.dart';
import '../dashboard/home_savings.dart';
import '../shell/spendwise_view_model.dart';

/// Choosing the three tones that carry meaning.
///
/// A row of swatches shows the colours; it does not show what they will feel
/// like carrying a real amount of money at the size Home draws it. So the
/// preview is Home itself, and tapping a palette repaints it -- the app is
/// already re-themed by the time your finger lifts, which is a truer preview
/// than any sample block.
class PaletteScreen extends StatefulWidget {
  const PaletteScreen({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<PaletteScreen> createState() => _PaletteScreenState();
}

class _PaletteScreenState extends State<PaletteScreen> {
  SpendWiseViewModel get viewModel => widget.viewModel;

  void _choose(SpendWisePalette palette) {
    if (palette.id == SpendWiseColors.palette.id) return;
    SpendWiseColors.apply(palette);
    viewModel.uiSetViewPreference('palette', palette.id);
    // Repaint from the root: ThemeData itself carries these colours.
    paletteRevision.value++;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final figures = homeFigures(viewModel);
    return ChooserScreen(
      title: 'Colour',
      preview: HomePreview(
        figures: figures,
        style: HomeSavingsStyle.fromId(
          viewModel.uiViewPreference('home_savings'),
        ),
        extra: HomeSavingsExtra.resolve(
          viewModel.uiViewPreference('home_savings_extra'),
          viewModel.uiViewPreference('home_savings'),
          legacyOn: viewModel.uiShowSavingsOnHome,
        ),
      ),
      children: [
        ChoiceGroup(
          label: 'Palette',
          caption: 'Kept, moved between your own accounts, and gone.',
          first: true,
          children: [
            for (final palette in SpendWisePalette.all)
              ChoiceRow(
                title: palette.name,
                detail: palette.blurb,
                selected: palette.id == SpendWiseColors.palette.id,
                tone: palette.keep,
                leading: _Swatch(palette: palette),
                onTap: () => _choose(palette),
              ),
          ],
        ),
      ],
    );
  }
}

/// The three tones in the order the app uses them.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.palette});

  final SpendWisePalette palette;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 34,
    height: 22,
    // Stretch, or a childless ColoredBox inside Expanded gets a tight width
    // and the swatch collapses to nothing.
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 5, child: ColoredBox(color: palette.keep)),
        Expanded(flex: 2, child: ColoredBox(color: palette.mine)),
        Expanded(flex: 3, child: ColoredBox(color: palette.spend)),
      ],
    ),
  );
}
