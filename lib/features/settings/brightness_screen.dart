import 'package:flutter/material.dart';

import '../../app/brightness_choice.dart';
import '../../app/ground.dart';
import '../../app/theme.dart';
import '../../main.dart';
import '../../widgets/chooser_kit.dart';
import '../dashboard/home_preview.dart';
import '../dashboard/home_savings.dart';
import '../shell/spendwise_view_model.dart';

/// Choosing the ground the app stands on.
///
/// Built from the same parts as the palette picker, and for the same reason:
/// a row of words cannot tell you what a ground feels like carrying a real
/// amount of money at the size Home draws it. Tapping a choice repaints the
/// app under your finger, so the preview is the thing itself.
class BrightnessScreen extends StatefulWidget {
  const BrightnessScreen({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<BrightnessScreen> createState() => _BrightnessScreenState();
}

class _BrightnessScreenState extends State<BrightnessScreen> {
  SpendWiseViewModel get viewModel => widget.viewModel;

  void _choose(BrightnessChoice choice) {
    if (choice == brightnessChoice.value) return;
    viewModel.uiSetViewPreference(BrightnessChoice.preferenceKey, choice.id);
    brightnessChoice.value = choice;
    // Repaint from the root, exactly as the palette does: `ThemeData` carries
    // these colours, and so do the widgets that read `SpendWiseColors`
    // directly. `BrightnessScope` already rebuilds off the notifier above,
    // but the revision is what forces the subtree under `MaterialApp` -- the
    // pushed route this screen is sitting in included.
    paletteRevision.value++;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final figures = homeFigures(viewModel);
    return ChooserScreen(
      title: 'Light or dark',
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
          label: 'Ground',
          caption: 'What everything else is drawn on.',
          first: true,
          children: [
            for (final choice in BrightnessChoice.values)
              ChoiceRow(
                title: choice.title,
                detail: choice.blurb,
                selected: choice == brightnessChoice.value,
                leading: _GroundSwatch(choice: choice),
                onTap: () => _choose(choice),
              ),
          ],
        ),
      ],
    );
  }
}

/// The ground and its ink, at swatch size.
///
/// System shows both halves, because both are answers it might give.
class _GroundSwatch extends StatelessWidget {
  const _GroundSwatch({required this.choice});

  final BrightnessChoice choice;

  @override
  Widget build(BuildContext context) {
    final grounds = switch (choice) {
      BrightnessChoice.system => Ground.all,
      BrightnessChoice.light => const [Ground.paper],
      BrightnessChoice.dark => const [Ground.graphite],
    };
    return SizedBox(
      width: 34,
      height: 22,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final ground in grounds)
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ground.bg,
                  border: Border.all(color: SpendWiseColors.edge),
                ),
                child: Center(
                  child: Container(width: 8, height: 2, color: ground.fg),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
