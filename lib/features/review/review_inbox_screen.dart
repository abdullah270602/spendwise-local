import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';

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
      ReviewReason.parseFailed => Icons.text_snippet_outlined,
    };
    final canMerge =
        item.reason == ReviewReason.possibleDuplicate ||
        item.reason == ReviewReason.possibleTransfer;
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
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          viewModel.resolveReview(item.id, merge: false),
                      child: Text(canMerge ? 'Keep separate' : 'Dismiss'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () =>
                          viewModel.resolveReview(item.id, merge: true),
                      child: Text(canMerge ? 'Merge' : 'Accept'),
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
}
