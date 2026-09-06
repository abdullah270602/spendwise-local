import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import 'dashboard_screen.dart';
import 'home_savings.dart';

/// Home, at Home's size, drawn by Home's own widgets.
///
/// Not an illustration of a setting -- the setting itself, rendered by the
/// same code the dashboard uses and fed by the same [homeFigures]. A preview
/// assembled separately from the thing it previews will eventually disagree
/// with it, and a settings screen that lies about what it is about to do is
/// worse than one that shows nothing at all.
class HomePreview extends StatelessWidget {
  const HomePreview({
    super.key,
    required this.figures,
    required this.style,
    required this.extra,
    this.label,
  });

  final HomeFigures figures;
  final HomeSavingsStyle style;
  final HomeSavingsExtra extra;

  /// What window this is a picture of. Falls back to the neutral framing when
  /// the window is not the subject of the screen.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final kept = figures.kept;
    final saved = figures.saved;
    // "Only what I can spend" reduces the ribbon it is dividing rather than
    // adding a branch to it: choosing not to see savings means not seeing them.
    final asideFromShape = style == HomeSavingsStyle.available
        ? saved.clamp(0, kept < 0 ? 0 : kept)
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(
          label ?? 'On Home',
          trailing: Text(
            '${formatMinor(figures.received, cents: false)} in',
            style: SpendWiseType.eyebrow,
          ),
        ),
        const SizedBox(height: 10),
        FlowShape(
          height: 132,
          animate: false,
          receivedMinor: figures.received,
          keptMinor: kept - asideFromShape,
          spentMinor: figures.spent,
          savedMinor: saved,
          saved: switch (style) {
            HomeSavingsStyle.siblings => SavedTreatment.branch,
            HomeSavingsStyle.divided => SavedTreatment.inset,
            HomeSavingsStyle.seam => SavedTreatment.seam,
            _ => SavedTreatment.none,
          },
        ),
        const SizedBox(height: 14),
        MonthLegend(
          received: figures.received,
          kept: kept,
          spent: figures.spent,
          savedMinor: saved,
          setsSavingAside: style.setsSavingAside,
          namesTheSaving: style.namesTheSaving,
        ),
        if (extra != HomeSavingsExtra.none) ...[
          const SizedBox(height: 14),
          _Underneath(extra: extra, figures: figures),
        ],
      ],
    );
  }
}

/// The optional line beneath the shape.
///
/// Kept below a hairline and outside the legend, because it reports something
/// the figures above do not: one of them is a balance, and a balance folded
/// in among flow figures quietly changes what all of them mean.
class _Underneath extends StatelessWidget {
  const _Underneath({required this.extra, required this.figures});

  final HomeSavingsExtra extra;
  final HomeFigures figures;

  @override
  Widget build(BuildContext context) {
    final saved = figures.saved;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 11),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SpendWiseColors.line)),
      ),
      child: switch (extra) {
        HomeSavingsExtra.balance => Eyebrow(
          'Savings',
          trailing: Text(
            formatMinor(figures.held, cents: false),
            style: SpendWiseType.rowStrong.copyWith(fontSize: 14),
          ),
        ),
        HomeSavingsExtra.moved => Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: formatMinor(saved.abs(), cents: false),
                style: SpendWiseType.rowStrong.copyWith(fontSize: 15),
              ),
              TextSpan(
                text: saved < 0
                    ? ' taken back out of savings.'
                    : ' put away this period.',
                style: SpendWiseType.body.copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
        HomeSavingsExtra.none => const SizedBox.shrink(),
      },
    );
  }
}
