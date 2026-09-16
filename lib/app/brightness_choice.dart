import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ground.dart';

/// Which ground the app draws on, as the user asked for it.
///
/// Three answers rather than two, and the third is the default. A phone
/// already knows whether it is day or night and already asks every other app
/// to agree; an app that makes you tell it separately is an app you have to
/// remember to tell twice. Light and Dark are there because "the system" is
/// sometimes not what you want in the room you are in.
enum BrightnessChoice {
  /// The default, and the only one that can change without anyone touching
  /// the app.
  system(
    'system',
    'Follow the system',
    'Whatever the phone is doing, including when it changes at dusk.',
  ),
  light('light', 'Light', 'Warm paper — the ground an exported report prints on.'),
  dark('dark', 'Dark', 'Graphite. The ground SpendWise was drawn in.');

  const BrightnessChoice(this.id, this.title, this.blurb);

  /// Stored, so it has to survive a rename of the enum member.
  final String id;
  final String title;

  /// One line in the picker.
  final String blurb;

  /// The stored view preference this is written to.
  static const preferenceKey = 'brightness';

  /// Unknown and missing both land on [system], which is what a fresh install
  /// has and what an older ledger that predates this setting has too.
  static BrightnessChoice fromId(String? id) =>
      values.firstWhere((item) => item.id == id, orElse: () => system);

  Brightness resolve(Brightness platform) => switch (this) {
    BrightnessChoice.system => platform,
    BrightnessChoice.light => Brightness.light,
    BrightnessChoice.dark => Brightness.dark,
  };

  Ground groundFor(Brightness platform) => Ground.of(resolve(platform));
}

/// The choice in force, above `MaterialApp`.
///
/// The same shape as `paletteRevision`: a setting changed once in a while,
/// read by the whole tree, and cheaper to broadcast from the root than to
/// thread through every screen. It is a `ValueNotifier` rather than a counter
/// because unlike the palette this value is also *asked for* -- the scope
/// below has to know whether the platform is still being followed.
final brightnessChoice = ValueNotifier<BrightnessChoice>(
  BrightnessChoice.system,
);

/// Resolves [brightnessChoice] against the platform, and rebuilds when either
/// of them moves.
///
/// The second half is the one worth having a widget for. A preference read at
/// launch is followed at launch; a phone that switches to its dark theme at
/// sunset while SpendWise is open in the foreground has changed the answer,
/// and an app still drawing the morning's ground has quietly stopped
/// following the setting it says it is following. `didChangePlatformBrightness`
/// is how the platform says so, and it only matters while the choice is
/// [BrightnessChoice.system] -- overriding is the whole point of the other
/// two, and an override that drifted back would be worse than no override.
class BrightnessScope extends StatefulWidget {
  const BrightnessScope({super.key, required this.builder});

  final Widget Function(BuildContext context, Ground ground) builder;

  @override
  State<BrightnessScope> createState() => _BrightnessScopeState();
}

class _BrightnessScopeState extends State<BrightnessScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (brightnessChoice.value == BrightnessChoice.system) setState(() {});
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<BrightnessChoice>(
        valueListenable: brightnessChoice,
        builder: (context, choice, _) {
          final ground = choice.groundFor(
            WidgetsBinding.instance.platformDispatcher.platformBrightness,
          );
          // The status and navigation bars are the one part of the screen
          // Flutter does not paint, so they have to be told. Annotated rather
          // than pushed through `SystemChrome` from a callback, because this
          // value is a function of the ground and nothing else, and a
          // side-effecting call is one more thing that can be made while the
          // tree says otherwise.
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: ground.bg,
              systemNavigationBarIconBrightness: ground.isLight
                  ? Brightness.dark
                  : Brightness.light,
              statusBarIconBrightness: ground.isLight
                  ? Brightness.dark
                  : Brightness.light,
              statusBarBrightness: ground.brightness,
            ),
            child: widget.builder(context, ground),
          );
        },
      );
}
