import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/spendwise_controller.dart';
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
  runApp(SpendWiseApp(controller: controller));
}

class SpendWiseApp extends StatelessWidget {
  const SpendWiseApp({super.key, required this.controller});
  final SpendWiseController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SpendWise',
    debugShowCheckedModeBanner: false,
    theme: SpendWiseTheme.dark,
    home: SpendWiseShell(viewModel: controller),
  );
}
