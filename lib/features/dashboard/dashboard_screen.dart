import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../main.dart';
import '../../widgets/shape_kit.dart';
import '../settings/settings_screen.dart';
import '../tour/spotlight.dart';
import '../shell/spendwise_view_model.dart';
import 'home_categories.dart';
import 'home_savings.dart';

/// Home is one idea: of everything that arrived this month, this much is still
/// yours and this much is gone -- drawn to true proportion, then zoomed into
/// the part that left. No cards, no metric grid, no trend chart.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.viewModel,
    required this.onSeeLedger,
    required this.onOpenAccounts,
  });

  final SpendWiseViewModel viewModel;
  final VoidCallback onSeeLedger;
  final VoidCallback onOpenAccounts;

  @override
  Widget build(BuildContext context) {
    final data = viewModel.dashboard;
    final now = DateTime.now();
    final period = viewModel.uiHomePeriod;
    final month = period.label(now);

    // Every figure on Home comes from one place, and the settings previews
    // read the same one. Three separate assemblies of the same sum was three
    // chances for the preview to disagree with the screen it previews.
    final figures = homeFigures(viewModel, now: now);
    final windowFrom = figures.from;
    final windowTo = figures.to;
    final received = figures.received;
    final spent = figures.spent;
    final kept = figures.kept;
    final savedMinor = figures.saved;
    final anything = received != 0 || spent != 0;
    // A share of nothing is not a share. Before any income lands in the
    // window the ribbon would split |kept| against |spent| and draw a
    // confident 50/50 that means nothing at all, with "0%" beside it.
    final hasShare = received > 0;

    final categoryStyle = HomeCategories.fromId(
      viewModel.uiViewPreference('home_categories'),
    );
    // With no breakdown beneath it the ribbon is the whole of Home, so it
    // takes a share of the screen rather than a fixed number of pixels: a
    // figure that fills a tall phone and still fits a short one. Bounded at
    // both ends -- below 200 the curve stops reading as a shape, and above
    // 380 it pushes the tray scan past the fold, which is the opposite of
    // where that control belongs.
    final usableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewPaddingOf(context).vertical -
        96;
    final ribbonHeight = categoryStyle == HomeCategories.off
        ? (usableHeight * 0.36).clamp(190.0, 300.0)
        : 168.0;
    // One fold, read by both the bar and the rows, so the picture and the
    // list can never disagree about what is on screen.
    final categories = categoriesForHome(data.categorySpending, categoryStyle);
    final categoryTotal = categories.fold<int>(
      0,
      (sum, item) => sum + item.amount.minorUnits,
    );
    final savingsStyle = HomeSavingsStyle.fromId(
      viewModel.uiViewPreference('home_savings'),
    );
    // The line beneath the shape is its own choice now. It changes no figure
    // above it, so it was the wrong thing to have been picked *instead of*
    // the five that do.
    final savingsExtra = HomeSavingsExtra.resolve(
      viewModel.uiViewPreference('home_savings_extra'),
      viewModel.uiViewPreference('home_savings'),
      legacyOn: viewModel.uiShowSavingsOnHome,
    );
    final ownMoves = viewModel.transactions.where((item) {
      final local = item.occurredAt.toLocal();
      return item.kind == TransactionKind.transfer &&
          !local.isBefore(windowFrom) &&
          local.isBefore(windowTo);
    }).toList();

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SpendWiseTheme.gutter,
                14,
                SpendWiseTheme.gutter - 8,
                0,
              ),
              child: Row(
                children: [
                  // The month alone. "What happened to it" was a caption on a
                  // picture that already says so.
                  Expanded(child: Eyebrow(month)),
                  IconButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => SettingsScreen(viewModel: viewModel),
                      ),
                    ),
                    tooltip: 'Settings and privacy',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.tune_rounded,
                      size: 19,
                      color: SpendWiseColors.dim,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (viewModel.uiViewPreference('tour_seen') != 'true' &&
              viewModel.accounts.isNotEmpty)
            SliverToBoxAdapter(child: _TourOffer(viewModel: viewModel)),
          if (!anything && savingsExtra == HomeSavingsExtra.balance)
            SliverToBoxAdapter(
              child: _SavingsStrip(
                accounts: viewModel.accounts,
                onTap: onOpenAccounts,
              ),
            ),
          if (!anything)
            SliverToBoxAdapter(
              child: RestState(
                headline: 'Nothing has moved in $month yet.',
                detail: viewModel.notificationAccessGranted
                    ? 'The moment a bank alert arrives, this becomes the shape '
                          'of your month.'
                    : 'Turn on notification access and SpendWise will start '
                          'reading your bank alerts.',
                action: viewModel.notificationAccessGranted
                    ? null
                    : OutlinedButton(
                        onPressed: viewModel.requestNotificationAccess,
                        child: const Text('Turn on notification access'),
                      ),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  SpendWiseTheme.gutter,
                  8,
                  SpendWiseTheme.gutter,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasShare
                          ? 'RECEIVED ${formatMinor(received)}'
                          : 'NOTHING RECEIVED YET',
                      style: SpendWiseType.metaTight,
                    ),
                    const SizedBox(height: 6),
                    if (hasShare) ...[
                      Semantics(
                        label:
                            'Of ${formatMinor(received)} received, '
                            '${formatMinor(kept)} is still yours and '
                            '${formatMinor(spent)} was spent.',
                        // Home's own State is never recreated when the tabs
                        // switch away and back, so nothing here would replay
                        // its draw-in on return without this. A fresh key
                        // rebuilds the ribbon from a fresh State each time the
                        // shell sends the user back to this tab.
                        child: ValueListenableBuilder<int>(
                          valueListenable: homeReturnRevision,
                          builder: (context, revision, _) => FlowShape(
                            key: ValueKey(revision),
                            height: ribbonHeight,
                            receivedMinor: received,
                            // Taking saving out of the headline takes it out
                            // of the ribbon too: the shape then divides what
                            // is available against what went, and never shows
                            // a slice the figures do not mention.
                            keptMinor:
                                savingsStyle == HomeSavingsStyle.available
                                ? kept -
                                      savedMinor.clamp(0, kept < 0 ? 0 : kept)
                                : kept,
                            spentMinor: spent,
                            savedMinor: savedMinor,
                            saved: switch (savingsStyle) {
                              HomeSavingsStyle.siblings =>
                                SavedTreatment.branch,
                              HomeSavingsStyle.divided => SavedTreatment.inset,
                              HomeSavingsStyle.seam => SavedTreatment.seam,
                              _ => SavedTreatment.none,
                            },
                            // The wobble is a Home-only reply to a tap; the
                            // settings previews already replay their draw-in
                            // on every choice and do not opt in.
                            wobble: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      MonthLegend(
                        received: received,
                        kept: kept,
                        spent: spent,
                        savedMinor: savedMinor,
                        setsSavingAside: savingsStyle.setsSavingAside,
                        namesTheSaving: savingsStyle.namesTheSaving,
                        large: categoryStyle == HomeCategories.off,
                      ),
                    ] else
                      _SpentOnly(spent: spent, period: month),
                  ],
                ),
              ),
            ),
            if (categories.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SpendWiseTheme.gutter,
                    26,
                    SpendWiseTheme.gutter,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // No heading: the bar and the list under it are
                      // self-evidently the breakdown of what left.
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        height: 1,
                        color: SpendWiseColors.line,
                      ),
                      SegmentBar(
                        weights: [
                          for (final item in categories)
                            categoryTotal == 0
                                ? 1
                                : item.amount.minorUnits / categoryTotal,
                        ],
                        colors: [
                          for (var i = 0; i < categories.length; i++)
                            categoryColor(categories[i], i),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: SpendWiseTheme.gutter,
              ),
              sliver: SliverList.builder(
                itemCount: categories.length,
                itemBuilder: (context, index) => CategoryRow(
                  item: categories[index],
                  color: categoryColor(categories[index], index),
                  onTap: onSeeLedger,
                ),
              ),
            ),
            if (savingsExtra == HomeSavingsExtra.balance)
              SliverToBoxAdapter(
                child: _SavingsStrip(
                  accounts: viewModel.accounts,
                  onTap: onOpenAccounts,
                ),
              ),
            // Whatever is underneath is asked for underneath. "Nothing" means
            // nothing, including for the treatments that draw the saved slice
            // in the shape -- if you want the figure as well, ask for it.
            if (savingsExtra == HomeSavingsExtra.moved)
              SliverToBoxAdapter(
                child: _PutAwayNote(
                  savedMinor: savedMinor,
                  onTap: onOpenAccounts,
                ),
              ),
            SliverToBoxAdapter(
              child: _AsideNotes(
                viewModel: viewModel,
                moves: ownMoves,
                onTap: onOpenAccounts,
              ),
            ),
          ],
          // The tray scan falls to the bottom of the screen when there is room
          // and simply follows the content when there is not. It is the one
          // control on Home a person reaches for repeatedly, and it used to
          // sit wherever the content happened to end -- high on a quiet month,
          // far down a busy one, never twice in the same place.
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: 96 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [if (anything) _TrayScan(viewModel: viewModel)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _percent(int part, int whole) {
    if (whole <= 0) return '0%';
    final value = (part / whole) * 100;
    return '${value < 10 ? value.toStringAsFixed(1) : value.round()}%';
  }
}

