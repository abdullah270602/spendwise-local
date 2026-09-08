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

  /// The most of the screen the pinned preview may claim.
  ///
  /// Pinning something means it cannot be scrolled away, which also means it
  /// cannot be allowed to grow without limit: at twice the default text size
  /// the preview wanted more height than a phone has and simply took it, and
  /// the choices it exists to explain were pushed off the bottom of a Column
  /// that had nowhere to put them. Half is the split that keeps both halves
  /// usable.
  static const _previewShareOfScreen = 0.5;

  static const _previewPadding = EdgeInsets.fromLTRB(
    SpendWiseTheme.gutter,
    4,
    SpendWiseTheme.gutter,
    18,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          Container(
            width: double.infinity,
            padding: _previewPadding,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: SpendWiseColors.line)),
            ),
            child: _PinnedPreview(
              maxHeight:
                  constraints.maxHeight * _previewShareOfScreen -
                  _previewPadding.vertical,
              child: preview,
            ),
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
    ),
  );
}

/// The preview, held to a ceiling, and given a scroll view only once it has
/// actually hit one.
///
/// The scroll view is withheld rather than always present because a second
/// scrollable changes what "scroll this screen" means -- to a test harness,
/// and to anyone driving the phone by switch or by voice, both of which have
/// to be told which one they meant. At ordinary text sizes there is nothing
/// to scroll and so nothing should be scrollable.
class _PinnedPreview extends StatefulWidget {
  const _PinnedPreview({required this.child, required this.maxHeight});

  final Widget child;
  final double maxHeight;

  @override
  State<_PinnedPreview> createState() => _PinnedPreviewState();
}

class _PinnedPreviewState extends State<_PinnedPreview> {
  final GlobalKey _content = GlobalKey();
  bool _tooTall = false;

  /// Measured after the frame rather than predicted from the text scale.
  /// What a preview costs depends on which chooser it belongs to and on how
  /// many of its lines wrapped, and neither of those is knowable in advance.
  void _remeasure(Duration _) {
    if (!mounted) return;
    final box = _content.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final tooTall = box.size.height > widget.maxHeight + 0.5;
    if (tooTall != _tooTall) setState(() => _tooTall = tooTall);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback(_remeasure);
    final content = KeyedSubtree(key: _content, child: widget.child);
    if (_tooTall) {
      return SizedBox(
        height: widget.maxHeight,
        child: SingleChildScrollView(child: content),
      );
    }
    // Laid out at whatever height it asks for and then clipped to the
    // ceiling, so the one frame before a too-tall preview is measured cuts it
    // short instead of reporting an overflow. Under the ceiling this is the
    // preview at exactly its own height, which is what it always was.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: ConstraintsTransformBox(
        constraintsTransform: ConstraintsTransformBox.maxHeightUnconstrained,
        alignment: Alignment.topCenter,
        clipBehavior: Clip.hardEdge,
        child: content,
      ),
    );
  }
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
    // AnimatedContainer does not consult the platform's reduced-motion flag
    // by itself -- honouring it is opt-in, per widget -- so the border that
    // thickens and takes the accent went on thickening for someone who had
    // asked the whole system to stop moving. The choice still lands and still
    // looks selected; it simply arrives rather than travels.
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 140);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: duration,
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
