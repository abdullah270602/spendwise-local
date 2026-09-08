import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/category_tones.dart';
import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../shell/spendwise_view_model.dart';
import 'spending_analytics.dart';

/// Where the money went, drawn as a fader bank instead of a bar-and-list.
///
/// This is the implementation of `local/design/final-mixing-desk.html`. The
/// one decision that design settled and this widget must honour exactly:
/// a channel's position and number come from [CategoryTones], which is keyed
/// to the app's stable, all-time category list -- never from this period's
/// spending rank. [categories] arrives sorted largest first (the same list
/// `SpendingAnalytics` hands every other reader of it), so channel 07 would
/// otherwise mean a different category every time the ranking shifted. This
/// widget re-sorts it once, by [CategoryTones.channelOf], before drawing
/// anything.
///
/// [selected] never changes what is measured -- the fader heights come from
/// [categories] alone, which the screen computes unfiltered on purpose, so a
/// filter tap never moves a single cap. It only changes which channels dim
/// and which row in the patch bay inverts.
class MixingDesk extends StatefulWidget {
  const MixingDesk({
    super.key,
    required this.categories,
    required this.tones,
    required this.selected,
    required this.onSelect,
    required this.currency,
  });

  final List<CategoryAnalytics> categories;
  final CategoryTones tones;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final String currency;

  @override
  State<MixingDesk> createState() => _MixingDeskState();
}

