import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';

class SourceSelectionScreen extends StatefulWidget {
  const SourceSelectionScreen({super.key, required this.viewModel});
  final SpendWiseViewModel viewModel;

  @override
  State<SourceSelectionScreen> createState() => _SourceSelectionScreenState();
}

class _SourceSelectionScreenState extends State<SourceSelectionScreen> {
  final _search = TextEditingController();
  final _pending = <String>{};
  final _optimistic = <String, bool>{};

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_modelChanged);
  }

  @override
  void didUpdateWidget(covariant SourceSelectionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_modelChanged);
      widget.viewModel.addListener(_modelChanged);
    }
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_modelChanged);
    _search.dispose();
    super.dispose();
  }

  void _modelChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final all = widget.viewModel.sources;
    final matching = all.where((source) {
      if (query.isEmpty) return true;
      return source.label.toLowerCase().contains(query) ||
          source.packageName.toLowerCase().contains(query);
    }).toList();
    // What you already trust comes first. The device lists a hundred apps and
    // the handful you enabled are the ones you came back to check.
    final visible = [
      ...matching.where(_isEnabled),
      ...matching.where((source) => !_isEnabled(source)),
    ];
    final enabledCount = all.where(_isEnabled).length;
    final firstDisabled = matching.where(_isEnabled).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Notification sources')),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              SpendWiseTheme.gutter,
              8,
              SpendWiseTheme.gutter,
              14,
            ),
            sliver: SliverList.list(
              children: [
                Text(
                  'Choose trusted financial apps',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Only enabled apps enter SpendWise’s encrypted local evidence queue.',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: SpendWiseColors.textSecondary),
                ),
                if (!widget.viewModel.notificationAccessGranted) ...[
                  const SizedBox(height: 14),
                  // A caution, not a card: a left rule in the warning tone
                  // and the app's own edge on the other three sides, the
                  // same drawing the export screen's own notice uses -- there
                  // is no second surface colour anywhere in this app to fill
                  // a box with.
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: SpendWiseColors.warning,
                          width: 2,
                        ),
                        top: BorderSide(color: SpendWiseColors.edge),
                        right: BorderSide(color: SpendWiseColors.edge),
                        bottom: BorderSide(color: SpendWiseColors.edge),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Notification access is off',
                                style: SpendWiseType.rowStrong.copyWith(
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Choose apps now; capture starts after access is granted.',
                                style: SpendWiseType.body.copyWith(
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: widget.viewModel.requestNotificationAccess,
                          child: const Text('Enable'),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // The theme's own square, hairline field -- the identical
                // control Ledger already searches with. A pill-shaped
                // SearchBar sitting above a flat list read as a second app.
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: SpendWiseType.row,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search apps or package names',
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Wrapped so a doubled text scale shrinks and ellipses
                    // this half of the line rather than pushing the match
                    // count off the right edge of a 360px phone.
                    Expanded(
                      child: Text(
                        enabledCount == 0
                            ? 'Nothing enabled yet'
                            : '$enabledCount enabled, shown first',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Flexible rather than a bare Text for the same reason as
                    // its neighbour: at a doubled scale even this short a
                    // count can no longer be trusted to fit unshrunk.
                    Flexible(
                      child: Text(
                        query.isEmpty
                            ? '${all.length} installed apps'
                            : '${visible.length} matches',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (all.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: EmptyState(
                  icon: Icons.apps_outage_outlined,
                  title: 'No apps discovered',
                  message: 'Open or install a banking, wallet, or messaging app, then return here.',
                ),
              ),
            )
          else if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No matching apps',
                message: 'Try an app name or package name such as “messages”.',
                action: 'Clear search',
                onAction: () {
                  _search.clear();
                  setState(() {});
                },
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                SpendWiseTheme.gutter,
                0,
                SpendWiseTheme.gutter,
                18,
              ),
              sliver: SliverList.separated(
                itemCount: visible.length,
                // Indent matches the icon-plus-gap width below it, so the
                // hairline picks up exactly where each row's title starts.
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 57),
                itemBuilder: (context, index) {
                  final tile = _sourceTile(visible[index]);
                  // One heading where the enabled run ends, so the split is
                  // stated rather than left for the user to infer.
                  if (index != firstDisabled || firstDisabled == 0) {
                    return tile;
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(0, 18, 0, 6),
                        child: Eyebrow('Everything else'),
                      ),
                      tile,
                    ],
                  );
                },
              ),
            ),
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(
              SpendWiseTheme.gutter,
              4,
              SpendWiseTheme.gutter,
              48,
            ),
            sliver: SliverToBoxAdapter(child: PrivacyBanner(compact: true)),
          ),
        ],
      ),
    );
  }

  Widget _sourceTile(SourceViewData source) {
    final waiting = _pending.contains(source.packageName);
    final enabled = _isEnabled(source);
    return Semantics(
      toggled: enabled,
      label: '${source.label} notification source',
      child: InkWell(
        onTap: waiting ? null : () => _toggle(source, !enabled),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _SourceIcon(source: source),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      source.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SpendWiseType.row,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _status(source),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SpendWiseType.meta,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Switch(
                value: enabled,
                onChanged: waiting ? null : (value) => _toggle(source, value),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isEnabled(SourceViewData source) =>
      _optimistic[source.packageName] ?? source.enabled;

  Future<void> _toggle(SourceViewData source, bool enabled) async {
    setState(() {
      _pending.add(source.packageName);
      _optimistic[source.packageName] = enabled;
    });
    try {
      await widget.viewModel.setSourceEnabled(source.packageName, enabled);
      if (!mounted) return;
      setState(() {
        _pending.remove(source.packageName);
        _optimistic.remove(source.packageName);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pending.remove(source.packageName);
        _optimistic.remove(source.packageName);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not ${enabled ? 'enable' : 'disable'} ${source.label}. Try again.',
          ),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _toggle(source, enabled),
          ),
        ),
      );
    }
  }

  static String _shortDate(DateTime value) =>
      '${value.day}/${value.month}/${value.year}';

  static String _status(SourceViewData source) {
    if (!source.enabled) return 'Disabled · Tap to allow capture';
    final health = switch (source.health) {
      SourceHealth.healthy => 'Active',
      SourceHealth.idle => 'Waiting for activity',
      SourceHealth.stale => 'No recent events',
      SourceHealth.permissionRequired => 'Ready after notification access',
      SourceHealth.error => 'Needs attention',
    };
    final last = source.lastSeenAt == null
        ? ''
        : ' · Last seen ${_shortDate(source.lastSeenAt!)}';
    final detail = source.statusDetail.isEmpty
        ? ''
        : ' · ${source.statusDetail}';
    return '$health$last$detail';
  }
}

class _SourceIcon extends StatelessWidget {
  const _SourceIcon({required this.source});
  final SourceViewData source;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    clipBehavior: Clip.hardEdge,
    decoration: const BoxDecoration(
      border: Border.fromBorderSide(BorderSide(color: SpendWiseColors.edge)),
    ),
    child: source.iconPng == null
        ? Icon(
            _fallbackIcon(source),
            color: _healthColor(source.health),
            size: 21,
          )
        : Image.memory(
            source.iconPng!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Icon(
              _fallbackIcon(source),
              color: _healthColor(source.health),
              size: 21,
            ),
          ),
  );

  static IconData _fallbackIcon(SourceViewData source) {
    final package = source.packageName.toLowerCase();
    if (package.contains('messag')) return Icons.sms_outlined;
    if (package.contains('bank')) return Icons.account_balance_outlined;
    return Icons.notifications_outlined;
  }

  static Color _healthColor(SourceHealth health) => switch (health) {
    SourceHealth.healthy => SpendWiseColors.income,
    SourceHealth.idle => SpendWiseColors.textSecondary,
    SourceHealth.stale => SpendWiseColors.warning,
    SourceHealth.permissionRequired ||
    SourceHealth.error => SpendWiseColors.expense,
  };
}
