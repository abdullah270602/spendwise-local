import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../accounts/accounts_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../review/review_inbox_screen.dart';
import '../settings/settings_screen.dart';
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
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.viewModel,
    builder: (context, _) {
      if (!widget.viewModel.onboardingComplete) {
        return OnboardingScreen(viewModel: widget.viewModel);
      }
      final pages = <Widget>[
        DashboardScreen(
          viewModel: widget.viewModel,
          onSeeLedger: () => setState(() => index = 1),
          onOpenSettings: () => setState(() => index = 4),
          onOpenAccounts: () => setState(() => index = 3),
        ),
        LedgerScreen(viewModel: widget.viewModel),
        ReviewInboxScreen(viewModel: widget.viewModel),
        AccountsScreen(viewModel: widget.viewModel),
        SettingsScreen(viewModel: widget.viewModel),
      ];
      return Scaffold(
        body: Stack(
          children: [
            IndexedStack(index: index, children: pages),
            if (widget.viewModel.uiBusy)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (widget.viewModel.uiErrorMessage case final message?)
              Positioned(
                left: 14,
                right: 14,
                bottom: 10,
                child: Material(
                  color: SpendWiseColors.expense,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded),
                        const SizedBox(width: 10),
                        Expanded(child: Text(message)),
                        IconButton(
                          onPressed: widget.viewModel.uiDismissError,
                          tooltip: 'Dismiss error',
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        floatingActionButton: index <= 1 && widget.viewModel.accounts.isNotEmpty
            ? FloatingActionButton(
                onPressed: () => _showManual(context),
                tooltip: 'Add transaction',
                backgroundColor: SpendWiseColors.accent,
                foregroundColor: SpendWiseColors.background,
                child: const Icon(Icons.add_rounded),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (v) => setState(() => index = v),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            const NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Ledger',
            ),
            NavigationDestination(
              icon: _ReviewIcon(count: widget.viewModel.reviews.length),
              selectedIcon: _ReviewIcon(
                count: widget.viewModel.reviews.length,
                selected: true,
              ),
              label: 'Review',
            ),
            const NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet_rounded),
              label: 'Accounts',
            ),
            const NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      );
    },
  );

  void _showManual(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => ManualTransactionSheet(viewModel: widget.viewModel),
  );
}

class _ReviewIcon extends StatelessWidget {
  const _ReviewIcon({required this.count, this.selected = false});
  final int count;
  final bool selected;
  @override
  Widget build(BuildContext context) => Badge(
    isLabelVisible: count > 0,
    label: Text(count > 99 ? '99+' : '$count'),
    child: Icon(
      selected ? Icons.fact_check_rounded : Icons.fact_check_outlined,
    ),
  );
}
