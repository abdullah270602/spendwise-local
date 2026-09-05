import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';
import 'source_selection_screen.dart';
import 'export_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.viewModel});
  final SpendWiseViewModel viewModel;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static final Uri _repositoryUri = Uri.parse(
    'https://github.com/abdullah270602/spendwise-local',
  );

  bool changingDemoData = false;
  bool changingSavingsVisibility = false;
  late final Future<PackageInfo> packageInfo = PackageInfo.fromPlatform();

  SpendWiseViewModel get viewModel => widget.viewModel;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings & privacy')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(SpendWiseTheme.gutter, 8, SpendWiseTheme.gutter, 48),
      children: [
        const PrivacyBanner(),
        const SizedBox(height: 22),
        const SectionHeading('Capture'),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Notification access'),
                subtitle: Text(
                  viewModel.notificationAccessGranted
                      ? 'Enabled'
                      : 'Required for automatic capture',
                ),
                trailing: TextButton(
                  onPressed: viewModel.requestNotificationAccess,
                  child: Text(
                    viewModel.notificationAccessGranted ? 'Manage' : 'Enable',
                  ),
                ),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.apps_rounded),
                title: const Text('Notification sources'),
                subtitle: Text(
                  '${viewModel.sources.where((s) => s.enabled).length} enabled',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SourceSelectionScreen(viewModel: viewModel),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const SectionHeading('Your identity'),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Your name(s)'),
            subtitle: Text(
              viewModel.uiOwnNames.isEmpty
                  ? 'Recognizes transfers between your own accounts'
                  : viewModel.uiOwnNames.join(', '),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _editOwnNames(context),
          ),
        ),
        const SizedBox(height: 22),
        const SectionHeading('Your data'),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Export data'),
                subtitle: const Text('CSV or JSON with precise filters'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ExportScreen(viewModel: viewModel),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const SectionHeading('Home'),
        const SizedBox(height: 8),
        Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.savings_outlined),
            title: const Text('Show savings on Home'),
            subtitle: const Text(
              'Savings always remain available in Accounts and Insights',
            ),
            value: viewModel.uiShowSavingsOnHome,
            onChanged: changingSavingsVisibility ? null : _setSavingsVisibility,
          ),
        ),
        const SizedBox(height: 22),
        const SectionHeading('Sample data'),
        const SizedBox(height: 8),
        Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.science_outlined),
            title: const Text('Demo transactions'),
            subtitle: const Text(
              'Use clearly labelled sample transactions for previews',
            ),
            value: viewModel.uiDemoDataEnabled,
            onChanged: changingDemoData ? null : _setDemoDataEnabled,
          ),
        ),
        const SizedBox(height: 22),
        const SectionHeading('About SpendWise'),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              FutureBuilder<PackageInfo>(
                future: packageInfo,
                builder: (context, snapshot) {
                  final info = snapshot.data;
                  return ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: const Text('App version'),
                    subtitle: Text(
                      info == null
                          ? 'Loading version…'
                          : 'v${info.version} (${info.buildNumber})',
                    ),
                  );
                },
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.code_rounded),
                title: const Text('GitHub repository'),
                subtitle: const Text(
                  'github.com/abdullah270602/spendwise-local',
                ),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: _openRepository,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const SectionHeading('Privacy controls'),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              const ListTile(
                leading: Icon(
                  Icons.wifi_off_rounded,
                  color: SpendWiseColors.accent,
                ),
                title: Text('Network-free core'),
                subtitle: Text(
                  'Ledger and reconciliation never require internet',
                ),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(
                  Icons.delete_forever_outlined,
                  color: SpendWiseColors.expense,
                ),
                title: const Text(
                  'Erase all local data',
                  style: TextStyle(color: SpendWiseColors.expense),
                ),
                onTap: () => _confirmErase(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'SpendWise · Private. Local. Yours.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );

  Future<void> _openRepository() async {
    try {
      final opened = await launchUrl(
        _repositoryUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('No browser is available');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the GitHub repository')),
      );
    }
  }

  Future<void> _setDemoDataEnabled(bool enabled) async {
    setState(() => changingDemoData = true);
    try {
      await viewModel.uiSetDemoDataEnabled(enabled);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update sample data: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => changingDemoData = false);
    }
  }

  Future<void> _setSavingsVisibility(bool enabled) async {
    setState(() => changingSavingsVisibility = true);
    try {
      await viewModel.uiSetShowSavingsOnHome(enabled);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update Home: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => changingSavingsVisibility = false);
    }
  }

  Future<void> _editOwnNames(BuildContext context) async {
    final controller = TextEditingController(
      text: viewModel.uiOwnNames.join(', '),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your name(s)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'As they appear in bank or wallet SMS/notifications, e.g. '
              '"YOUR FULL NAME". Used only to recognize transfers between '
              'your own accounts — separate multiple names with commas.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Your Name, Y. Name',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      final names = controller.text
          .split(',')
          .map((name) => name.trim())
          .toList();
      // Defer past the dialog's own pop transition -- calling a mutation
      // that notifies listeners in the same frame the dialog route is still
      // unwinding is what produced the Dismissible zombie-widget bug earlier
      // in Review; the same race applies to any dialog-then-notify sequence.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await viewModel.uiSetOwnNames(names);
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not save your name(s): $error')),
            );
          }
        }
      });
    }
    controller.dispose();
  }

  Future<void> _confirmErase(BuildContext context) async {
    var erasing = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Erase all local data?'),
          content: const Text(
            'This permanently removes accounts, evidence, transactions, rules, and settings from this device.',
          ),
          actions: [
            TextButton(
              onPressed: erasing ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: SpendWiseColors.expense,
              ),
              onPressed: erasing
                  ? null
                  : () async {
                      setDialogState(() => erasing = true);
                      try {
                        await viewModel.eraseAllData();
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          setDialogState(() => erasing = false);
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(
                              content: Text('Could not erase data: $error'),
                            ),
                          );
                        }
                      }
                    },
              child: Text(erasing ? 'Erasing…' : 'Erase everything'),
            ),
          ],
        ),
      ),
    );
  }
}
