import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.viewModel});
  final SpendWiseViewModel viewModel;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int page = 0;
  bool busy = false;
  static const pages = [
    (
      Icons.receipt_long_rounded,
      'One trustworthy ledger',
      'Notifications, imports, and manual entries are evidence. SpendWise reconciles them into real transactions.',
    ),
    (
      Icons.auto_awesome_motion_rounded,
      'Duplicates become context',
      'Matching amounts, time windows, accounts, and references help identify transfers and repeated observations.',
    ),
    (
      Icons.shield_outlined,
      'Private by design',
      'Everything works locally. Your notification contents and financial history remain on your phone.',
    ),
  ];

  Future<void> _continue() async {
    if (page < pages.length - 1) {
      setState(() => page++);
      return;
    }
    setState(() => busy = true);
    try {
      await widget.viewModel.completeOnboarding();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not finish setup: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = pages[page];
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: SpendWiseColors.accent,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: SpendWiseColors.background,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'SpendWise',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Column(
                  key: ValueKey(page),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: SpendWiseColors.accentMuted,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Icon(
                        item.$1,
                        color: SpendWiseColors.accent,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      item.$2,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      item.$3,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 16,
                        color: SpendWiseColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (page == 2) const PrivacyBanner(),
              const SizedBox(height: 26),
              Row(
                children: List.generate(
                  pages.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 7),
                    width: i == page ? 24 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == page
                          ? SpendWiseColors.accent
                          : SpendWiseColors.border,
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy ? null : _continue,
                  child: Text(page == 2 ? 'Start privately' : 'Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
