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
    body: viewModel.reviews.isEmpty
        ? const EmptyState(
            icon: Icons.verified_outlined,
            title: 'You’re all caught up',
            message:
                'New uncertain matches and unparsed events will appear here.',
          )
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
            itemCount: viewModel.reviews.length,
            itemBuilder: (context, i) =>
                _ReviewCard(item: viewModel.reviews[i], viewModel: viewModel),
          ),
  );
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