/// The figures under the month's shape.
///
/// Public so the Settings preview can draw the real thing rather than an
/// imitation of it -- a preview that can drift from what it previews is worse
/// than none.
class MonthLegend extends StatelessWidget {
  const MonthLegend({
    super.key,
    required this.received,
    required this.kept,
    required this.spent,
    this.savedMinor = 0,
    this.setsSavingAside = false,
    this.namesTheSaving = true,
    this.large = false,
  });

  final int received;
  final int kept;
  final int spent;
  final int savedMinor;

  /// Whether saving is counted out of the headline figure.
  ///
  /// It is money you still own either way, so when it is counted out the
  /// figure stops being "still yours" and becomes "available" -- the label has
  /// to move with the arithmetic or one of them is lying.
  final bool setsSavingAside;

  /// Whether the amount set aside is named. Taking saving out of the figure
  /// without itemising it is a deliberate choice -- Home then answers exactly
  /// one question, which is what is left to spend.
  final bool namesTheSaving;

  /// Drawn larger when nothing follows it on Home. Scale here answers the
  /// space that is actually free, rather than decorating a fixed layout.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final aside = setsSavingAside && savedMinor > 0 ? savedMinor : 0;
    final headline = kept - aside;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _LegendEntry(
            large: large,
            label: headline < 0
                ? 'Overspent'
                : aside > 0
                ? 'Available'
                : 'Still yours',
            minor: headline,
            note: received > 0
                ? '${DashboardScreen._percent(headline.abs(), received)} of what came in'
                : 'nothing came in this month',
            color: headline < 0 ? SpendWiseColors.spend : SpendWiseColors.fg,
          ),
        ),
        if (aside > 0 && namesTheSaving)
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: _LegendEntry(
                large: large,
                label: 'Saved',
                minor: aside,
                note: DashboardScreen._percent(aside, received),
                color: SpendWiseColors.mine,
              ),
            ),
          ),
        _LegendEntry(
          large: large,
          label: 'Gone',
          minor: spent,
          note: DashboardScreen._percent(spent, received),
          color: SpendWiseColors.spend,
          alignRight: true,
        ),
      ],
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({
    required this.label,
    required this.minor,
    required this.note,
    required this.color,
    this.alignRight = false,
    this.large = false,
  });

  final String label;
  final int minor;
  final String note;
  final Color color;
  final bool alignRight;
  final bool large;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: alignRight
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      Eyebrow(label),
      const SizedBox(height: 4),
      AnimatedMinor(
        minor,
        cents: false,
        style: SpendWiseType.amount.copyWith(
          color: color,
          fontSize: large ? 30 : null,
        ),
      ),
      const SizedBox(height: 2),
      Text(note, style: SpendWiseType.body.copyWith(fontSize: 12.5)),
    ],
  );
}

