import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../accounts/accounts_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../insights/insights_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../review/review_inbox_screen.dart';
import '../review/review_rules.dart';
import '../transactions/ledger_screen.dart';
import '../transactions/manual_transaction_sheet.dart';
import 'spendwise_view_model.dart';

class SpendWiseShell extends StatefulWidget {
  const SpendWiseShell({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<SpendWiseShell> createState() => _SpendWiseShellState();
}

class _SpendWiseShellState extends State<SpendWiseShell> {
  int index = 0;
  late final PageController _pageController;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pages = [
      _ReactivePage(
        viewModel: widget.viewModel,
        builder: () => DashboardScreen(
          viewModel: widget.viewModel,
          onSeeLedger: () => _selectPage(1),
          onOpenAccounts: () => _selectPage(4),
        ),
      ),
      _ReactivePage(
        viewModel: widget.viewModel,
        builder: () => LedgerScreen(viewModel: widget.viewModel),
      ),
      _ReactivePage(
        viewModel: widget.viewModel,
        builder: () => ReviewInboxScreen(viewModel: widget.viewModel),
      ),
      _ReactivePage(
        viewModel: widget.viewModel,
        builder: () => InsightsScreen(viewModel: widget.viewModel),
      ),
      _ReactivePage(
        viewModel: widget.viewModel,
        builder: () => AccountsScreen(viewModel: widget.viewModel),
      ),
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.viewModel,
    builder: (context, _) {
      if (!widget.viewModel.onboardingComplete) {
        return OnboardingScreen(viewModel: widget.viewModel);
      }
      // The badge counts decisions, not alerts: fourteen unread alerts that
      // collapse into two questions is a "2", and promising fourteen would be
      // the same lie the old inbox told.
      final decisions = buildReviewRules(
        transactions: widget.viewModel.transactions,
        reviews: widget.viewModel.reviews,
        accounts: widget.viewModel.accounts,
        unroutedAlerts: widget.viewModel.uiUnroutedAlerts,
      ).length;

      return Scaffold(
        body: Stack(
          children: [
            PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: _pages,
            ),
            if (widget.viewModel.uiBusy)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (widget.viewModel.uiErrorMessage case final message?)
              Positioned(
                left: SpendWiseTheme.gutter,
                right: SpendWiseTheme.gutter,
                bottom: 12,
                child: Material(
                  color: SpendWiseColors.spend,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            message,
                            style: SpendWiseType.row.copyWith(
                              color: SpendWiseColors.bg,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: widget.viewModel.uiDismissError,
                          tooltip: 'Dismiss',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: SpendWiseColors.bg,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        floatingActionButton: index <= 1 && widget.viewModel.accounts.isNotEmpty
            ? FloatingActionButton.small(
                onPressed: () => _showManual(context),
                tooltip: 'Record something by hand',
                elevation: 0,
                shape: const RoundedRectangleBorder(),
                backgroundColor: SpendWiseColors.fg,
                foregroundColor: SpendWiseColors.bg,
                child: const Icon(Icons.add_rounded),
              )
            : null,
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: SpendWiseColors.line)),
          ),
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: _selectPage,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.change_history_outlined),
                selectedIcon: Icon(Icons.change_history_rounded),
                label: 'Home',
              ),
              const NavigationDestination(
                icon: Icon(Icons.notes_rounded),
                selectedIcon: Icon(Icons.subject_rounded),
                label: 'Ledger',
              ),
              NavigationDestination(
                icon: _DecisionIcon(count: decisions),
                selectedIcon: _DecisionIcon(count: decisions, selected: true),
                label: 'Review',
              ),
              const NavigationDestination(
                icon: Icon(Icons.ssid_chart_outlined),
                selectedIcon: Icon(Icons.ssid_chart_rounded),
                label: 'Insights',
              ),
              const NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view_rounded),
                label: 'Accounts',
              ),
            ],
          ),
        ),
      );
    },
  );

  void _selectPage(int value) {
    if (value == index) return;
    setState(() => index = value);
    _pageController.jumpToPage(value);
  }

  void _showManual(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => ManualTransactionSheet(viewModel: widget.viewModel),
  );
}

class _ReactivePage extends StatelessWidget {
  const _ReactivePage({required this.viewModel, required this.builder});

  final SpendWiseViewModel viewModel;
  final Widget Function() builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) => RepaintBoundary(child: builder()),
  );
}

class _DecisionIcon extends StatelessWidget {
  const _DecisionIcon({required this.count, this.selected = false});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      selected ? Icons.help_center_rounded : Icons.help_center_outlined,
    );
    if (count == 0) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          top: -5,
          right: -9,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            color: SpendWiseColors.spend,
            child: Text(
              count > 9 ? '9+' : '$count',
              style: const TextStyle(
                fontFamily: SpendWiseType.sans,
                fontSize: 9,
                height: 1.3,
                fontWeight: FontWeight.w700,
                color: SpendWiseColors.bg,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
