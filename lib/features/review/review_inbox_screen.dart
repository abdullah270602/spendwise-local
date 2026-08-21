import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';
import '../settings/source_selection_screen.dart';
import '../transactions/transaction_details_screen.dart';

class ReviewInboxScreen extends StatelessWidget {
  const ReviewInboxScreen({super.key, required this.viewModel});
  final SpendWiseViewModel viewModel;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Review inbox'),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(32),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Only uncertain matches need your attention',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
      children: [
        _NotificationRecoveryPanel(viewModel: viewModel),
        const SizedBox(height: 20),
        if (viewModel.reviews.isEmpty)
          const EmptyState(
            icon: Icons.verified_outlined,
            title: 'You’re all caught up',
            message:
                'New uncertain matches and unparsed events will appear here.',
          )
        else
          for (final item in viewModel.reviews)
            _ReviewCard(item: item, viewModel: viewModel),
      ],
    ),
  );
}

class _NotificationRecoveryPanel extends StatefulWidget {
  const _NotificationRecoveryPanel({required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<_NotificationRecoveryPanel> createState() =>
      _NotificationRecoveryPanelState();
}

class _NotificationRecoveryPanelState
    extends State<_NotificationRecoveryPanel> {
  bool _scanning = false;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: SpendWiseColors.surfaceRaised,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: SpendWiseColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.notification_add_outlined,
                color: SpendWiseColors.accent,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Missing a transaction?',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Check enabled-source notifications still visible in your Android tray. Already captured alerts are safely ignored.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _scanning ? null : _scan,
              icon: _scanning
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(
                _scanning ? 'Scanning tray…' : 'Scan notification tray',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Cleared or dismissed notifications cannot be recovered by Android.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final result = await widget.viewModel.uiScanNotificationTray();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      switch (result.status) {
        case NotificationTrayScanViewStatus.accessRequired:
          messenger.showSnackBar(
            SnackBar(
              content: const Text(
                'Notification access is required before SpendWise can scan the tray.',
              ),
              action: SnackBarAction(
                label: 'Open settings',
                onPressed: widget.viewModel.requestNotificationAccess,
              ),
            ),
          );
        case NotificationTrayScanViewStatus.listenerUnavailable:
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Android is reconnecting SpendWise. Wait a moment, then scan again.',
              ),
            ),
          );
        case NotificationTrayScanViewStatus.completed:
          messenger.showSnackBar(
            SnackBar(content: Text(_completedMessage(result))),
          );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The tray could not be scanned. Check notification access and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  String _completedMessage(NotificationTrayScanViewData result) {
    if (result.failedCount > 0) {
      return 'Recovered ${result.queuedCount} new ${_plural(result.queuedCount, 'notification')}; ${result.failedCount} could not be read.';
    }
    if (result.queuedCount > 0) {
      return 'Recovered ${result.queuedCount} new ${_plural(result.queuedCount, 'notification')} from the tray.';
    }
    if (result.eligibleCount > 0) {
      return 'Checked ${result.eligibleCount} ${_plural(result.eligibleCount, 'notification')}. Everything visible was already captured.';
    }
    return 'No enabled-source notifications are currently visible in the tray.';
  }

  String _plural(int count, String singular) =>
      count == 1 ? singular : '${singular}s';
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.item, required this.viewModel});
  final ReviewViewData item;
  final SpendWiseViewModel viewModel;
  @override
  Widget build(BuildContext context) {
    final icon = switch (item.reason) {
      ReviewReason.possibleDuplicate => Icons.content_copy_rounded,
      ReviewReason.possibleTransfer => Icons.swap_horiz_rounded,
      ReviewReason.needsCategory => Icons.category_outlined,
      ReviewReason.lowConfidence => Icons.help_outline_rounded,
      ReviewReason.parseFailed => Icons.text_snippet_outlined,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: SpendWiseColors.warning.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: SpendWiseColors.warning, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item.description,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (item.transactions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: SpendWiseColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      for (final tx in item.transactions) TransactionTile(tx),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (item.transactions.isEmpty)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                SourceSelectionScreen(viewModel: viewModel),
                          ),
                        ),
                        child: const Text('Configure sources'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _confirmDismiss(context),
                        child: const Text('Dismiss all'),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TransactionDetailsScreen(
                              viewModel: viewModel,
                              transaction: item.transactions.first,
                            ),
                          ),
                        ),
                        child: const Text('Inspect details'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () =>
                            viewModel.resolveReview(item.id, merge: false),
                        child: const Text('Confirm as shown'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDismiss(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dismiss unsupported evidence?'),
        content: Text(
          '${item.title}\n\nThese observations stay stored locally, but will no longer appear in Review.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Dismiss all'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await viewModel.resolveReview(item.id, merge: false);
    }
  }
}