class _MixingDeskState extends State<MixingDesk>
    with SingleTickerProviderStateMixin {
  /// One-shot entrance cascade, kept alive for the widget's whole life. It is
  /// never rebuilt when [MixingDesk.selected] changes -- if it were, a filter
  /// tap would replay the entire entrance for no reason, and the dial this
  /// desk was designed alongside makes the same promise for the same reason.
  late final AnimationController _entry = AnimationController(
    duration: const Duration(milliseconds: 1300),
    vsync: this,
  );

  /// Guards the cascade so it starts exactly once. `didChangeDependencies`
  /// can run again later (a theme or locale change, say), and a second
  /// `forward()` from it would restart an entrance that already finished.
  bool _armed = false;

  /// Whether the AUX fold's own list of everything it swallowed is showing.
  bool _auxExpanded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_armed) return;
    _armed = true;
    // A raw AnimationController gets none of the help Flutter gives the
    // Animated* widgets, so reduced motion has to be honoured by hand here,
    // exactly as FlowShape and AnimatedMinor already do.
    if (MediaQuery.disableAnimationsOf(context)) {
      _entry.value = 1;
    } else {
      _entry.forward();
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  void _select(String name) =>
      widget.onSelect(widget.selected == name ? null : name);

  void _toggleAux() => setState(() => _auxExpanded = !_auxExpanded);

  @override
  Widget build(BuildContext context) {
    final total = widget.categories.fold<int>(
      0,
      (sum, item) => sum + item.amountMinor,
    );
    final header = Eyebrow(
      'Where your money went',
      trailing: Text(
        formatAmount(MoneyViewData(total, currency: widget.currency)),
        style: SpendWiseType.metaTight.copyWith(color: SpendWiseColors.fg),
      ),
    );

    // Floor rule: at exactly one active category, don't draw the desk at
    // all. A single fader has nothing to be compared against, which is the
    // one thing a fader bank exists to let a reader do.
    if (widget.categories.length == 1) {
      final only = widget.categories.single;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 12),
          _SoloModule(
            category: only,
            currency: widget.currency,
            color: widget.tones.of(only.category),
            entry: _entry,
          ),
        ],
      );
    }

    if (widget.categories.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 12),
          Text(
            'Categorised spending will appear here.',
            style: SpendWiseType.body.copyWith(fontSize: 13),
          ),
        ],
      );
    }

    final layout = _layout(widget.categories, widget.tones);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: SpendWiseColors.edge),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
            child: Column(
              children: [
                _ChannelStrip(
                  channels: layout.channels,
                  maxFraction: layout.maxFraction,
                  mini: layout.mini,
                  selected: widget.selected,
                  entry: _entry,
                  tones: widget.tones,
                  onSelectChannel: _select,
                  onToggleAux: _toggleAux,
                ),
                const SizedBox(height: 10),
                DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: SpendWiseColors.line),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _PatchBay(
                      channels: layout.channels,
                      selected: widget.selected,
                      tones: widget.tones,
                      auxExpanded: _auxExpanded,
                      onSelectChannel: _select,
                      onToggleAux: _toggleAux,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One channel's resolved facts: which category (if any), the stable number
/// it answers to, and its share of the period's spend. Built once per build
/// from [CategoryAnalytics] plus [CategoryTones], so the strip, the patch bay
/// and the hit-tester all draw from the same list rather than each deriving
/// their own and risking disagreement -- the same discipline `_FlowGeometry`
/// uses in `shape_kit.dart`.
@immutable
class _Channel {
  const _Channel({
    required this.category,
    required this.no,
    required this.fraction,
    required this.amountMinor,
    this.isAux = false,
    this.auxCount = 0,
    this.auxFolded = const [],
  });

  final String category;
  final int no;
  final double fraction;
  final int amountMinor;

  /// True for the one folded channel a 25+ category month grows past the
  /// fourteenth slot. It isn't a category, so it never carries a colour and
  /// never answers to [MixingDesk.onSelect] -- tapping it opens the fold.
  final bool isAux;
  final int auxCount;
  final List<_Channel> auxFolded;
}

class _DeskLayout {
  const _DeskLayout({
    required this.channels,
    required this.maxFraction,
    required this.mini,
  });

  final List<_Channel> channels;
  final double maxFraction;
  final bool mini;
}

/// The one AUX threshold: past fourteen active categories in a period, the
/// strip folds. Fourteen is also the source design's own hero count -- the
/// most that fits at 21px a channel before flex-shrink starts compressing
/// caps below a legible width.
const _foldAt = 14;

/// Below this many total slots (real channels plus one AUX, if it exists),
/// the strip reads as a small desk rather than a large one with most of its
/// channels torn out, and switches to the centred, fixed-width layout.
const _miniMax = 6;

_DeskLayout _layout(List<CategoryAnalytics> categories, CategoryTones tones) {
  final withNo = [
    for (final item in categories)
      _Channel(
        category: item.category,
        no: tones.channelOf(item.category),
        fraction: item.fraction,
        amountMinor: item.amountMinor,
      ),
  ];
  final maxFraction = withNo.fold<double>(
    0,
    (best, channel) => math.max(best, channel.fraction),
  );

  List<_Channel> real;
  _Channel? aux;
  if (withNo.length > _foldAt) {
    // Which categories earn a dedicated slot this period is unavoidably a
    // rank question, even though where they sit once they earn one isn't --
    // so the split is by amount, and only the display order that follows it
    // is put back into stable channel order.
    final byAmount = [...withNo]
      ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    real = byAmount.sublist(0, _foldAt - 1)
      ..sort((a, b) => a.no.compareTo(b.no));
    final folded = byAmount.sublist(_foldAt - 1)
      ..sort((a, b) => a.no.compareTo(b.no));
    final auxFraction = folded.fold<double>(
      0,
      (sum, channel) => sum + channel.fraction,
    );
    final auxAmount = folded.fold<int>(
      0,
      (sum, channel) => sum + channel.amountMinor,
    );
    aux = _Channel(
      category: '',
      no: 0,
      fraction: auxFraction,
      amountMinor: auxAmount,
      isAux: true,
      auxCount: folded.length,
      auxFolded: folded,
    );
  } else {
    real = [...withNo]..sort((a, b) => a.no.compareTo(b.no));
  }

  final channels = [...real, ?aux];
  return _DeskLayout(
    channels: channels,
    // A month where every category sits at 0% would otherwise divide by
    // zero; there is nothing honest to draw then anyway, so the floor
    // keeps the maths finite rather than describing that case specially.
    maxFraction: maxFraction <= 0 ? 1 : maxFraction,
    mini: channels.length <= _miniMax,
  );
}

/// The channel strip: a whole-height, whole-width row of faders, hit-tested
/// as one surface rather than as N separate 21px targets.
class _ChannelStrip extends StatelessWidget {
  const _ChannelStrip({
    required this.channels,
    required this.maxFraction,
    required this.mini,
    required this.selected,
    required this.entry,
    required this.tones,
    required this.onSelectChannel,
    required this.onToggleAux,
  });

  final List<_Channel> channels;
  final double maxFraction;
  final bool mini;
  final String? selected;
  final AnimationController entry;
  final CategoryTones tones;
  final ValueChanged<String> onSelectChannel;
  final VoidCallback onToggleAux;

  static const _trackHeight = 140.0;
  static const _minCap = 6.0;
  static const _headroom = 10.0;
  static const _range = _trackHeight - _minCap - _headroom;

  static const _miniChannelWidth = 26.0;
  static const _miniGap = 16.0;
  static const _cheek = 10.0;

  /// A channel's fully-risen height, in pixels. The additive floor is why
  /// even a category at a fraction of a percent still reads as a sliver
  /// rather than nothing -- and why it is a floor, not a proportional line
  /// through zero: the honest cost is that the bottom of the scale is
  /// compressed, which the printed percentage above the cap exists to make
  /// up for.
  double _levelFor(_Channel channel) {
    if (channel.fraction <= 0) return 0;
    return _minCap + (channel.fraction / maxFraction) * _range;
  }

  /// Resolves a tap's x-offset to the channel it landed nearest, using the
  /// exact geometry the row below was built with -- the same discipline
  /// `_buildFlowGeometry`/`branchAt` use in `shape_kit.dart`, just width
  /// division here instead of `Path.contains`, because there is no curve.
  int _hitIndex(double dx, double width) {
    final n = channels.length;
    if (!mini) {
      // Equal, contiguous slices spanning the whole strip -- there is no
      // dead zone between channels, so a tap that lands in what would be a
      // channel's visual margin still resolves to a real, adjacent channel.
      final slice = width / n;
      return (dx / slice).floor().clamp(0, n - 1);
    }
    // The mini layout is centred and fixed-width, not an equal division, so
    // the nearest channel is found by comparing distances to each channel's
    // known centre instead.
    final content = 2 * _cheek + n * _miniChannelWidth + (n - 1) * _miniGap;
    final left = math.max(0.0, (width - content) / 2) + _cheek;
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < n; i++) {
      final center =
          left + i * (_miniChannelWidth + _miniGap) + _miniChannelWidth / 2;
      final distance = (dx - center).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }

  void _handleTap(_Channel channel) {
    if (channel.isAux) {
      onToggleAux();
    } else {
      onSelectChannel(channel.category);
    }
  }

  /// A channel's current, animated height at the controller's present value.
  /// Built fresh per frame from an `Interval` rather than from N persistent
  /// `CurvedAnimation`s, so N channels never means N long-lived listeners --
  /// the maths is identical either way.
  double _currentLevel(int index, int n, double finalLevel) {
    if (finalLevel <= 0) return 0;
    final start = n <= 1 ? 0.0 : (index / (n - 1)) * (550 / 1300);
    final end = math.min(1.0, start + 750 / 1300);
    final progress = Interval(
      start,
      end,
      curve: Curves.easeOutQuint,
    ).transform(entry.value.clamp(0.0, 1.0));
    return finalLevel * progress;
  }

  @override
  Widget build(BuildContext context) {
    final n = channels.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          key: const Key('mixing-desk-strip'),
          behavior: HitTestBehavior.opaque,
          // The tap target for a screen-reader user never depends on this
          // gesture layer -- each channel below carries its own Semantics
          // node with its own `onTap`, which is what a screen reader actually
          // drives, so this detector stays out of the semantics tree rather
          // than describing the same action twice.
          excludeFromSemantics: true,
          onTapUp: (details) {
            if (n == 0) return;
            _handleTap(channels[_hitIndex(details.localPosition.dx, width)]);
          },
          child: AnimatedBuilder(
            animation: entry,
            builder: (context, _) => Row(
              mainAxisAlignment: mini
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (mini) const _Cheek(),
                for (var i = 0; i < n; i++)
                  mini
                      ? Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : _miniGap),
                          child: SizedBox(
                            width: _miniChannelWidth,
                            child: _ChannelColumn(
                              channel: channels[i],
                              selected: selected,
                              currentLevel: _currentLevel(
                                i,
                                n,
                                _levelFor(channels[i]),
                              ),
                              tones: tones,
                              onTap: () => _handleTap(channels[i]),
                            ),
                          ),
                        )
                      : Expanded(
                          child: _ChannelColumn(
                            channel: channels[i],
                            selected: selected,
                            currentLevel: _currentLevel(
                              i,
                              n,
                              _levelFor(channels[i]),
                            ),
                            tones: tones,
                            onTap: () => _handleTap(channels[i]),
                          ),
                        ),
                if (mini) const _Cheek(),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A blank end-plate bookending the strip in its centred, small-desk layout
/// -- filler that says "this desk is small on purpose", not a torn-out slot.
class _Cheek extends StatelessWidget {
  const _Cheek();

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 24,
    margin: const EdgeInsets.only(bottom: 12),
    color: SpendWiseColors.edge,
  );
}

/// One fader: an unlit LED, a four-letter scribble-strip abbreviation, the
/// share it carries, the fader itself, and the stable number underneath.
class _ChannelColumn extends StatelessWidget {
  const _ChannelColumn({
    required this.channel,
    required this.selected,
    required this.currentLevel,
    required this.tones,
    required this.onTap,
  });

  final _Channel channel;
  final String? selected;
  final double currentLevel;
  final CategoryTones tones;

  /// Fires the same effect the strip's own hit-testing does -- a screen
  /// reader drives this action directly, off the semantics tree, rather than
  /// through pointer coordinates, so its precision never depends on how
  /// narrow this channel's visual column got squeezed to.
  final VoidCallback onTap;

  static const _capHeight = 7.0;
  static const _trackHeight = 140.0;

  /// A folded category can be the one thing the screen is filtered to even
  /// though it has no channel of its own this period -- so AUX reads as
  /// selected too, rather than dimming while quietly holding the very
  /// category a reader just picked.
  bool get _isSelected => channel.isAux
      ? channel.auxFolded.any((item) => item.category == selected)
      : channel.category == selected;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final duration = reduce ? Duration.zero : const Duration(milliseconds: 220);
    final isDim = selected != null && !_isSelected;
    final ledColor = _isSelected ? SpendWiseColors.fg : SpendWiseColors.line;
    final textColor = _isSelected
        ? SpendWiseColors.fg
        : (isDim ? SpendWiseColors.line : SpendWiseColors.dim);
    final label = channel.isAux ? 'AUX' : _abbreviate(channel.category);
    final noText = channel.isAux
        ? 'Σ${channel.auxCount}'
        : channel.no.toString().padLeft(2, '0');
    final pctText = (channel.fraction * 100).toStringAsFixed(1);

    return Semantics(
      key: ValueKey(
        channel.isAux ? 'channel-aux' : 'channel-${channel.category}',
      ),
      button: true,
      label: channel.isAux
          ? 'AUX, ${channel.auxCount} more categories, $pctText percent, '
                'double tap to expand'
          : '${channel.category}, $pctText percent, double tap to filter',
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            width: 3,
            height: 3,
            color: ledColor,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: SpendWiseType.metaTight.copyWith(
              fontSize: 6.5,
              color: textColor,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            pctText,
            maxLines: 1,
            style: SpendWiseType.metaTight.copyWith(
              fontSize: 7,
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            height: _trackHeight,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  width: 2,
                  height: _trackHeight,
                  color: SpendWiseColors.line,
                ),
                AnimatedOpacity(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  opacity: isDim ? 0.28 : 1,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: currentLevel),
                    child: Container(
                      width: double.infinity,
                      height: _capHeight,
                      decoration: BoxDecoration(
                        color: channel.isAux
                            ? Colors.transparent
                            : tones.of(channel.category),
                        border: channel.isAux
                            ? Border.all(color: SpendWiseColors.dim)
                            : (_isSelected
                                  ? Border.symmetric(
                                      vertical: BorderSide(
                                        color: SpendWiseColors.fg,
                                      ),
                                    )
                                  : null),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            noText,
            style: SpendWiseType.metaTight.copyWith(
              fontSize: 7.5,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// The strip's abbreviation, and the one honestly unsolved piece of it: it
/// has no uniqueness guarantee, so two differently-named categories can
/// collide on the same four letters. The stable number underneath every
/// abbreviation is what keeps a collision from being the only way to tell
/// two channels apart.
String _abbreviate(String name) {
  final letters = name.replaceAll(RegExp('[^A-Za-z]'), '');
  final take = letters.length > 4 ? letters.substring(0, 4) : letters;
  return take.toUpperCase();
}

/// The index below the strip: every channel's full name, restated, because
/// a 21px column never had room to state it once.
class _PatchBay extends StatelessWidget {
  const _PatchBay({
    required this.channels,
    required this.selected,
    required this.tones,
    required this.auxExpanded,
    required this.onSelectChannel,
    required this.onToggleAux,
  });

  final List<_Channel> channels;
  final String? selected;
  final CategoryTones tones;
  final bool auxExpanded;
  final ValueChanged<String> onSelectChannel;
  final VoidCallback onToggleAux;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final channel in channels)
        _PatchRow(
          channel: channel,
          selected: selected,
          tones: tones,
          onTap: () =>
              channel.isAux ? onToggleAux() : onSelectChannel(channel.category),
        ),
    ];

    // Two columns, filled left-to-right then down a row, is the same
    // reading order a two-column grid gives -- chosen because the patch bay
    // is already stable-ordered top to bottom, and a single column would run
    // twice as far down the screen for the same fourteen rows.
    final paired = <Widget>[
      for (var i = 0; i < rows.length; i += 2)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: rows[i]),
            const SizedBox(width: 12),
            Expanded(
              child: i + 1 < rows.length ? rows[i + 1] : const SizedBox(),
            ),
          ],
        ),
    ];

    final aux = channels.where((channel) => channel.isAux);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...paired,
        if (aux.isNotEmpty && auxExpanded)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: SpendWiseColors.line)),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _AuxList(folded: aux.single.auxFolded),
              ),
            ),
          ),
      ],
    );
  }
}

