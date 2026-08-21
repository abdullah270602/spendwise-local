import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../features/shell/spendwise_view_model.dart';

String formatMoney(MoneyViewData money, {bool signed = false}) {
  final value = money.majorUnits.abs();
  final fixed = value.toStringAsFixed(2);
  final pieces = fixed.split('.');
  final whole = pieces.first;
  final grouped = whole.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );
  final decimals = pieces.last == '00' ? '' : '.${pieces.last}';
  final prefix = signed
      ? (money.minorUnits < 0 ? '−' : '+')
      : (money.minorUnits < 0 ? '−' : '');
  return '$prefix${money.currency} $grouped$decimals';
}

String titleCase(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
    ],
  );
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = SpendWiseColors.accent,
    this.detail,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? detail;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: color, size: 17),
              ),
              const Spacer(),
              if (detail != null)
                Text(
                  detail!,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: color),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: Theme.of(context).textTheme.titleLarge),
          ),
        ],
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: SpendWiseColors.accentMuted,
          ),
          child: Icon(icon, color: SpendWiseColors.accent, size: 28),
        ),
        const SizedBox(height: 18),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (action != null) ...[
          const SizedBox(height: 18),
          FilledButton(onPressed: onAction, child: Text(action!)),
        ],
      ],
    ),
  );
}

class TransactionTile extends StatelessWidget {
  const TransactionTile(this.transaction, {super.key, this.onTap});
  final TransactionViewData transaction;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (transaction.kind) {
      TransactionKind.income => (
        Icons.south_west_rounded,
        SpendWiseColors.income,
      ),
      TransactionKind.expense => (
        Icons.north_east_rounded,
        SpendWiseColors.expense,
      ),
      TransactionKind.transfer => (
        Icons.swap_horiz_rounded,
        SpendWiseColors.warning,
      ),
    };
    return ListTile(
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 19),
      ),
      title: Text(
        transaction.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${transaction.category} · ${transaction.subtitle}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatMoney(
              transaction.amount,
              signed: transaction.kind != TransactionKind.transfer,
            ),
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
          if (transaction.evidenceCount > 1)
            Text(
              '${transaction.evidenceCount} sources',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class PrivacyBanner extends StatelessWidget {
  const PrivacyBanner({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(compact ? 12 : 16),
    decoration: BoxDecoration(
      color: SpendWiseColors.accentMuted.withValues(alpha: .7),
      border: Border.all(color: SpendWiseColors.accent.withValues(alpha: .22)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.lock_outline_rounded,
          color: SpendWiseColors.accent,
          size: 20,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            'Your ledger stays encrypted on this device. SpendWise has no account, cloud, analytics, or hidden uploads.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: const Color(0xFFB9D9C6)),
          ),
        ),
      ],
    ),
  );
}
