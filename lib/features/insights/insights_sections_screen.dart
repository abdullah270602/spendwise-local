import 'package:flutter/material.dart';

import '../../app/category_tones.dart';
import '../../app/theme.dart';
import '../../widgets/chooser_kit.dart';
import '../../widgets/shape_kit.dart';
import '../shell/spendwise_view_model.dart';
import 'chronograph.dart';
import 'gate.dart';
import 'gate_sensitivity_screen.dart';
import 'insights_layout.dart';
import 'insights_screen.dart';
import 'mixing_desk.dart';
import 'seismograph.dart';
import 'spending_analytics.dart';

/// The three questions Insights answers, each turned on or off on its own.
///
/// One list of five drawings would have been the obvious build and the wrong
/// one: the dial and the trace are not alternatives, they answer different
/// questions, and a chooser offering them side by side would have been asking
/// people to pick between answers to questions they had not been asked.
class InsightsSectionsScreen extends StatefulWidget {
  const InsightsSectionsScreen({
    super.key,
    required this.viewModel,
    required this.resolution,
  });

  final SpendWiseViewModel viewModel;

  /// The period the screen is currently reading, so every preview below is a
  /// picture of the same month the reader just came from.
  final AnalyticsResolution resolution;

  @override
  State<InsightsSectionsScreen> createState() => _InsightsSectionsScreenState();
}

class _InsightsSectionsScreenState extends State<InsightsSectionsScreen> {
  SpendWiseViewModel get viewModel => widget.viewModel;