/// One patch-bay row: a full-width, 48dp-tall target -- the dependable
/// fallback for anyone whose tap on the 21px strip above missed.
class _PatchRow extends StatelessWidget {
  const _PatchRow({
    required this.channel,
    required this.selected,
    required this.tones,
    required this.onTap,
  });

  final _Channel channel;
  final String? selected;
  final CategoryTones tones;
  final VoidCallback onTap;

  bool get _isSelected => channel.isAux
      ? channel.auxFolded.any((item) => item.category == selected)
      : channel.category == selected;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final isDim = selected != null && !_isSelected;
    final label = channel.isAux
        ? '+ ${channel.auxCount} more'
        : channel.category;
    final noText = channel.isAux ? 'Σ' : channel.no.toString().padLeft(2, '0');
    final pctText = '${(channel.fraction * 100).toStringAsFixed(1)}%';
    final rowColor = _isSelected ? SpendWiseColors.fg : SpendWiseColors.dim;
    final nameColor = _isSelected
        ? SpendWiseColors.bg
        : (isDim ? SpendWiseColors.line : SpendWiseColors.dim);
    final valueColor = _isSelected
        ? SpendWiseColors.bg
        : (isDim ? SpendWiseColors.line : SpendWiseColors.fg);

    return Semantics(
      key: ValueKey(channel.isAux ? 'patch-aux' : 'patch-${channel.category}'),
      button: true,
      label: channel.isAux
          ? '$label, $pctText, double tap to expand'
          : '$label, $pctText, double tap to filter',
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 48),
          color: _isSelected ? SpendWiseColors.fg : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: channel.isAux
                      ? Colors.transparent
                      : tones.of(channel.category),
                  border: channel.isAux ? Border.all(color: rowColor) : null,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                noText,
                style: SpendWiseType.metaTight.copyWith(color: nameColor),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SpendWiseType.row.copyWith(
                    fontSize: 12.5,
                    color: nameColor,
                  ),
                ),
              ),
              Text(
                pctText,
                style: SpendWiseType.metaTight.copyWith(color: valueColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The AUX fold's own list, one row per category it swallowed -- so "+ 15
/// more" is a claim a reader can check, not a number they have to trust.
class _AuxList extends StatelessWidget {
  const _AuxList({required this.folded});

  final List<_Channel> folded;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columnWidth = (constraints.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final channel in folded)
            SizedBox(
              width: columnWidth,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      channel.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SpendWiseType.metaTight,
                    ),
                  ),
                  Text(
                    '${(channel.fraction * 100).toStringAsFixed(2)}%',
                    style: SpendWiseType.metaTight,
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

/// The N=1 case: a single fader has nothing to be compared against, so the
/// strip does not draw at all. This is its own module -- the category named
/// in full, one wide fader reading 100%, the same track-groove relief the
/// strip uses -- so it still reads as the same instrument, not a fallback
/// screen bolted on.
class _SoloModule extends StatelessWidget {
  const _SoloModule({
    required this.category,
    required this.currency,
    required this.color,
    required this.entry,
  });

  final CategoryAnalytics category;
  final String currency;
  final Color color;
  final AnimationController entry;

  static const _level = 140.0;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: SpendWiseColors.edge),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              category.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SpendWiseType.lead,
            ),
            const SizedBox(height: 2),
            Text(
              'Nothing to compare against yet — one category is the whole '
              'month.',
              style: SpendWiseType.body.copyWith(fontSize: 11),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 40,
                  height: _level + 10,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      Container(
                        width: 4,
                        height: _level + 10,
                        color: SpendWiseColors.line,
                      ),
                      AnimatedBuilder(
                        animation: entry,
                        builder: (context, _) {
                          final t = reduce
                              ? 1.0
                              : Curves.easeOutQuint.transform(entry.value);
                          return Padding(
                            padding: EdgeInsets.only(bottom: _level * t),
                            child: Container(
                              width: 40,
                              height: 9,
                              decoration: BoxDecoration(
                                color: color,
                                border: Border(
                                  top: BorderSide(
                                    color: SpendWiseColors.fg.withValues(
                                      alpha: .3,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '100%',
                        style: SpendWiseType.figure.copyWith(fontSize: 28),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${formatAmount(MoneyViewData(category.amountMinor, currency: currency))} '
                        '· every expense this period',
                        style: SpendWiseType.metaTight,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
