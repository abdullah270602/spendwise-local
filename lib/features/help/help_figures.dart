import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../shell/spendwise_view_model.dart';

/// The swipe gestures, as a thing you do rather than a thing you read.
///
/// Swiping a row to confirm or delete has no real-world analogue, which is
/// the one case the usability literature agrees is worth teaching explicitly.
/// It is also the case where doing beats watching: the classic animated-demo
/// experiments found people who watched performed well immediately and then
/// failed the retention test, because watching encodes almost nothing. So
/// this is a real row, with the real gesture, that really answers.
class SwipeDemo extends StatefulWidget {
  const SwipeDemo({super.key});

  @override
  State<SwipeDemo> createState() => _SwipeDemoState();
}

class _SwipeDemoState extends State<SwipeDemo> {
  /// Bumped to bring the row back, since a dismissed Dismissible is gone.
  int generation = 0;
  DismissDirection? outcome;

  void _reset() => setState(() {
    outcome = null;
    generation++;
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          border: Border.all(color: SpendWiseColors.edge),
        ),
        child: outcome == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Try it · swipe the row'),
                  const SizedBox(height: 10),
                  Dismissible(
                    key: ValueKey(generation),
                    background: _Hint(
                      icon: Icons.check_rounded,
                      label: 'Confirm',
                      tone: SpendWiseColors.keep,
                      alignment: Alignment.centerLeft,
                    ),
                    secondaryBackground: _Hint(
                      icon: Icons.close_rounded,
                      label: 'Delete',
                      tone: SpendWiseColors.spend,
                      alignment: Alignment.centerRight,
                    ),
                    onDismissed: (direction) =>
                        setState(() => outcome = direction),
                    child: RegisterRow(
                      name: 'Valley Mart',
                      meta: 'Groceries · Everyday',
                      amount: '−2,450.00',
                      amountColor: SpendWiseColors.spend,
                    ),
                  ),
                ],
              )
            : _Outcome(direction: outcome!, onReset: _reset),
      ),
    ],
  );
}

class _Hint extends StatelessWidget {
  const _Hint({
    required this.icon,
    required this.label,
    required this.tone,
    required this.alignment,
  });

  final IconData icon;
  final String label;
  final Color tone;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Container(
    alignment: alignment,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: tone),
        const SizedBox(width: 6),
        Text(
          label,
          style: SpendWiseType.metaTight.copyWith(color: tone),
        ),
      ],
    ),
  );
}

class _Outcome extends StatelessWidget {
  const _Outcome({required this.direction, required this.onReset});

  final DismissDirection direction;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final confirmed = direction == DismissDirection.startToEnd;
    return Row(
      children: [
        Expanded(
          child: Text(
            confirmed
                ? 'Confirmed. It is locked in.'
                : 'Deleted. It was never a transaction.',
            style: SpendWiseType.row.copyWith(
              fontSize: 14,
              color: confirmed
                  ? SpendWiseColors.keep
                  : SpendWiseColors.spend,
            ),
          ),
        ),
        TextButton(
          onPressed: onReset,
          style: TextButton.styleFrom(
            foregroundColor: SpendWiseColors.dim,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Again'),
        ),
      ],
    );
  }
}

/// The privacy claim, checked against the installed package.
///
/// Every other way of putting this is the app asserting something about
/// itself. This asks Android what the app is actually allowed to do and
/// prints the answer, INTERNET conspicuously not among it.
class PermissionsFigure extends StatefulWidget {
  const PermissionsFigure({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<PermissionsFigure> createState() => _PermissionsFigureState();
}

class _PermissionsFigureState extends State<PermissionsFigure> {
  late final Future<List<String>> permissions = widget.viewModel
      .uiDeclaredPermissions();

  @override
  Widget build(BuildContext context) => FutureBuilder<List<String>>(
    future: permissions,
    builder: (context, snapshot) {
      final granted = snapshot.data;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
        decoration: BoxDecoration(
          border: Border.all(color: SpendWiseColors.edge),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('What this app may do, per Android'),
            const SizedBox(height: 11),
            if (granted == null)
              Text('Reading…', style: SpendWiseType.meta)
            else ...[
              for (final name in granted)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    name.replaceFirst('android.permission.', ''),
                    style: SpendWiseType.meta.copyWith(
                      color: SpendWiseColors.fg,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 14,
                    height: 2,
                    color: SpendWiseColors.keep,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      granted.any((name) => name.endsWith('INTERNET'))
                          // Only reachable if a dependency ever slipped one in,
                          // which is exactly why this is read and not typed.
                          ? 'INTERNET is present. That should not be possible.'
                          : 'No INTERNET. There is nowhere to send anything.',
                      style: SpendWiseType.body.copyWith(
                        fontSize: 12.5,
                        color: granted.any((name) => name.endsWith('INTERNET'))
                            ? SpendWiseColors.spend
                            : SpendWiseColors.keep,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// Copies a ready-made prompt about one part of the guide.
///
/// The app cannot answer questions -- it has no network and never will -- so
/// the useful thing it can do is hand you a well-formed question to ask
/// somewhere that can, with enough context that the answer is about
/// SpendWise rather than about budgeting apps in general.
class CopyPromptButton extends StatelessWidget {
  const CopyPromptButton({
    super.key,
    required this.title,
    required this.brief,
    this.dense = false,
  });

  final String title;
  final String brief;
  final bool dense;

  static const _preamble =
      'I am using SpendWise, an offline Android app that turns bank SMS and '
      'notification alerts into a personal spending ledger. It has no '
      'internet permission at all, so everything happens on the phone: '
      'nothing syncs, uploads, or backs up, and the ledger is encrypted on '
      'the device.\n\n'
      'Here is the part of its guide I am asking about.';

  String get prompt => '$_preamble\n\n--- $title ---\n$brief\n\nMy question: ';

  @override
  Widget build(BuildContext context) {
    Future<void> copy() async {
      await Clipboard.setData(ClipboardData(text: prompt));
      if (!context.mounted) return;
      HapticFeedback.selectionClick();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prompt copied. Paste it to any AI assistant.'),
        ),
      );
    }

    if (dense) {
      return IconButton(
        onPressed: copy,
        tooltip: 'Copy a prompt about this',
        icon: const Icon(Icons.content_copy_rounded, size: 18),
      );
    }
    return OutlinedButton.icon(
      onPressed: copy,
      icon: const Icon(Icons.content_copy_rounded, size: 16),
      label: const Text('Copy a prompt to ask an AI'),
    );
  }
}
