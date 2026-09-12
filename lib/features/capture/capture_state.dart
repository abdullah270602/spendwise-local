import 'package:flutter/material.dart';

import '../settings/source_selection_screen.dart';
import '../shell/spendwise_view_model.dart';

/// Whether anything is being read for bank alerts.
///
/// Notification access can be granted with every source switched off, which
/// stops capture as surely as never granting it. The only surface that said so
/// was a subtitle in Settings, so the two screens that promise alerts will
/// arrive went on promising it in the one state where they cannot keep it.
///
/// This lives in its own file rather than on either screen. Home and the
/// Ledger both report it, and the first version had the Ledger importing the
/// dashboard to borrow the wording -- which works, and quietly says the
/// dashboard owns a fact that is really about capture.
bool captureIsOff(SpendWiseViewModel viewModel) =>
    viewModel.notificationAccessGranted &&
    !viewModel.sources.any((source) => source.enabled);

/// Written once, because Home and the Ledger report one fact here, and a
/// second copy of the wording is a second chance for them to disagree.
const captureOffDetail =
    'No app is being read for alerts, so nothing can arrive. Pick your bank '
    'in Settings, under Notification sources.';

/// The way out of that state, rather than directions to it.
class ChooseSourcesButton extends StatelessWidget {
  const ChooseSourcesButton({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: () => Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SourceSelectionScreen(viewModel: viewModel),
      ),
    ),
    child: const Text('Choose notification sources'),
  );
}

/// Said before access is granted at all, which is the state every new install
/// starts in.
const captureUngrantedDetail =
    'Turn on notification access and SpendWise will start reading your bank '
    'alerts.';

/// The way out of *that* state.
class TurnOnAccessButton extends StatelessWidget {
  const TurnOnAccessButton({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: viewModel.requestNotificationAccess,
    child: const Text('Turn on notification access'),
  );
}

/// Why an empty screen is empty, when the reason is that nothing is being
/// read -- and the control that fixes it. Null when capture is live, because
/// then the emptiness is honest and the screen's own wording is true.
///
/// Two things can be wrong at once and only one of them is worth saying
/// first: a source list is no use to somebody the listener cannot read for,
/// so refused access is reported ahead of an empty source list.
///
/// Home spells the same two answers out inline. It predates this file and is
/// being edited elsewhere; it is the one screen not reading from here.
({String detail, Widget action})? captureGap(SpendWiseViewModel viewModel) {
  if (!viewModel.notificationAccessGranted) {
    return (
      detail: captureUngrantedDetail,
      action: TurnOnAccessButton(viewModel: viewModel),
    );
  }
  if (captureIsOff(viewModel)) {
    return (
      detail: captureOffDetail,
      action: ChooseSourcesButton(viewModel: viewModel),
    );
  }
  return null;
}
