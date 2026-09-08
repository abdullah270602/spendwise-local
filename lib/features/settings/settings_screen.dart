import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../security/app_lock.dart';
import '../help/help_screen.dart';
import '../../app/theme.dart';
import '../../widgets/controller_scope.dart';
import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';
import 'app_lock_screen.dart';
import 'source_selection_screen.dart';
import '../reports/report_screen.dart';
import 'appearance_screen.dart';
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
  late final Future<PackageInfo> packageInfo = PackageInfo.fromPlatform();

  SpendWiseViewModel get viewModel => widget.viewModel;

  /// Both halves of the savings choice in one line, because the row has one
  /// line and hiding half the answer is how a setting becomes a surprise.
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings & privacy')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        SpendWiseTheme.gutter,
        8,
        SpendWiseTheme.gutter,
        48,
      ),
      children: [
        const PrivacyBanner(),
        const SizedBox(height: 22),
        // First, above everything a person might come here to change: the
        // place that explains what any of it does.
        SettingsRow(
          title: 'How SpendWise works',
          subtitle: 'Worked examples, step by step, and what it never does',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => HelpScreen(viewModel: viewModel),
            ),
          ),
        ),
        const SizedBox(height: 22),
        const SectionHeading('Capture'),
        const SizedBox(height: 8),
        SettingsRow(
          title: 'Notification access',
          subtitle: viewModel.notificationAccessGranted
              ? 'Enabled'
              : 'Required for automatic capture',
          trailing: TextButton(
            onPressed: viewModel.requestNotificationAccess,
            child: Text(
              viewModel.notificationAccessGranted ? 'Manage' : 'Enable',
            ),
          ),
        ),
        SettingsRow(
          title: 'Notification sources',
          subtitle:
              '${viewModel.sources.where((s) => s.enabled).length} enabled',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SourceSelectionScreen(viewModel: viewModel),
            ),
          ),
        ),
        const SizedBox(height: 22),
        const SectionHeading('Security'),
        const SizedBox(height: 8),
        Builder(
          builder: (context) {
            final lock = AppLockScope.maybeOf(context);
            return SettingsRow(
              title: 'App lock',
              subtitle: lock == null
                  ? 'Unavailable'
                  : lock.enabled
                  ? '${lock.biometricsEnabled ? 'PIN and fingerprint' : 'PIN'}'
                        ', ${lock.delay.title.toLowerCase()}'
                  : 'Off',
              onTap: lock == null
                  ? null
                  : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => AppLockScreen(lock: lock),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
            );
          },
        ),
        const SizedBox(height: 22),
        const SectionHeading('Your identity'),
        const SizedBox(height: 8),
        SettingsRow(
          title: 'Your name(s)',
          subtitle: viewModel.uiOwnNames.isEmpty
              ? 'Recognizes transfers between your own accounts'
              : viewModel.uiOwnNames.join(', '),
          onTap: _editOwnNames,
        ),
        const SizedBox(height: 22),
        const SectionHeading('Your data'),
        const SizedBox(height: 8),
        SettingsRow(
          title: 'Spending report',
          subtitle: 'A PDF of a month, a quarter, a year',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ReportScreen(viewModel: viewModel),
            ),
          ),
        ),
        SettingsRow(
          title: 'Export data',
          subtitle: 'CSV or JSON with precise filters',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ExportScreen(viewModel: viewModel),
            ),
          ),
        ),
        const SizedBox(height: 22),
        const SectionHeading('Appearance'),
        const SizedBox(height: 8),
        SettingsRow(
          title: 'How the app is drawn',
          subtitle: 'Home, Insights and the colour of everything',
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => AppearanceScreen(viewModel: viewModel),
              ),
            );
            if (mounted) setState(() {});
          },
        ),
        const SizedBox(height: 22),
        const SectionHeading('Sample data'),
        const SizedBox(height: 8),
        SettingsRow(
          title: 'Demo transactions',
          subtitle: 'Use clearly labelled sample transactions for previews',
          trailing: Switch(
            value: viewModel.uiDemoDataEnabled,
            onChanged: changingDemoData ? null : _setDemoDataEnabled,
          ),
          onTap: changingDemoData
              ? null
              : () => _setDemoDataEnabled(!viewModel.uiDemoDataEnabled),
        ),
        const SizedBox(height: 22),
        const SectionHeading('About SpendWise'),
        const SizedBox(height: 8),
        FutureBuilder<PackageInfo>(
          future: packageInfo,
          builder: (context, snapshot) {
            final info = snapshot.data;
            return SettingsRow(
              title: 'App version',
              subtitle: info == null
                  ? 'Loading version…'
                  : 'v${info.version} (${info.buildNumber})',
            );
          },
        ),
        SettingsRow(
          title: 'GitHub repository',
          subtitle: 'github.com/abdullah270602/spendwise-local',
          // A character, not a Material icon -- the same vocabulary as the
          // ⇄ transfer glyph on a ledger row, standing in for "leaves the app".
          trailing: const Text(
            '↗',
            style: TextStyle(fontSize: 15, color: SpendWiseColors.dim),
          ),
          onTap: _openRepository,
        ),
        const SizedBox(height: 22),
        const SectionHeading('Privacy controls'),
        const SizedBox(height: 8),
        SettingsRow(
          title: 'Network-free core',
          titleColor: SpendWiseColors.keep,
          subtitle: 'Ledger and reconciliation never require internet',
        ),
        SettingsRow(
          title: 'Erase all local data',
          titleColor: SpendWiseColors.spend,
          onTap: () => _confirmErase(context),
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

  Future<void> _editOwnNames() async {
    final controller = TextEditingController(
      text: viewModel.uiOwnNames.join(', '),
    );
    final entered = await showDialog<String>(
      context: context,
      builder: (dialogContext) => ControllerScope(
        controllers: [controller],
        child: AlertDialog(
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
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              // The text goes out with the pop. Reading it off the controller
              // after the await would mean reaching into a route that is on its
              // way out, which is the whole mistake this scope exists to stop.
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    // The dialog is an async gap: by the time it closes this screen may be
    // gone, and the context that was good enough to open it is not
    // automatically good enough to use again.
    if (entered != null && mounted) {
      final names = entered.split(',').map((name) => name.trim()).toList();
      // Defer past the dialog's own pop transition -- calling a mutation
      // that notifies listeners in the same frame the dialog route is still
      // unwinding is what produced the Dismissible zombie-widget bug earlier
      // in Review; the same race applies to any dialog-then-notify sequence.
      // Grabbed before the gap: after an await, reading it off a context
      // that may have gone is exactly the bug the lint is pointing at.
      final messenger = ScaffoldMessenger.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await viewModel.uiSetOwnNames(names);
        } catch (error) {
          if (mounted) {
            messenger.showSnackBar(
              SnackBar(content: Text('Could not save your name(s): $error')),
            );
          }
        }
      });
    }
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

/// One settings row, drawn the way the rest of the app draws a row: a
/// hairline underneath and nothing else. No card, no leading icon in a tinted
/// circle, no chevron glyph borrowed from Material -- the small dim mark on
/// the right, where a row opens another screen, is a character out of the
/// same drawer as the ⇄ transfer mark on a ledger row, not an Icon widget.
