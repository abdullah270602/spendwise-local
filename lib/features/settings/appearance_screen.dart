import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/spendwise_components.dart';
import '../dashboard/home_categories.dart';
import '../dashboard/home_savings.dart';
import '../insights/insights_layout.dart';
import '../insights/insights_sections_screen.dart';
import '../insights/spending_analytics.dart';
import '../shell/spendwise_view_model.dart';
import 'home_categories_screen.dart';
import 'home_period_screen.dart';
import 'home_savings_screen.dart';
import 'palette_screen.dart';

/// One door back to every question about how a screen is drawn.
///
/// These choices belong on the screens they change — you should be able to
/// decide how Insights draws its categories while standing on Insights,
/// watching it change, rather than in front of a picture of it. But a control
/// that only exists on its own screen is a control most people never find, and
/// Settings had grown a section per screen besides, which does not scale past
/// the second screen that wants an option.
///
/// So both: the controls live where they act, and this is the way in for
/// anyone who came looking in Settings, which is where people look.
class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  SpendWiseViewModel get viewModel => widget.viewModel;

  Future<void> _open(Widget screen) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    if (mounted) setState(() {});
  }

  /// The three answers in one line, so the tile says what is on without
  /// making anyone open it to find out.
  String get _insightsSummary {
    final parts = <String>[
      if (InsightsOverTime.fromId(
        viewModel.uiViewPreference(InsightsPreference.overTime),
      ).isOn)
        'Over time',
      if (InsightsShare.fromId(
            viewModel.uiViewPreference(InsightsPreference.share),
          )
          case final share when share.isOn)
        share.title,
      if (InsightsChange.fromId(
            viewModel.uiViewPreference(InsightsPreference.change),
          )
          case final change when change.isOn)
        change.title,
    ];
    return parts.isEmpty ? 'Nothing but the figures' : parts.join('  ·  ');
  }

  String get _savingsSummary {
    final style = HomeSavingsStyle.fromId(
      viewModel.uiViewPreference('home_savings'),
    );
    final extra = HomeSavingsExtra.resolve(
      viewModel.uiViewPreference('home_savings_extra'),
      viewModel.uiViewPreference('home_savings'),
      legacyOn: viewModel.uiShowSavingsOnHome,
    );
    if (extra == HomeSavingsExtra.none) return style.title;
    return '${style.title}  ·  ${extra.title}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Appearance')),
    body: ListView(
      padding: EdgeInsets.fromLTRB(
        SpendWiseTheme.gutter,
        18,
        SpendWiseTheme.gutter,
        32 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [
        const SectionHeading('Home'),
        const SizedBox(height: 8),
        SettingsRow(
          title: 'How much time Home shows',
          subtitle: viewModel.uiHomePeriod.title,
          onTap: () => _open(HomePeriodScreen(viewModel: viewModel)),
        ),
        SettingsRow(
          title: 'Savings on Home',
          subtitle: _savingsSummary,
          onTap: () => _open(HomeSavingsScreen(viewModel: viewModel)),
        ),
        SettingsRow(
          title: 'Categories on Home',
          subtitle: HomeCategories.fromId(
            viewModel.uiViewPreference('home_categories'),
          ).title,
          onTap: () => _open(HomeCategoriesScreen(viewModel: viewModel)),
        ),
        const SizedBox(height: 22),
        const SectionHeading('Insights'),
        const SizedBox(height: 8),
        SettingsRow(
          title: 'What Insights shows',
          subtitle: _insightsSummary,
          onTap: () => _open(
            InsightsSectionsScreen(
              viewModel: viewModel,
              // Settings has no period of its own to offer, so the previews
              // are drawn for the month, which is what Insights itself
              // opens on.
              resolution: AnalyticsResolution.thisMonth,
            ),
          ),
        ),
        const SizedBox(height: 22),
        // Not under Home. Colour repaints every screen in the app, and it sat
        // in the Home section only because that was the section that existed.
        const SectionHeading('Everywhere'),
        const SizedBox(height: 8),
        SettingsRow(
          title: 'Colour',
          subtitle: SpendWiseColors.palette.name,
          onTap: () => _open(PaletteScreen(viewModel: viewModel)),
        ),
      ],
    ),
  );
}

/// A choice-summary row: what the setting is, and the one line answering it,
/// with the same hairline-and-nothing-else drawing every other row in the
/// app uses. The old ListTile card gave every one of these a rounded, raised
/// panel and a Material leading icon that no other settings row in this
/// redraw carries -- dropped so this reads as one more row in the list Home,
/// Ledger and Accounts already use, not a different product's screen.
