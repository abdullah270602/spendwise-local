import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/spendwise_controller.dart';
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
}

/// The palette is baked into ThemeData and into widgets that read the colours
/// directly, so switching it has to rebuild from the root. A ValueListenable
/// beats making every screen palette-aware for a setting changed once a year.
final paletteRevision = ValueNotifier<int>(0);

class SpendWiseApp extends StatelessWidget {
  const SpendWiseApp({
    super.key,
    required this.controller,
    required this.lock,
  });

  final SpendWiseController controller;
  final AppLockController lock;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: paletteRevision,
    builder: (context, _, _) => MaterialApp(
      title: 'SpendWise',
      debugShowCheckedModeBanner: false,
      theme: SpendWiseTheme.dark,
      home: AppLockScope(
        lock: lock,
        child: AppLockGate(
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
