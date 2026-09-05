import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';

/// One thing SpendWise read out of one alert.
@immutable
class AlertMark {
  const AlertMark({
    required this.text,
    required this.reads,
    required this.tone,
  });

  /// The exact run of characters in the alert body.
  final String text;

  /// What it became.
  final String reads;

  final Color tone;
}

/// A worked example: a notification on one side, the ledger row it becomes on
/// the other, and the parts of the text that produced it marked in place.
@immutable
class AlertExample {
  const AlertExample({
    required this.sourceLabel,
    required this.body,
    required this.marks,
    required this.name,
    required this.meta,
    required this.amount,
    required this.tone,
    this.ignored,
    this.title,
  });

  final String sourceLabel;
  final String? title;
  final String body;
  final List<AlertMark> marks;

  /// The row as it lands in the ledger.
  final String name;
  final String meta;
  final String amount;
  final Color tone;

  /// The trap in this particular shape of alert, if it has one. Naming what
  /// was deliberately not read teaches more than naming what was.
  final String? ignored;

  /// The everyday case: a card purchase, where the merchant is buried in the
  /// middle of the sentence and a second, larger figure sits right beside the
  /// one that matters.
  static AlertExample get purchase => AlertExample(
    sourceLabel: 'Bank alert',
    body:
        'Rs 2,450.00 debited from A/C ****4821 at VALLEY MART on 06-SEP. '
        'Avl Bal Rs 61,300.00',
    marks: [
      AlertMark(
        text: 'Rs 2,450.00',
        reads: 'the amount',
        tone: SpendWiseColors.spend,
      ),
      AlertMark(
        text: 'VALLEY MART',
        reads: 'who it went to',
        tone: SpendWiseColors.fg,
      ),
      AlertMark(
        text: '****4821',
        reads: 'which account',
        tone: SpendWiseColors.mine,
      ),
    ],
    ignored: 'Avl Bal Rs 61,300.00 is your balance, not what you spent.',
    name: 'Valley Mart',
    meta: 'Groceries · Everyday account',
    amount: '−2,450.00',
    tone: SpendWiseColors.spend,
  );

  /// Money arriving, which most apps get backwards at least once.
  static AlertExample get received => AlertExample(
    sourceLabel: 'Bank alert',
    body:
        'Rs 85,000.00 credited to your account ****4821 from ACME TRADING CO '
        'via IBFT. Ref 918273645.',
    marks: [
      AlertMark(
        text: 'Rs 85,000.00',
        reads: 'the amount',
        tone: SpendWiseColors.keep,
      ),
      AlertMark(
        text: 'credited',
        reads: 'money coming in',
        tone: SpendWiseColors.keep,
      ),
      AlertMark(
        text: 'ACME TRADING CO',
        reads: 'who sent it',
        tone: SpendWiseColors.fg,
      ),
    ],
    name: 'Acme Trading Co',
    meta: 'Income · Everyday account',
    amount: '+85,000.00',
    tone: SpendWiseColors.keep,
  );

  /// The one that is neither income nor spending: your own money, moved.
  static AlertExample get ownTransfer => AlertExample(
    sourceLabel: 'Bank alert',
    body:
        'Rs 20,000.00 transferred from A/C ****4821 to YOUR OWN NAME '
        'A/C ****9036. Ref 552310889.',
    marks: [
      AlertMark(
        text: 'YOUR OWN NAME',
        reads: 'a name you told us is yours',
        tone: SpendWiseColors.mine,
      ),
      AlertMark(
        text: '****9036',
        reads: 'an account you already have',
        tone: SpendWiseColors.mine,
      ),
    ],
    ignored:
        'Nothing was earned or spent here, so it changes no total. It only '
        'moves.',
    name: 'To Savings',
    meta: 'Between your accounts',
    amount: '20,000.00',
    tone: SpendWiseColors.mine,
  );
}

/// Draws the example. Static by default; the onboarding animates it in.
class AlertDemo extends StatelessWidget {
  const AlertDemo({
    super.key,
    required this.example,
    this.showResult = true,
    this.compact = false,
  });

  final AlertExample example;
  final bool showResult;

  /// Drops the aside about what was ignored. True in onboarding, where the
  /// budget is a couple of dozen words for the whole screen.
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _AlertCard(example: example, compact: compact),
      if (showResult) ...[
        const SizedBox(height: 14),
        const _Arrow(),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
          decoration: BoxDecoration(
            border: Border.all(color: SpendWiseColors.edge),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 10, bottom: 4),
                child: Eyebrow('In your ledger'),
              ),
              RegisterRow(
                name: example.name,
                meta: example.meta,
                amount: example.amount,
                amountColor: example.tone,
                ownTransfer: example.tone == SpendWiseColors.mine,
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ],
    ],
  );
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.example, this.compact = false});

  final AlertExample example;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    decoration: BoxDecoration(
      border: Border.all(color: SpendWiseColors.edge),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 5, height: 5, color: SpendWiseColors.dim),
            const SizedBox(width: 7),
            Text(example.sourceLabel.toUpperCase(), style: SpendWiseType.metaTight),
          ],
        ),
        const SizedBox(height: 9),
        Text.rich(
          TextSpan(children: _spans(example)),
          style: SpendWiseType.meta.copyWith(
            fontSize: 12,
            height: 1.6,
            color: SpendWiseColors.dim,
          ),
        ),
        const SizedBox(height: 13),
        for (final mark in example.marks)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 5),
                  width: 14,
                  height: 2,
                  color: mark.tone,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    mark.reads,
                    style: SpendWiseType.body.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        if (example.ignored case final note? when !compact) ...[
          const SizedBox(height: 7),
          Container(
            padding: const EdgeInsets.only(left: 11),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: SpendWiseColors.edge, width: 2),
              ),
            ),
            child: Text(
              note,
              style: SpendWiseType.body.copyWith(fontSize: 12),
            ),
          ),
        ],
      ],
    ),
  );

  /// Colours the exact runs of text that produced each reading, so the claim
  /// is checkable against the alert rather than merely asserted beside it.
  static List<InlineSpan> _spans(AlertExample example) {
    final body = example.body;
    final hits = <({int start, int end, AlertMark mark})>[];
    for (final mark in example.marks) {
      final at = body.indexOf(mark.text);
      if (at < 0) continue;
      final end = at + mark.text.length;
      // Skip a mark that would overlap one already placed: two underlines on
      // the same characters would just look like a rendering bug.
      if (hits.any((hit) => at < hit.end && hit.start < end)) continue;
      hits.add((start: at, end: end, mark: mark));
    }
    hits.sort((a, b) => a.start.compareTo(b.start));

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final hit in hits) {
      if (hit.start > cursor) {
        spans.add(TextSpan(text: body.substring(cursor, hit.start)));
      }
      spans.add(
        TextSpan(
          text: body.substring(hit.start, hit.end),
          style: TextStyle(
            color: hit.mark.tone,
            fontWeight: FontWeight.w500,
            decoration: TextDecoration.underline,
            decorationColor: hit.mark.tone,
            decorationThickness: 1.4,
          ),
        ),
      );
      cursor = hit.end;
    }
    if (cursor < body.length) {
      spans.add(TextSpan(text: body.substring(cursor)));
    }
    return spans;
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SizedBox(width: 14),
      Container(width: 1, height: 14, color: SpendWiseColors.edge),
      const SizedBox(width: 9),
      Text('becomes', style: SpendWiseType.metaTight),
    ],
  );
}