/// The tone a category is drawn in.
///
/// The folded remainder is deliberately not given the next colour in the ramp:
/// it is not a sixth category, it is the absence of a list of them, and
/// colouring it like one invites the reader to look for its name in the list.
Color categoryColor(CategorySpendViewData item, int index) =>
    isRemainder(item) ? SpendWiseColors.dim : SpendWiseColors.category(index);

/// Public so the settings preview draws the real row rather than an imitation.
class CategoryRow extends StatelessWidget {
  const CategoryRow({
    super.key,
    required this.item,
    required this.color,
    required this.onTap,
  });

  final CategorySpendViewData item;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(width: 9, height: 9, color: color),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              item.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SpendWiseType.row,
            ),
          ),
          Text(
            formatAmount(item.amount, cents: false),
            style: SpendWiseType.rowStrong,
          ),
        ],
      ),
    ),
  );
}

/// What was put away over the period Home covers.
///
/// A figure, not a balance: it is the movement the shape is drawing, said in
/// words so the drawing is checkable rather than decorative. Nothing is shown
/// when nothing moved -- a line reading "0 put away" is noise, and a negative
/// one is a different sentence entirely.
class _PutAwayNote extends StatelessWidget {
  const _PutAwayNote({required this.savedMinor, required this.onTap});

