import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/parser_health.dart';
import '../shell/spendwise_view_model.dart';

/// What the parser is actually managing, per source.
///
/// Deliberately plain and a little dense. This is not a screen anybody uses
/// daily; it is the one place to answer "why did it miss that" without
/// exporting the ledger and reading JSON, and the answer is usually a
/// sentence the parser already wrote about why it stopped.
///
/// It shows counts before it shows any percentage, because the percentages
/// lie at small numbers: one alert read out of one is not 100% of anything.
class ParserHealthScreen extends StatelessWidget {
  const ParserHealthScreen({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final health = viewModel.uiParserHealth();
    final withTraffic = health.sources
        .where((source) => source.total > 0)
        .toList();
    final silent = health.sources.where((source) => source.total == 0).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Reading accuracy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Summary(health: health),
          const SizedBox(height: 20),
          if (withTraffic.isEmpty)
            Text(
              'Nothing has been captured yet. Once an app you have enabled '
              'posts an alert, it will be counted here.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          for (final source in withTraffic) ...[
            _SourceCard(
              source: source,
              onSeeSkipped: source.ignored == 0
                  ? null
                  : () => _showSkipped(context, viewModel, source),
            ),
            const SizedBox(height: 12),
          ],
          if (silent.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Enabled, nothing captured',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'These are switched on but have never posted an alert '
              'SpendWise saw. Usually the app sends nothing, or notification '
              'access was granted after they last spoke.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (final source in silent)
                    ListTile(
                      dense: true,
                      title: Text(source.label),
                      subtitle: source.packageName == null
                          ? null
                          : Text(source.packageName!),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The alerts a source sent that were judged not to be money.
///
/// The report can say a source sent twenty-one alerts and none were about
/// money. It cannot say whether that was right -- only the alerts can, and
/// nothing showed them: Review lists what is unanswered, and a skipped alert
/// is by definition answered. This is where the claim gets checked.
void _showSkipped(
  BuildContext context,
  SpendWiseViewModel viewModel,
  SourceCoverage source,
) {
  final alerts = viewModel.uiSkippedAlerts(packageName: source.packageName);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .8,
      maxChildSize: .95,
      builder: (context, controller) => ListView.separated(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        itemCount: alerts.length + 1,
        separatorBuilder: (_, _) => const Divider(height: 22),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Skipped by ${source.label}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'These carried no amount, so SpendWise read them as not '
                  'being about money. If one of them is a payment, that is a '
                  'gap worth reporting.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          }
          final alert = alerts[index - 1];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (alert.title.isNotEmpty)
                Text(
                  alert.title,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              const SizedBox(height: 2),
              Text(alert.body, style: Theme.of(context).textTheme.bodySmall),
            ],
          );
        },
      ),
    ),
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.health});

  final ParserHealth health;

  @override
  Widget build(BuildContext context) {
    final coverage = health.coverage;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              coverage == null
                  ? 'No alert has looked like money yet'
                  : '${health.parsed} of ${health.attempted} read without '
                        'asking',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              // The denominator is the whole point, so it is stated rather
              // than left to be inferred from a percentage.
              'Counted against alerts that carried an amount. '
              '${health.ignored} more said nothing about money — passcodes, '
              'deliveries, offers — and are not failures.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (health.review + health.error > 0) ...[
              const SizedBox(height: 10),
              Text(
                '${health.review + health.error} still waiting on you.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: SpendWiseColors.warning),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.source, this.onSeeSkipped});

  final SourceCoverage source;
  final VoidCallback? onSeeSkipped;

  @override
  Widget build(BuildContext context) {
    final unread = source.review + source.error;
    return Card(
      child: InkWell(
        onTap: onSeeSkipped,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      source.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (unread > 0)
                    Text(
                      '$unread unread',
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: SpendWiseColors.warning),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                source.attempted == 0
                    ? '${source.ignored} alerts, none about money'
                    : '${source.parsed} of ${source.attempted} money alerts '
                          'read'
                          '${source.ignored > 0 ? ', ${source.ignored} not about money' : ''}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (source.onLastResort > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '${source.onLastResort} read only by the last-resort parser: '
                  'one amount and one direction word, no recognised sentence.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (source.reasons.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'What stopped it',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                for (final reason in source.reasons.take(4))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '${reason.count}×  ${reason.reason}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
              if (source.parsers.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  source.parsers.entries
                      .map((entry) => '${entry.key} ${entry.value}')
                      .join('   '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SpendWiseColors.dim,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
              if (onSeeSkipped != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Tap to read the ${source.ignored} it skipped',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
