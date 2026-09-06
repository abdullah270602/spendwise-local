import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'shape_kit.dart';

/// One preview, held still, and the choices that change it.
///
/// Every screen that changes how Home looks is built from this, so they are
/// not three screens that merely resemble each other -- they are one screen
/// with three subjects. The preview is pinned rather than scrolled: a choice
/// you cannot see the effect of while making it is a guess, and the previous
/// version put the preview at the top of a list, so reaching the options
/// scrolled the answer off the screen.
///
/// The words are deliberately few. A row says what the choice *is*; the
/// preview says what it looks like. Saying both in prose is how a settings
/// screen turns into an essay nobody reads.
class ChooserScreen extends StatelessWidget {
  const ChooserScreen({
    super.key,
    required this.title,
    required this.preview,
    required this.children,
  });

  final String title;

  /// Drawn from the real widgets and the real figures, never an illustration
  /// of them. A preview that can drift from what it previews is worse than no
  /// preview at all.
  final Widget preview;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            SpendWiseTheme.gutter,
            4,
            SpendWiseTheme.gutter,
            18,
          ),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: SpendWiseColors.line)),
          ),
          child: preview,
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              SpendWiseTheme.gutter,
              20,
              SpendWiseTheme.gutter,
              32 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            children: children,
          ),
        ),
      ],
    ),
  );
}

/// A titled run of choices that answer one question.
///
/// The grouping is the explanation. "In the figure" and "Underneath" do
/// genuinely different work -- one changes the number Home reports, the other
/// adds a line beneath it -- and a single undifferentiated list of options was
/// asking people to work that out from the wording of seven rows.
class ChoiceGroup extends StatelessWidget {
  const ChoiceGroup({
    super.key,
    required this.label,
    required this.children,
    this.caption,
    this.first = false,
  });

  final String label;

  /// At most one short line. If it needs two, the group is doing too much.
  final String? caption;
  final List<Widget> children;
  final bool first;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(height: first ? 0 : 26),
      Eyebrow(label),
      if (caption != null) ...[
        const SizedBox(height: 6),
        Text(
          caption!,
          style: SpendWiseType.body.copyWith(
            fontSize: 12.5,
            color: SpendWiseColors.dim,
          ),
        ),
      ],
      const SizedBox(height: 11),
      ...children,
    ],
  );
}

/// One choice.
///
/// A hairline that thickens and takes the accent when selected, and a filled
/// mark -- no cards, no shadows, no radius. The app draws money with straight
/// edges and a single hairline, and a settings screen that suddenly rounds and
/// floats reads as a different product.
class ChoiceRow extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.detail,
    this.leading,
    this.tone,
  });

  final String title;

  /// One short line, or none. The preview above is doing the explaining.
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  /// A swatch, for choices whose subject is colour.
  final Widget? leading;

  /// Overrides the selected colour where the choice itself has one.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final mark = tone ?? SpendWiseColors.keep;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(13, 13, 14, 13),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? mark : SpendWiseColors.edge,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 13),
              ] else ...[
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(right: 13),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? mark : SpendWiseColors.edge,
                      width: 1.5,
                    ),
                    color: selected ? mark : Colors.transparent,
                  ),
                ),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: SpendWiseType.rowStrong.copyWith(fontSize: 14),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail!,
                        style: SpendWiseType.body.copyWith(
                          fontSize: 12.5,
                          color: SpendWiseColors.dim,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
