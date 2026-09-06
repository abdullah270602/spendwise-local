import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../security/app_lock.dart';
import '../security/pin_setup_screen.dart';

/// Everything about the lock, in one place.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key, required this.lock});

  final AppLockController lock;

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  bool busy = false;

  AppLockController get lock => widget.lock;

  @override
  void initState() {
    super.initState();
    // The person may have enrolled a fingerprint since the app started.
    lock.refreshBiometricSupport();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('App lock')),
    body: ListenableBuilder(
      listenable: lock,
      builder: (context, _) => ListView(
        padding: EdgeInsets.fromLTRB(
          SpendWiseTheme.gutter,
          8,
          SpendWiseTheme.gutter,
          48 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          // No explanation of what an app lock is. Everybody knows.
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.lock_outline_rounded),
              title: const Text('Require a PIN'),
              subtitle: Text(lock.enabled ? '${lock.pinLength} digits' : 'Off'),
              value: lock.enabled,
              onChanged: busy ? null : _toggle,
            ),
          ),
          if (lock.enabled) ...[
            const SizedBox(height: 22),
            _Heading('Unlocking'),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.pin_outlined),
                    title: const Text('Change PIN'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: busy ? null : _changePin,
                  ),
                  const Divider(height: 1, indent: 56),
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint_rounded),
                    title: const Text('Fingerprint or face'),
                    subtitle: lock.biometricsAvailable
                        ? null
                        : const Text('None enrolled on this phone'),
                    value: lock.biometricsEnabled,
                    onChanged: lock.biometricsAvailable
                        ? lock.setBiometricsEnabled
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _Heading('When to ask'),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (final option in LockDelay.values) ...[
                    if (option != LockDelay.values.first)
                      const Divider(height: 1, indent: 16),
                    InkWell(
                      onTap: () => lock.setDelay(option),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(option.title, style: SpendWiseType.row),
                                  const SizedBox(height: 2),
                                  Text(
                                    option.blurb,
                                    style: SpendWiseType.body.copyWith(
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (option == lock.delay)
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
            ),
            const SizedBox(height: 22),
            _Heading('Privacy'),
            const SizedBox(height: 8),
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.visibility_off_outlined),
                title: const Text('Hide in the app switcher'),
                subtitle: const Text('Also blocks screenshots'),
                value: lock.hideInSwitcher,
                onChanged: (value) => lock.setHideInSwitcher(value),
              ),
            ),
            const SizedBox(height: 18),
            // The one fact that is not obvious and cannot be undone.
            Text(
              'A forgotten PIN cannot be recovered.',
              style: SpendWiseType.body.copyWith(fontSize: 12.5),
            ),
          ],
        ],
      ),
    ),
  );

  Future<void> _toggle(bool value) async {
    if (!value) return _disable();
    final pin = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const PinSetupScreen(title: 'Set a PIN'),
      ),
    );
    if (pin == null || !mounted) return;
    setState(() => busy = true);
    await lock.enable(pin, useBiometrics: lock.biometricsAvailable);
    if (mounted) setState(() => busy = false);
  }

  Future<void> _disable() async {
    // Proving the current PIN before removing it: otherwise the lock is
    // undone by anyone who gets past it once.
    final proved = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PinSetupScreen(
          title: 'Turn off the lock',
          prompt: 'Enter your current PIN',
          confirm: false,
          fixedLength: lock.pinLength,
          verify: lock.verify,
        ),
      ),
    );
    if (proved == null || !mounted) return;
    setState(() => busy = true);
    await lock.disable();
    if (mounted) setState(() => busy = false);
  }

  Future<void> _changePin() async {
    final proved = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PinSetupScreen(
          title: 'Change PIN',
          prompt: 'Enter your current PIN',
          confirm: false,
          fixedLength: lock.pinLength,
          verify: lock.verify,
        ),
      ),
    );
    if (proved == null || !mounted) return;
    final next = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const PinSetupScreen(
          title: 'Change PIN',
          prompt: 'Choose a new PIN',
        ),
      ),
    );
    if (next == null || !mounted) return;
    setState(() => busy = true);
    await lock.enable(next, useBiometrics: lock.biometricsEnabled);
    if (!mounted) return;
    setState(() => busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('PIN changed')));
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: SpendWiseType.eyebrow);
}
