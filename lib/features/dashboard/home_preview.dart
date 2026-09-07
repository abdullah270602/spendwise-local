import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../shell/spendwise_view_model.dart';
import 'dashboard_screen.dart';
import 'home_categories.dart';
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
          // A new key on every choice, so the ribbon draws itself in again
          // rather than blinking into its new arrangement. The choice and its
          // answer then feel like one gesture.
          key: ValueKey('${style.id}|${extra.id}'),
          height: 132,
          // Quicker than Home's own pour on purpose -- this replays on every
          // option tap, and a preview that took Home's full 1300ms to answer
          // each choice would feel sluggish rather than considered.
          duration: const Duration(milliseconds: 560),
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

/// The spending breakdown, at Home's size, drawn by Home's own widgets.
///
/// The bar is the part worth previewing: it is drawn to true proportion, so
/// it is where the difference between showing five categories and showing all
/// of them is actually visible.
class CategoryPreview extends StatelessWidget {
  const CategoryPreview({
    super.key,
    required this.spending,
    required this.style,
  });

  final List<CategorySpendViewData> spending;
  final HomeCategories style;

  /// A pinned preview cannot grow with the list, and a preview that silently
  /// stops after four rows would be making the same claim the fold exists to
  /// avoid. So it says how many it did not draw.
  static const _visibleRows = 4;

  @override
  Widget build(BuildContext context) {
    final items = categoriesForHome(spending, style);
    final total = items.fold<int>(0, (sum, i) => sum + i.amount.minorUnits);

    if (items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('On Home'),
          const SizedBox(height: 12),
          Text(
            style == HomeCategories.off
                ? 'Home ends after the figures above. Nothing else is drawn.'
                : 'Nothing has been spent in this period yet.',
            style: SpendWiseType.body.copyWith(fontSize: 13),
          ),
        ],
      );
    }

    final shown = items.take(_visibleRows).toList();
    final hidden = items.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(
          'On Home',
          trailing: Text(
            items.length == 1 ? '1 line' : '${items.length} lines',
            style: SpendWiseType.eyebrow,
          ),
        ),
        const SizedBox(height: 12),
        SegmentBar(
          weights: [
            for (final item in items)
              total == 0 ? 1 : item.amount.minorUnits / total,
          ],
          colors: [
            for (var i = 0; i < items.length; i++) categoryColor(items[i], i),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < shown.length; i++)
          CategoryRow(
            item: shown[i],
            color: categoryColor(shown[i], i),
            onTap: () {},
          ),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              hidden == 1 ? '+1 more line' : '+$hidden more lines',
              style: SpendWiseType.metaTight,
            ),
          ),
      ],
    );
  }
}
