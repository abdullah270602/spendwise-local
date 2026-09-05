import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../shell/spendwise_view_model.dart';

/// Money as a current, not a list.
///
/// One spine runs down the middle of the screen: what came in branches left,
/// what went out branches right, and a move between the user's own accounts
/// spans both sides because it is genuinely two events. Direction reads from
/// *position* before any colour or sign is decoded, which is the whole point --
/// it is the one view where you cannot misread which way money went.
class RiverView extends StatelessWidget {
  const RiverView({
    super.key,
    required this.transactions,
    required this.onOpen,
  });

  final List<TransactionViewData> transactions;
  final ValueChanged<TransactionViewData> onOpen;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const SliverToBoxAdapter(
        child: RestState(
          headline: 'The river has not started yet.',
          detail: 'Once alerts reach your ledger, every one of them shows up '
              'here as a branch off the spine — in on the left, out on the '
              'right, all the way back through your history.',
        ),
      );
    }

    // Day markers are part of the current, not headers above it, so the spine
    // is never interrupted.
    final rows = <_RiverRow>[];
    DateTime? lastDay;
    for (final item in transactions) {
      final local = item.occurredAt.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      if (lastDay == null || day != lastDay) {
        rows.add(_RiverRow.day(day));
        lastDay = day;
      }
      rows.add(_RiverRow.event(item));
    }

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
                SpendWiseTheme.gutter,
                0,
                SpendWiseTheme.gutter,
                96 + MediaQuery.viewPaddingOf(context).bottom,
              ),
      sliver: SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          if (row.day case final day?) return _DayMarker(day: day);
          final item = row.transaction!;
          return _Branch(
            transaction: item,
            onTap: () => onOpen(item),
            first: index == 1,
            last: index == rows.length - 1,
          );
        },
      ),
    );
  }
}

/// The header that names the two banks of the river.
class RiverHeading extends StatelessWidget {
  const RiverHeading({super.key, required this.inTotal, required this.outTotal});

