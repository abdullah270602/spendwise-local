import 'package:flutter/services.dart';

/// The one channel the Home-screen widget crosses through.
///
/// Everything named here is either a ratio (never a balance), a colour (the
/// palette a person already chose), or a flag -- nothing a stranger glancing
/// at a lock screen could turn into a figure. The native side stores exactly
/// these fields in plain `SharedPreferences`, unencrypted, because the
/// widget's process cannot open the SQLCipher ledger and there is nothing
/// here worth protecting the way the ledger itself is protected. See
/// `HomeWidgetSnapshot` for how the fraction is derived, and
/// `android/app/src/main/kotlin/com/spendwise/app/SpendWiseHomeWidgetProvider.kt`
/// for what reads this on the other side.
final class WidgetBridge {
  const WidgetBridge();

  static const _channel = MethodChannel('com.spendwise.app/home_widget');

  /// Sends the widget its next picture. Fire-and-forget: a widget that
  /// missed one publish still has the last one it drew, which is a better
  /// failure than a screen that blocks on a channel call to draw at all.
  ///
  /// [keepColor] and [spendColor] are the two tones the ribbon is currently
  /// painted in; [mineColor] joins them for the one style that draws a
  /// third branch, "saving gets its own branch" -- three tones is the whole
  /// of the app's palette choice the widget ever needs, since it draws
  /// neither the "moved between your own accounts" tone nor anything darker
  /// than that. Packed as `Color.toARGB32()` ints, the same representation
  /// `SpendWiseHomeWidgetRenderer` reads them back as on the Kotlin side.
  ///
  /// [hasSavedBranch] and [savedFraction] are sent unconditionally, like
  /// every other field here, rather than only when true -- a widget that
  /// last drew three branches and is now told to draw two needs to hear
  /// that explicitly, the same way it needs to hear a plain fraction change.
  Future<void> publish({
    required bool hasData,
    required double keptFraction,
    required bool hasSavedBranch,
    required double savedFraction,
    required int keepColor,
    required int spendColor,
    required int mineColor,
  }) => _channel.invokeMethod<void>('publish', <String, Object?>{
    'hasData': hasData,
    'keptFraction': keptFraction,
    'hasSavedBranch': hasSavedBranch,
    'savedFraction': savedFraction,
    'keepColor': keepColor,
    'spendColor': spendColor,
    'mineColor': mineColor,
  });
}
