import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/palette.dart';
import '../../security/app_lock.dart';
import '../help/help_screen.dart';
import '../../app/theme.dart';
import '../../main.dart';
import '../../widgets/controller_scope.dart';
import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';
import 'app_lock_screen.dart';
import 'source_selection_screen.dart';
import '../reports/report_screen.dart';
import '../dashboard/home_savings.dart';
import 'home_period_screen.dart';
import 'home_savings_screen.dart';
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
        Card(
          child: ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('How SpendWise works'),
            subtitle: const Text(
              'Worked examples, step by step, and what it never does',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => HelpScreen(viewModel: viewModel),
              ),
            ),
          ),
        ),
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
        const SectionHeading('Security'),
        const SizedBox(height: 8),
        Builder(
          builder: (context) {
            final lock = AppLockScope.maybeOf(context);
            return Card(
              child: ListTile(
                leading: const Icon(Icons.lock_outline_rounded),
                title: const Text('App lock'),
                subtitle: Text(
                  lock == null
                      ? 'Unavailable'
                      : lock.enabled
                      ? '${lock.biometricsEnabled ? 'PIN and fingerprint' : 'PIN'}'
                            ', ${lock.delay.title.toLowerCase()}'
                      : 'Off',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
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
              ),
            );
          },
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
            onTap: _editOwnNames,
          ),
        ),
        const SizedBox(height: 22),
        const SectionHeading('Your data'),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Spending report'),
                subtitle: const Text('A PDF of a month, a quarter, a year'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ReportScreen(viewModel: viewModel),
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
        const SectionHeading('Home'),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.date_range_outlined),
                title: const Text('How much time Home shows'),
                subtitle: Text(viewModel.uiHomePeriod.title),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => HomePeriodScreen(viewModel: viewModel),
                    ),
                  );
                  if (mounted) setState(() {});
                },
              ),
              const Divider(height: 1, indent: 56),
              // A switch could only ever ask "on or off", and there are two
              // different questions here -- what you put away over the period,
              // and what you hold. So it opens a choice that names them.
              ListTile(
                leading: const Icon(Icons.savings_outlined),
                title: const Text('How Home counts savings'),
                subtitle: Text(
                  HomeSavingsStyle.fromId(
                    viewModel.uiViewPreference('home_savings'),
                    legacyOn: viewModel.uiShowSavingsOnHome,
                  ).title,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => HomeSavingsScreen(viewModel: viewModel),
                    ),
                  );
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const SectionHeading('Colour'),
        const SizedBox(height: 8),
        _PalettePicker(viewModel: viewModel),
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
              ListTile(
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
                leading: Icon(
                  Icons.delete_forever_outlined,
                  color: SpendWiseColors.expense,
                ),
                title: Text(
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

/// Five palettes, not a colour wheel. The ground, the type and the layout are
/// the app's identity; what a person gets to choose is the temperament of the
/// three colours that carry meaning. Every option is checked against the same
/// dark ground, so none of them can make the app look worse than the default.
class _PalettePicker extends StatefulWidget {
  const _PalettePicker({required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<_PalettePicker> createState() => _PalettePickerState();
}

class _PalettePickerState extends State<_PalettePicker> {
  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        for (final palette in SpendWisePalette.all) ...[
          if (palette != SpendWisePalette.all.first)
            const Divider(height: 1, indent: 16),
          InkWell(
            onTap: () => _choose(palette),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
              child: Row(
                children: [
                  _Swatch(palette: palette),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(palette.name, style: SpendWiseType.row),
                        const SizedBox(height: 2),
                        Text(
                          palette.blurb,
                          style: SpendWiseType.body.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (palette.id == SpendWiseColors.palette.id)
                    Text(
                      '✓',
                      style: TextStyle(
                        color: SpendWiseColors.keep,
                        fontSize: 16,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );

  void _choose(SpendWisePalette palette) {
    if (palette.id == SpendWiseColors.palette.id) return;
    SpendWiseColors.apply(palette);
    widget.viewModel.uiSetViewPreference('palette', palette.id);
    // Repaint from the root: ThemeData itself carries these colours.
    paletteRevision.value++;
    setState(() {});
  }
}

/// The three tones that carry meaning, in the order the app uses them:
/// kept, moved between your own accounts, gone.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.palette});

  final SpendWisePalette palette;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 46,
    height: 26,
    // Stretch, or a childless ColoredBox inside Expanded gets a tight width
    // and zero height, and the swatch renders as nothing at all.
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 5, child: ColoredBox(color: palette.keep)),
        Expanded(flex: 2, child: ColoredBox(color: palette.mine)),
        Expanded(flex: 3, child: ColoredBox(color: palette.spend)),
      ],
    ),
  );
}