  final int savedMinor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (savedMinor == 0) return const SizedBox.shrink();
    final out = savedMinor < 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SpendWiseTheme.gutter,
        18,
        SpendWiseTheme.gutter,
        0,
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(top: 13),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: SpendWiseColors.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 5, right: 11),
                color: out ? SpendWiseColors.spend : SpendWiseColors.mine,
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: formatMinor(savedMinor.abs(), cents: false),
                        style: SpendWiseType.rowStrong.copyWith(fontSize: 15),
                      ),
                      TextSpan(
                        text: out
                            ? ' taken back out of savings.'
                            : ' put away this period.',
                        style: SpendWiseType.body.copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Savings are deliberately absent from the month's shape -- money set aside
/// is neither kept nor spent this month. When the user asks to see it on Home,
/// it appears as its own band beneath the shape rather than being folded into
/// figures that would then mean something different.
class _SavingsStrip extends StatelessWidget {
  const _SavingsStrip({required this.accounts, required this.onTap});

  final List<AccountViewData> accounts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final savings = accounts.where((a) => !a.isIncluded).toList();
    if (savings.isEmpty) return const SizedBox.shrink();
    final total = savings.fold<int>(
      0,
      (sum, account) => sum + account.balance.minorUnits,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SpendWiseTheme.gutter,
        22,
        SpendWiseTheme.gutter,
        0,
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(top: 13),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: SpendWiseColors.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow(
                'Savings',
                trailing: Text(
                  formatMinor(total, cents: false),
                  style: SpendWiseType.rowStrong.copyWith(fontSize: 14),
                ),
              ),
              const SizedBox(height: 10),
              for (final account in savings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 15,
                        color: SpendWiseColors.keep,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          account.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SpendWiseType.row.copyWith(fontSize: 13.5),
                        ),
                      ),
                      Text(
                        formatMinor(account.balance.minorUnits, cents: false),
                        style: SpendWiseType.rowStrong.copyWith(fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                'Not counted as kept or spent this month.',
                style: SpendWiseType.body.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lending is the other reason the spend figure is smaller than a naive sum
/// of outgoing alerts, so it gets the same one-line treatment.
/// Money that moved without being spending.
///
/// Lending, being owed, and shifting money between your own accounts are three
/// statements of the same kind, so they sit in one block on one grid rather
/// than in separate strips with a rule each. They used to be two widgets with
/// two markers of different sizes, each nudged into place by hand -- which is
/// why the lines did not start at the same x and did not share a baseline.
class _AsideNotes extends StatelessWidget {
  const _AsideNotes({
    required this.viewModel,
    required this.moves,
    required this.onTap,
  });

  final SpendWiseViewModel viewModel;
  final List<TransactionViewData> moves;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final open = viewModel.uiDebts.where((item) => !item.isSettled).toList();
    final lentOut = open
        .where((item) => item.kind == DebtKind.lent)
        .fold<int>(0, (sum, item) => sum + item.outstanding.minorUnits);
    final owed = open
        .where((item) => item.kind == DebtKind.borrowed)
        .fold<int>(0, (sum, item) => sum + item.outstanding.minorUnits);
    final held = open
        .where((item) => item.isHeld)
        .fold<int>(0, (sum, item) => sum + item.outstanding.minorUnits);
    final moved = moves.fold<int>(
      0,
      (sum, item) => sum + item.amount.minorUnits.abs(),
    );

    final lines = <Widget>[
      if (lentOut > 0)
        _AsideLine(
          amount: lentOut,
          tail: 'out on loan',
          tone: SpendWiseColors.keep,
        ),
      if (owed > 0)
        _AsideLine(amount: owed, tail: 'you owe', tone: SpendWiseColors.spend),
      if (held > 0)
        _AsideLine(
          amount: held,
          tail: 'held for someone else',
          tone: SpendWiseColors.dim,
        ),
      if (moved > 0)
        _AsideLine(
          amount: moved,
          tail: 'moved between your own accounts',
          tone: SpendWiseColors.mine,
        ),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SpendWiseTheme.gutter,
        20,
        SpendWiseTheme.gutter,
        0,
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(top: 13),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: SpendWiseColors.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < lines.length; i++) ...[
                if (i > 0) const SizedBox(height: 9),
                lines[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of that block.
///
/// The marker sits in a fixed column the width of the gutter it shares with
/// every other line, and is centred against the first line of text by a box
/// of the text's own height -- not by a hand-tuned top margin, which is what
/// let two of these drift apart in the first place.
class _AsideLine extends StatelessWidget {
  const _AsideLine({
    required this.amount,
    required this.tail,
    required this.tone,
  });

  final int amount;
  final String tail;
  final Color tone;

  static const _markerColumn = 6.0;
  static const _gutter = 11.0;
  static const _lineHeight = 20.0;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: _markerColumn,
        height: _lineHeight,
        child: Center(
          child: Container(
            width: _markerColumn,
            height: _markerColumn,
            color: tone,
          ),
        ),
      ),
      const SizedBox(width: _gutter),
      Expanded(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${formatMinor(amount, cents: false)} ',
                style: SpendWiseType.row.copyWith(
                  fontWeight: FontWeight.w600,
                  color: tone,
                  height: _lineHeight / 15,
                ),
              ),
              TextSpan(
                text: tail,
                style: SpendWiseType.body.copyWith(
                  fontSize: 13,
                  height: _lineHeight / 13,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// Deliberately the quietest control on the screen. It exists because Android
/// can drop a notification before the listener wakes, not because anyone should
/// be pressing it every day.
class _TrayScan extends StatefulWidget {
  const _TrayScan({required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<_TrayScan> createState() => _TrayScanState();
}

class _TrayScanState extends State<_TrayScan> {
  bool running = false;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SpendWiseTheme.gutter,
      28,
      SpendWiseTheme.gutter,
      0,
    ),
    child: Align(
      // Centred, because at the bottom of the screen it is a destination
      // rather than a footnote to the line above it.
      alignment: Alignment.bottomCenter,
      // A hairline box, so it reads as something you can press without
      // becoming another thing competing for attention on the screen.
      child: InkWell(
        onTap: running ? null : _scan,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            border: Border.all(color: SpendWiseColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                running ? Icons.hourglass_empty_rounded : Icons.refresh_rounded,
                size: 13,
                color: SpendWiseColors.dim,
              ),
              const SizedBox(width: 7),
              // The label is wider than a 360dp phone once the border and
              // padding are counted, so it yields rather than running off.
              Flexible(
                child: Text(
                  running
                      ? 'SCANNING TRAY…'
                      : 'MISSING SOMETHING? SCAN THE TRAY',
                  style: SpendWiseType.metaTight,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _scan() async {
    setState(() => running = true);
    try {
      final result = await widget.viewModel.uiScanNotificationTray();
      if (!mounted) return;
      final message = switch (result.status) {
        NotificationTrayScanViewStatus.accessRequired =>
          'Notification access is off, so the tray cannot be read.',
        NotificationTrayScanViewStatus.listenerUnavailable =>
          'The capture service is not running yet. Try again in a moment.',
        NotificationTrayScanViewStatus.completed when result.queuedCount == 0 =>
          'Nothing new in the tray. Everything there is already recorded.',
        NotificationTrayScanViewStatus.completed =>
          'Picked up ${result.queuedCount} '
              '${result.queuedCount == 1 ? 'alert' : 'alerts'} from the tray.',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read the tray: $error')),
      );
    } finally {
      if (mounted) setState(() => running = false);
    }
  }
}

/// What Home says before any money has arrived in the window. It states the
/// one true thing -- this much has gone out -- instead of drawing a
/// proportion of nothing.
class _SpentOnly extends StatelessWidget {
  const _SpentOnly({required this.spent, required this.period});

  final int spent;
  final String period;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 6),
      Text(
        formatMinor(spent, cents: false),
        style: SpendWiseType.figure.copyWith(color: SpendWiseColors.spend),
      ),
      const SizedBox(height: 6),
      Text(
        'has gone out in $period, against nothing received yet. '
        'The share appears once money arrives.',
        style: SpendWiseType.body.copyWith(fontSize: 13),
      ),
    ],
  );
}

/// A single line, once, and then never again.
///
/// The evidence on walkthroughs is that the ones people finish are the ones
/// they chose to start, so the tour needs somewhere to be offered -- but Home
/// earns its keep by having nothing on it, so this leaves for good the moment
/// it is taken or waved off.
class _TourOffer extends StatelessWidget {
  const _TourOffer({required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SpendWiseTheme.gutter,
      6,
      SpendWiseTheme.gutter,
      2,
    ),
    child: Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => walkthroughRequested.value++,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Text(
                'New here? Show me around',
                style: SpendWiseType.body.copyWith(
                  fontSize: 12.5,
                  color: SpendWiseColors.keep,
                ),
              ),
            ),
          ),
        ),
        InkWell(
          onTap: () => viewModel.uiSetViewPreference('tour_seen', 'true'),
          child: const Padding(
            padding: EdgeInsets.all(7),
            child: Icon(
              Icons.close_rounded,
              size: 14,
              color: SpendWiseColors.dim,
            ),
          ),
        ),
      ],
    ),
  );
}
