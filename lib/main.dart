import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/spendwise_controller.dart';
import 'data/local_ledger.dart';
import 'app/palette.dart';
import 'app/theme.dart';
import 'features/security/lock_screen.dart';
import 'features/shell/spendwise_shell.dart';
import 'security/app_lock.dart';
import 'security/ledger_lock_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: SpendWiseColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  // Everything the app needs before it can draw anything is in here, and
  // all of it can fail: the ledger has to be found, decrypted and migrated
  // before there is a single figure to show. This used to run bare, so a
  // throw meant `runApp` was never reached at all -- a blank window, every
  // launch, with nothing on screen to say why and no way to reach a setting.
  // Whatever went wrong, saying so beats showing nothing.
  try {
    final controller = await SpendWiseController.create();
    // Before the first frame, so the app never flashes the default.
    SpendWiseColors.apply(
      SpendWisePalette.byId(controller.viewPreference('palette')),
    );
    final lock = AppLockController(
      preferences: LedgerLockPreferences(controller),
    );
    await lock.start();
    runApp(SpendWiseApp(controller: controller, lock: lock));
  } catch (error, stack) {
    debugPrint('SpendWise: could not open the ledger: $error');
    debugPrintStack(stackTrace: stack);
    runApp(LedgerUnavailableApp(error: error));
  }
}

/// The screen shown when the ledger could not be opened at all.
///
/// It exists because the alternative was nothing: startup awaited the ledger
/// before `runApp`, so anything it threw — a keystore that lost the key, a
/// build without SQLCipher, a storage directory the platform would not hand
/// over — meant no `runApp` call ever happened. The app drew a blank window,
/// on every launch, for good, with no message and no way to reach a setting.
///
/// A failure here is not necessarily damage. The ledger file is untouched by
/// any of it, so the screen says what happened, says the data is still there,
/// and offers to try again — which is the whole recovery for a transient
/// cause, and honest about the rest.
class LedgerUnavailableApp extends StatelessWidget {
  const LedgerUnavailableApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SpendWise',
    debugShowCheckedModeBanner: false,
    theme: SpendWiseTheme.dark,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SpendWiseTheme.gutter),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SpendWise could not open your ledger',
                style: SpendWiseType.title,
              ),
              const SizedBox(height: 12),
              Text(
                error is LedgerKeyMissingException
                    ? 'Your ledger is still on this device, but the key that '
                          'unlocks it is not where it was left. This can '
                          'happen after a system update or a restore onto a '
                          'new device.\n\nNothing has been changed or '
                          'deleted. SpendWise will not make a new key, '
                          'because doing that would make the ledger '
                          'unreadable for good.'
                    : 'Your ledger has not been changed or deleted. '
                          'SpendWise stopped rather than carry on without '
                          'it.',
                style: SpendWiseType.body.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 20),
              // The raw fault, verbatim. It is the only thing anybody
              // helping from outside has to go on, and hiding it would leave
              // the owner with a screen that says something went wrong and
              // no way to say what.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: SpendWiseColors.edge),
                ),
                child: SelectableText(
                  '$error',
                  style: SpendWiseType.body.copyWith(
                    fontSize: 12,
                    color: SpendWiseColors.dim,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  // A cold start is the only retry worth offering: everything
                  // that failed happened before the first frame, so there is
                  // no state here to reset and try again from.
                  onPressed: () => SystemNavigator.pop(),
                  child: const Text('Close SpendWise'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Open it again to retry. If it keeps failing, keep the '
                'message above — reinstalling erases the ledger with it.',
                style: SpendWiseType.body.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The palette is baked into ThemeData and into widgets that read the colours
/// directly, so switching it has to rebuild from the root. A ValueListenable
/// beats making every screen palette-aware for a setting changed once a year.
final paletteRevision = ValueNotifier<int>(0);

/// Bumped when the tab bar sends the user back to Home.
///
/// The shell builds every tab once in `initState` and switches between them
/// with a `PageController`, so Home's State is never recreated and nothing on
/// it replays just because the tab regained focus. This is the explicit
/// signal that lets the ribbon play its draw-in again on return, the same way
/// [paletteRevision] is the explicit signal for a re-themed root.
final homeReturnRevision = ValueNotifier<int>(0);

class SpendWiseApp extends StatelessWidget {
  const SpendWiseApp({super.key, required this.controller, required this.lock});

  final SpendWiseController controller;
  final AppLockController lock;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: paletteRevision,
    // Above MaterialApp, not inside its `home`: pushed routes are siblings of
    // home under the app's Navigator, so a scope down there is invisible to
    // every screen the user actually navigates to.
    builder: (context, _, _) => AppLockScope(
      lock: lock,
      child: MaterialApp(
        title: 'SpendWise',
        debugShowCheckedModeBanner: false,
        theme: SpendWiseTheme.dark,
        home: AppLockGate(
          lock: lock,
          child: SpendWiseShell(viewModel: controller),
        ),
      ),
    ),
  );
}

/// Puts the lock screen over the app rather than in place of it.
///
/// Replacing the shell would tear down every screen's state, so coming back
/// from a thirty-second glance at your messages would dump you on Home with
/// your place lost. The lock is opaque, so nothing shows through; what it
/// protects is the looking, and the app underneath simply stops ticking.
class AppLockGate extends StatelessWidget {
  const AppLockGate({super.key, required this.lock, required this.child});

  final AppLockController lock;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lock,
    builder: (context, _) {
      final locked = lock.locked;
      return Stack(
        children: [
          TickerMode(
            enabled: !locked,
            child: ExcludeSemantics(excluding: locked, child: child),
          ),
          if (locked) LockScreen(lock: lock),
        ],
      );
    },
  );
}
