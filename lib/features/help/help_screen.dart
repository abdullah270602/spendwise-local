import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../onboarding/onboarding_screen.dart';
import '../shell/spendwise_view_model.dart';
import 'help_topics.dart';

/// The manual.
///
/// Eight chapters in the order the app is actually met: what comes in, what
/// SpendWise makes of it, what you do about it, and what it will never do.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final topics = helpTopics();
    return Scaffold(
      appBar: AppBar(title: const Text('How SpendWise works')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          SpendWiseTheme.gutter,
          6,
          SpendWiseTheme.gutter,
          40 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          Text(
            'SpendWise turns the alerts your bank already sends into a ledger '
            'you did not have to type. These are the parts worth knowing, '
            'each with a real example.',
            style: SpendWiseType.body.copyWith(fontSize: 13.5),
          ),
          const SizedBox(height: 26),
          for (var index = 0; index < topics.length; index++)
            _TopicRow(
              number: index + 1,
              topic: topics[index],
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => _TopicScreen(topic: topics[index]),
                ),
              ),
            ),
          const SizedBox(height: 30),
          const Eyebrow('From the beginning'),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (routeContext) => OnboardingScreen(
                  viewModel: viewModel,
                  // Replayed, not repeated: finishing here closes the screen
                  // rather than marking first run complete all over again.
                  onDone: () => Navigator.pop(routeContext),
                ),
              ),
            ),
            child: const Text('Replay the introduction'),
          ),
        ],
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({
    required this.number,
    required this.topic,
    required this.onTap,
  });

  final int number;
  final HelpTopic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SpendWiseColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$number',
              style: SpendWiseType.metaTight.copyWith(height: 1.6),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(topic.title, style: SpendWiseType.row),
                const SizedBox(height: 3),
                Text(
                  topic.summary,
                  style: SpendWiseType.body.copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 2, left: 8),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: SpendWiseColors.dim,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TopicScreen extends StatelessWidget {
  const _TopicScreen({required this.topic});

  final HelpTopic topic;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(topic.title)),
    body: ListView(
      padding: EdgeInsets.fromLTRB(
        SpendWiseTheme.gutter,
        4,
        SpendWiseTheme.gutter,
        48 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [
        Text(topic.summary, style: SpendWiseType.lead),
        const SizedBox(height: 20),
        ...topic.body(),
      ],
    ),
  );
}