  final int inTotal;
  final int outTotal;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SpendWiseTheme.gutter,
      0,
      SpendWiseTheme.gutter,
      10,
    ),
    child: Container(
      padding: const EdgeInsets.only(bottom: 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SpendWiseColors.edge)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow('In', color: SpendWiseColors.keep),
                const SizedBox(height: 3),
                Text(
                  formatMinor(inTotal, cents: false),
                  style: SpendWiseType.rowStrong.copyWith(
                    fontSize: 15,
                    color: SpendWiseColors.keep,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Eyebrow('Out', color: SpendWiseColors.spend),
                const SizedBox(height: 3),
                Text(
                  formatMinor(outTotal, cents: false),
                  style: SpendWiseType.rowStrong.copyWith(
                    fontSize: 15,
                    color: SpendWiseColors.spend,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _RiverRow {
  _RiverRow.day(this.day) : transaction = null;
  _RiverRow.event(this.transaction) : day = null;

  final DateTime? day;
  final TransactionViewData? transaction;
}

/// The spine, with the date set into it.
class _DayMarker extends StatelessWidget {
  const _DayMarker({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 34,
    child: Row(
      children: [
        const Expanded(child: SizedBox()),
        SizedBox(
          width: _Branch.spine,
          child: Center(
            child: Container(
              color: SpendWiseColors.bg,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                DateFormat('dd MMM').format(day).toUpperCase(),
                textAlign: TextAlign.center,
                style: SpendWiseType.metaTight.copyWith(fontSize: 8.5),
              ),
            ),
          ),
        ),
        const Expanded(child: SizedBox()),
      ],
    ),
  );
}

/// One event branching off the spine. An own-account move draws on both sides,
/// because the money left one of your accounts and arrived in another.
class _Branch extends StatelessWidget {
  const _Branch({
    required this.transaction,
    required this.onTap,
    required this.first,
    required this.last,
  });

  static const spine = 74.0;

  final TransactionViewData transaction;
  final VoidCallback onTap;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final own = transaction.kind == TransactionKind.transfer;
    final incoming = transaction.kind == TransactionKind.income;
    // A transfer's subtitle is already "From → To"; a crossing should name
    // both banks rather than saying "here", which is exactly the word a map
    // is supposed to replace.
    final legs = own ? transaction.subtitle.split('→') : const <String>[];
    final fromName = legs.length == 2 ? legs.first.trim() : '';
    final toName = legs.length == 2 ? legs.last.trim() : '';
    final tone = own
        ? SpendWiseColors.mine
        : incoming
        ? SpendWiseColors.keep
        : SpendWiseColors.spend;

    return InkWell(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: incoming || own
                  ? _Side(
                      transaction: transaction,
                      tone: tone,
                      alignEnd: true,
                      title: own && fromName.isNotEmpty
                          ? fromName
                          : transaction.title,
                      label: own ? 'left' : null,
                    )
                  : const SizedBox(),
            ),
            SizedBox(
              width: spine,
              child: _Spine(tone: tone, first: first, last: last, wide: own),
            ),
            Expanded(
              child: !incoming || own
                  ? _Side(
                      transaction: transaction,
                      tone: tone,
                      alignEnd: false,
                      title: own && toName.isNotEmpty
                          ? toName
                          : transaction.title,
                      label: own ? 'arrived' : null,
                    )
                  : const SizedBox(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Spine extends StatelessWidget {
  const _Spine({
    required this.tone,
    required this.first,
    required this.last,
    required this.wide,
  });

  final Color tone;
  final bool first;
  final bool last;
  final bool wide;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _SpinePainter(tone: tone, first: first, last: last, wide: wide),
  );
}

class _SpinePainter extends CustomPainter {
  _SpinePainter({
    required this.tone,
    required this.first,
    required this.last,
    required this.wide,
  });

  final Color tone;
  final bool first;
  final bool last;
  final bool wide;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.width / 2;
    final midY = size.height / 2;

    canvas.drawLine(
      Offset(centre, first ? midY : 0),
      Offset(centre, last ? midY : size.height),
      Paint()
        ..color = SpendWiseColors.edge
        ..strokeWidth = 1.4,
    );

    // The branch: a short arm out to the side the money went.
    final arm = Paint()
      ..color = tone.withValues(alpha: .55)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    if (wide) {
      canvas.drawLine(Offset(0, midY), Offset(size.width, midY), arm);
    }

    canvas.drawCircle(
      Offset(centre, midY),
      3.4,
      Paint()..color = tone,
    );
  }

  @override
  bool shouldRepaint(_SpinePainter old) =>
      old.tone != tone ||
      old.first != first ||
      old.last != last ||
      old.wide != wide;
}

class _Side extends StatelessWidget {
  const _Side({
    required this.transaction,
    required this.tone,
    required this.alignEnd,
    this.title,
    this.label,
  });

  final TransactionViewData transaction;
  final Color tone;
  final bool alignEnd;

  /// Overrides the transaction's own name. A crossing between two of your
  /// accounts names the account on each side instead.
  final String? title;
  final String? label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      alignEnd ? 0 : 4,
      11,
      alignEnd ? 4 : 0,
      11,
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          title ?? transaction.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: SpendWiseType.row.copyWith(fontSize: 13.5),
        ),
        const SizedBox(height: 2),
        Text(
          (label ??
                  [
                    transaction.category,
                    if (transaction.accountName.isNotEmpty)
                      transaction.accountName,
                  ].join(' · '))
              .toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: SpendWiseType.metaTight.copyWith(fontSize: 8.5),
        ),
        const SizedBox(height: 3),
        Text(
          formatAmount(transaction.amount, cents: false),
          style: SpendWiseType.rowStrong.copyWith(fontSize: 14, color: tone),
        ),
      ],
    ),
  );
}
