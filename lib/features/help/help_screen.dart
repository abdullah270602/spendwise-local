import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../onboarding/onboarding_screen.dart';
import '../shell/spendwise_view_model.dart';
import 'help_figures.dart';
import 'help_topics.dart';

/// The manual.
///
/// An index of figures rather than a table of contents: a glyph, a short
/// name, one line. Help is scanned by somebody mildly annoyed who wants one
/// answer, not read front to back.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final topics = helpTopics(viewModel);
    return Scaffold(
      appBar: AppBar(
        title: const Text('How SpendWise works'),
        actions: [
          CopyPromptButton(
            dense: true,
            title: 'The whole guide',
            brief: [
              for (final topic in topics) '## ${topic.title}\n${topic.brief}',
            ].join('\n\n'),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          SpendWiseTheme.gutter,
          10,
          SpendWiseTheme.gutter,
          40 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          for (final topic in topics)
            _TopicRow(
              topic: topic,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => _TopicScreen(topic: topic),
                ),
              ),
            ),
          const SizedBox(height: 28),
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
  const _TopicRow({required this.topic, required this.onTap});

  final HelpTopic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SpendWiseColors.line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Icon(topic.glyph, size: 19, color: SpendWiseColors.dim),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(topic.title, style: SpendWiseType.lead.copyWith(fontSize: 16)),
                const SizedBox(height: 2),
                Text(
                  topic.summary,
                  style: SpendWiseType.body.copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: SpendWiseColors.dim,
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
    appBar: AppBar(
      title: Text(topic.title),
      actions: [
        CopyPromptButton(dense: true, title: topic.title, brief: topic.brief),
      ],
    ),
    body: ListView(
      padding: EdgeInsets.fromLTRB(
        SpendWiseTheme.gutter,
        6,
        SpendWiseTheme.gutter,
        40 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [
        ...topic.body(),
        const SizedBox(height: 18),
        // The app has no network and never will, so the most useful thing it
        // can do with a question is hand you a well-formed version of it.
        CopyPromptButton(title: topic.title, brief: topic.brief),
      ],
    ),
  );
}
