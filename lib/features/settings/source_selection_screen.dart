import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';

class SourceSelectionScreen extends StatelessWidget {
  const SourceSelectionScreen({super.key, required this.viewModel});
  final SpendWiseViewModel viewModel;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notification sources')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        Text(
          'Choose trusted financial apps',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'SpendWise only processes notifications from sources you enable. Other notifications are ignored.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: SpendWiseColors.textSecondary),
        ),
        const SizedBox(height: 18),
        if (viewModel.sources.isEmpty)
          const EmptyState(
            icon: Icons.apps_outage_outlined,
            title: 'No sources discovered',
            message: 'Install or open a supported banking, wallet, or messaging app, then return here.',
          )
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < viewModel.sources.length; i++) ...[
                  SwitchListTile(
                    secondary: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: SpendWiseColors.accentMuted,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _sourceIcon(viewModel.sources[i]),
                        color: _healthColor(viewModel.sources[i].health),
                        size: 20,
                      ),
                    ),
                    title: Text(viewModel.sources[i].label),
                    subtitle: Text(
                      _status(viewModel.sources[i]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    value: viewModel.sources[i].enabled,
                    onChanged: (value) => viewModel.setSourceEnabled(
                      viewModel.sources[i].packageName,
                      value,
                    ),
                  ),
                  if (i != viewModel.sources.length - 1)
                    const Divider(height: 1, indent: 68),
                ],
              ],
            ),
          ),
        const SizedBox(height: 18),
        const PrivacyBanner(compact: true),
      ],
    ),
  );

  static String _shortDate(DateTime value) =>
      '${value.day}/${value.month}/${value.year}';
  static IconData _sourceIcon(SourceViewData source) =>
      source.packageName.toLowerCase().contains('messag')
      ? Icons.sms_outlined
      : source.packageName.toLowerCase().contains('bank')
      ? Icons.account_balance_outlined
      : Icons.notifications_outlined;
  static Color _healthColor(SourceHealth health) => switch (health) {
    SourceHealth.healthy => SpendWiseColors.income,
    SourceHealth.idle => SpendWiseColors.textSecondary,
    SourceHealth.stale => SpendWiseColors.warning,
    SourceHealth.permissionRequired ||
    SourceHealth.error => SpendWiseColors.expense,
  };
  static String _status(SourceViewData source) {
    final health = switch (source.health) {
      SourceHealth.healthy => 'Healthy',
      SourceHealth.idle => 'Waiting for activity',
      SourceHealth.stale => 'No recent events',
      SourceHealth.permissionRequired => 'Permission required',
      SourceHealth.error => 'Needs attention',
    };
    final last = source.lastSeenAt == null
        ? ''
        : ' · Last seen ${_shortDate(source.lastSeenAt!)}';
    final count = source.observationCount == 0
        ? ''
        : ' · ${source.observationCount} events';
    return source.statusDetail.isNotEmpty
        ? '$health · ${source.statusDetail}'
        : '$health$last$count';
  }
}
