import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/spendwise_components.dart';
import '../import/import_csv_screen.dart';
import '../shell/spendwise_view_model.dart';
import 'source_selection_screen.dart';
import 'export_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.viewModel});
  final SpendWiseViewModel viewModel;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings & privacy')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
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
        const SectionHeading('Your data'),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('Import CSV statement'),
                subtitle: const Text(
                  'Add and reconcile historical transactions',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ImportCsvScreen(viewModel: viewModel),
                  ),
                ),
              ),
              const Divider(height: 1, indent: 56),
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
        const SectionHeading('Development'),
        const SizedBox(height: 8),
        Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.science_outlined),
            title: const Text('Demo data'),
            subtitle: const Text(
              'Use clearly labelled sample transactions for previews',
            ),
            value: viewModel.uiDemoDataEnabled,
            onChanged: viewModel.uiSetDemoDataEnabled,
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
            'SpendWise · local-first finance',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
  void _confirmErase(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Erase all local data?'),
      content: const Text(
        'This permanently removes accounts, evidence, transactions, rules, and settings from this device.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: SpendWiseColors.expense,
          ),
          onPressed: () async {
            await viewModel.eraseAllData();
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
          child: const Text('Erase everything'),
        ),
      ],
    ),
  );
}
