import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/spendwise_controller.dart';
import 'app/palette.dart';
import 'app/theme.dart';
import 'features/shell/spendwise_shell.dart';

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
  runApp(SpendWiseApp(controller: controller));
}

/// The palette is baked into ThemeData and into widgets that read the colours
/// directly, so switching it has to rebuild from the root. A ValueListenable
/// beats making every screen palette-aware for a setting changed once a year.
final paletteRevision = ValueNotifier<int>(0);

class SpendWiseApp extends StatelessWidget {
  const SpendWiseApp({super.key, required this.controller});
  final SpendWiseController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: paletteRevision,
    builder: (context, _, _) => MaterialApp(
      title: 'SpendWise',
      debugShowCheckedModeBanner: false,
      theme: SpendWiseTheme.dark,
      home: SpendWiseShell(viewModel: controller),
    ),
  );
}
