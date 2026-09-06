import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';

/// The small vocabulary every help page is built from.
///
/// The examples are live widgets rather than screenshots. A screenshot is out
/// of date the day the screen changes, ignores the palette the reader picked,
/// and weighs something; the real component is always current by construction.

class HelpProse extends StatelessWidget {
  const HelpProse(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: Text(
      text,
      style: SpendWiseType.body.copyWith(fontSize: 14, height: 1.5),
    ),
  );
}

class HelpHeading extends StatelessWidget {
  const HelpHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 26, height: 2, color: SpendWiseColors.edge),
        const SizedBox(height: 13),
        Text(text, style: SpendWiseType.title.copyWith(fontSize: 20)),
      ],
    ),
  );
}

/// A thing to do, in order. Numbered because the order is real.
class HelpStep extends StatelessWidget {
  const HelpStep({
    super.key,
    required this.index,
    required this.title,
    required this.detail,
  });

  final int index;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 26,
          child: Text(
            '$index',
            style: SpendWiseType.metaTight.copyWith(
              color: SpendWiseColors.fg,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: SpendWiseType.row),
              const SizedBox(height: 3),
              Text(detail, style: SpendWiseType.body.copyWith(fontSize: 13)),
            ],
          ),
        ),
      ],
    ),
  );
}

/// An aside: the thing people get wrong, or the reason behind a rule.
class HelpNote extends StatelessWidget {
  const HelpNote(this.text, {super.key, this.tone});

  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.only(left: 13),
    decoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: tone ?? SpendWiseColors.edge, width: 2),
      ),
    ),
    child: Text(
      text,
      style: SpendWiseType.body.copyWith(fontSize: 13, height: 1.5),
    ),
  );
}

/// A live piece of the app, captioned. The caption goes underneath, the way a
/// figure is captioned in print, so the eye meets the thing before the words.
class HelpExample extends StatelessWidget {
  const HelpExample({
    super.key,
    required this.child,
    this.caption,
    this.framed = true,
  });

  final Widget child;
  final String? caption;
  final bool framed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (framed)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              border: Border.all(color: SpendWiseColors.line),
            ),
            child: child,
          )
        else
          child,
        if (caption case final text?) ...[
          const SizedBox(height: 8),
          Text(
            text,
            style: SpendWiseType.body.copyWith(fontSize: 12, height: 1.45),
          ),
        ],
      ],
    ),
  );
}

/// Two things side by side, where the difference is the lesson.
class HelpContrast extends StatelessWidget {
  const HelpContrast({
    super.key,
    required this.leftLabel,
    required this.left,
    required this.rightLabel,
    required this.right,
  });

  final String leftLabel;
  final String left;
  final String rightLabel;
  final String right;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _Side(label: leftLabel, text: left, good: false),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Side(label: rightLabel, text: right, good: true),
        ),
      ],
    ),
  );
}

class _Side extends StatelessWidget {
  const _Side({required this.label, required this.text, required this.good});

  final String label;
  final String text;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final tone = good ? SpendWiseColors.keep : SpendWiseColors.spend;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(label, color: tone),
        const SizedBox(height: 7),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
          decoration: BoxDecoration(
            border: Border.all(color: SpendWiseColors.line),
          ),
          child: Text(
            text,
            style: SpendWiseType.body.copyWith(fontSize: 12.5, height: 1.45),
          ),
        ),
      ],
    );
  }
}

/// Points at where in the app something lives, so the reader can go and do it
/// rather than only understand it.
class HelpWhere extends StatelessWidget {
  const HelpWhere(this.path, {super.key, this.onTap});

  final String path;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          border: Border.all(color: SpendWiseColors.edge),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.north_east_rounded,
              size: 14,
              color: SpendWiseColors.dim,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                path,
                style: SpendWiseType.row.copyWith(fontSize: 13.5),
              ),
            ),
            if (onTap != null)
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: SpendWiseColors.dim,
              ),
          ],
        ),
      ),
    ),
  );
}