  Future<void> _open(Widget screen) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final analytics = SpendingAnalytics.calculate(
      transactions: viewModel.transactions,
      resolution: widget.resolution,
    );
    final tones = viewModel.tonesFor(
      analytics.categories.map((item) => item.category),
    );
    final change = InsightsChange.fromId(
      viewModel.uiViewPreference(InsightsPreference.change),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('What Insights shows')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          SpendWiseTheme.gutter,
          18,
          SpendWiseTheme.gutter,
          32 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          Text(
            'Three questions, answered separately. Turn off the ones you do '
            'not ask.',
            style: SpendWiseType.body.copyWith(
              fontSize: 13,
              color: SpendWiseColors.dim,
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Column(
              children: [
                _Entry(
                  title: 'Over time',
                  value: InsightsOverTime.fromId(
                    viewModel.uiViewPreference(InsightsPreference.overTime),
                  ).title,
                  onTap: () => _open(
                    InsightsOverTimeScreen(
                      viewModel: viewModel,
                      analytics: analytics,
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 16),
                _Entry(
                  title: 'Where your money went',
                  value: InsightsShare.fromId(
                    viewModel.uiViewPreference(InsightsPreference.share),
                  ).title,
                  onTap: () => _open(
                    InsightsShareScreen(
                      viewModel: viewModel,
                      analytics: analytics,
                      tones: tones,
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 16),
                _Entry(
                  title: 'What changed',
                  value: change.title,
                  onTap: () => _open(
                    InsightsChangeScreen(
                      viewModel: viewModel,
                      analytics: analytics,
                      tones: tones,
                    ),
                  ),
                ),
                // Only where it is the thing being drawn. A threshold with
                // nothing behind it is a setting for a screen you cannot see.
                if (change == InsightsChange.gate) ...[
                  const Divider(height: 1, indent: 16),
                  _Entry(
                    title: 'What counts as a move',
                    value: GateSensitivity.fromId(
                      viewModel.uiViewPreference(
                        InsightsPreference.gateSensitivity,
                      ),
                    ).title,
                    onTap: () => _open(
                      GateSensitivityScreen(
                        selected: GateSensitivity.fromId(
                          viewModel.uiViewPreference(
                            InsightsPreference.gateSensitivity,
                          ),
                        ),
                        onSelected: (value) => viewModel.uiSetViewPreference(
                          InsightsPreference.gateSensitivity,
                          value.id,
                        ),
                        preview: analytics.categoryChanges,
                        tones: tones,
                        totalSpendingMinor: analytics.totalSpendingMinor,
                        currency: analytics.currency,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.title, required this.value, required this.onTap});

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    subtitle: Text(value),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

/// A preview of a section, drawn from the real ledger and scaled to fit.
///
/// Scaled rather than clipped: what is being chosen between here is a *form*,
/// and half a form with the rest cut off is not a picture of it. Shrinking
/// keeps every part of the drawing on screen and in proportion, which is what
/// a preview is for; the real thing is a tap away at full size.
class _SectionPreview extends StatelessWidget {
  const _SectionPreview({required this.child});

  /// Tall enough to show a dial or a fourteen-channel desk whole once scaled,
  /// short enough that the options below it are still on screen on a small
  /// phone -- the point of a pinned preview is that you can see both.
  static const _height = 236.0;

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _height,
    width: double.infinity,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topCenter,
      child: SizedBox(
        // Laid out at the width these visuals will really have, then scaled
        // as one piece, so nothing reflows into an arrangement the screen
        // itself would never produce.
        width: MediaQuery.sizeOf(context).width - SpendWiseTheme.gutter * 2,
        child: child,
      ),
    ),
  );
}

/// Whether the days are drawn at all.
class InsightsOverTimeScreen extends StatefulWidget {
  const InsightsOverTimeScreen({
    super.key,
    required this.viewModel,
    required this.analytics,
  });

  final SpendWiseViewModel viewModel;
  final SpendingAnalytics analytics;

  @override
  State<InsightsOverTimeScreen> createState() => _InsightsOverTimeScreenState();
}

class _InsightsOverTimeScreenState extends State<InsightsOverTimeScreen> {
  InsightsOverTime get _current => InsightsOverTime.fromId(
    widget.viewModel.uiViewPreference(InsightsPreference.overTime),
  );

  void _choose(InsightsOverTime value) {
    widget.viewModel.uiSetViewPreference(InsightsPreference.overTime, value.id);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return ChooserScreen(
      title: 'Over time',
      preview: current.isOn
          ? _SectionPreview(
              child: FlowSpine(
                buckets: widget.analytics.buckets,
                currency: widget.analytics.currency,
              ),
            )
          : const _NothingDrawn(
              'Insights opens on the figures, with no chart above them.',
            ),
      children: [
        ChoiceGroup(
          label: 'The days themselves',
          first: true,
          children: [
            for (final value in InsightsOverTime.values)
              ChoiceRow(
                title: value.title,
                detail: value.detail,
                selected: current == value,
                onTap: () => _choose(value),
              ),
          ],
        ),
      ],
    );
  }
}

/// How the period's spending is split by category.
class InsightsShareScreen extends StatefulWidget {
  const InsightsShareScreen({
    super.key,
    required this.viewModel,
    required this.analytics,
    required this.tones,
  });

  final SpendWiseViewModel viewModel;
  final SpendingAnalytics analytics;
  final CategoryTones tones;

  @override
  State<InsightsShareScreen> createState() => _InsightsShareScreenState();
}

class _InsightsShareScreenState extends State<InsightsShareScreen> {
  InsightsShare get _current => InsightsShare.fromId(
    widget.viewModel.uiViewPreference(InsightsPreference.share),
  );

  void _choose(InsightsShare value) {
    widget.viewModel.uiSetViewPreference(InsightsPreference.share, value.id);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final analytics = widget.analytics;
    return ChooserScreen(
      title: 'Where your money went',
      preview: switch (current) {
        InsightsShare.off => const _NothingDrawn(
          'Insights stops after the figures and whatever changed.',
        ),
        InsightsShare.bars => _SectionPreview(
          child: CategoryBars(
            analytics: analytics,
            tones: widget.tones,
            selected: null,
            onSelect: (_) {},
          ),
        ),
        InsightsShare.chronograph => _SectionPreview(
          child: Chronograph(
            categories: analytics.categories,
            tones: widget.tones,
            selected: null,
            onSelect: (_) {},
            currency: analytics.currency,
          ),
        ),
        InsightsShare.mixingDesk => _SectionPreview(
          child: MixingDesk(
            categories: analytics.categories,
            tones: widget.tones,
            selected: null,
            onSelect: (_) {},
            currency: analytics.currency,
          ),
        ),
      },
      children: [
        ChoiceGroup(
          label: 'The breakdown',
          caption: 'All of it, however many categories you have.',
          first: true,
          children: [
            for (final value in InsightsShare.values)
              ChoiceRow(
                title: value.title,
                detail: value.detail,
                selected: current == value,
                onTap: () => _choose(value),
              ),
          ],
        ),
      ],
    );
  }
}

/// This period against the one before it.
class InsightsChangeScreen extends StatefulWidget {
  const InsightsChangeScreen({
    super.key,
    required this.viewModel,
    required this.analytics,
    required this.tones,
  });

  final SpendWiseViewModel viewModel;
  final SpendingAnalytics analytics;
  final CategoryTones tones;

  @override
  State<InsightsChangeScreen> createState() => _InsightsChangeScreenState();
}

class _InsightsChangeScreenState extends State<InsightsChangeScreen> {
  InsightsChange get _current => InsightsChange.fromId(
    widget.viewModel.uiViewPreference(InsightsPreference.change),
  );

  void _choose(InsightsChange value) {
    widget.viewModel.uiSetViewPreference(InsightsPreference.change, value.id);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final analytics = widget.analytics;
    return ChooserScreen(
      title: 'What changed',
      preview: switch (current) {
        InsightsChange.off => const _NothingDrawn(
          'Insights reports this period and does not compare it to another.',
        ),
        InsightsChange.seismograph => _SectionPreview(
          child: Seismograph(
            changes: analytics.categoryChanges,
            tones: widget.tones,
            selected: null,
            onSelect: (_) {},
            currency: analytics.currency,
          ),
        ),
        InsightsChange.gate => _SectionPreview(
          child: Gate(
            changes: analytics.categoryChanges,
            tones: widget.tones,
            sensitivity: GateSensitivity.fromId(
              widget.viewModel.uiViewPreference(
                InsightsPreference.gateSensitivity,
              ),
            ),
            totalSpendingMinor: analytics.totalSpendingMinor,
            selected: null,
            onSelect: (_) {},
            currency: analytics.currency,
          ),
        ),
      },
      children: [
        ChoiceGroup(
          label: 'Against last period',
          caption:
              'Cut to the same number of days, so an early month is not '
              'compared against a whole one.',
          first: true,
          children: [
            for (final value in InsightsChange.values)
              ChoiceRow(
                title: value.title,
                detail: value.detail,
                selected: current == value,
                onTap: () => _choose(value),
              ),
          ],
        ),
      ],
    );
  }
}

/// What an "off" preview shows: a sentence, not an empty box.
///
/// A blank preview area reads as a preview that failed to load. Saying what
/// the screen will do instead is the same amount of space doing actual work.
class _NothingDrawn extends StatelessWidget {
  const _NothingDrawn(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 236,
    width: double.infinity,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Not drawn'),
          const SizedBox(height: 10),
          Text(
            text,
            style: SpendWiseType.body.copyWith(
              fontSize: 13,
              color: SpendWiseColors.dim,
            ),
          ),
        ],
      ),
    ),
  );
}
