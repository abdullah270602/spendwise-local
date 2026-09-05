import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Two installs of the same code, side by side on one phone.
///
/// The application id is the only thing standing between a sandbox build and
/// somebody's real, encrypted ledger. If `live` ever picked up a suffix, the
/// next install would arrive as a different app: the existing one would sit
/// there orphaned, and its keystore entry would no longer match. So the id is
/// pinned here rather than trusted to whoever next edits Gradle.
void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();

  test('the live install keeps the application id it shipped with', () {
    expect(gradle, contains('applicationId = "com.spendwise.app"'));
    // Anything that would change it for the default build.
    expect(
      RegExp(r'applicationIdSuffix').allMatches(gradle).length,
      1,
      reason: 'only the sandbox flavour may shift the application id',
    );
    expect(gradle, contains('applicationIdSuffix = ".sandbox"'));
  });

  test('the sandbox is a flavour, not a build type', () {
    // A build type would ride along with debug and release and could reach a
    // published build; a flavour has to be asked for by name.
    expect(gradle, contains('flavorDimensions += "install"'));
    expect(gradle, contains('create("live")'));
    expect(gradle, contains('create("sandbox")'));
  });

  test('each install says which one it is', () {
    // Same icon, same everything inside: without distinct labels these are
    // two identical rows in the launcher.
    final live = File(
      'android/app/src/live/res/values/strings.xml',
    ).readAsStringSync();
    final sandbox = File(
      'android/app/src/sandbox/res/values/strings.xml',
    ).readAsStringSync();
    expect(live, contains('>SpendWise<'));
    expect(sandbox, contains('>SpendWise Sandbox<'));
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      contains('android:label="@string/app_name"'),
    );
  });

  test('class names in the manifest are spelled out in full', () {
    // Relative names would resolve against the sandbox application id, where
    // the classes do not exist, and the sandbox build would crash on launch.
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:name="com.spendwise.app.MainActivity"'));
    expect(
      manifest,
      contains(
        'android:name="com.spendwise.app.SpendWiseNotificationListenerService"',
      ),
    );
    expect(manifest, isNot(contains('android:name=".MainActivity"')));
  });

  test('no flavour smuggles in a permission', () {
    final flavourManifests = [
      'android/app/src/live',
      'android/app/src/sandbox',
    ].map(Directory.new).where((dir) => dir.existsSync()).expand(
      (dir) => dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('AndroidManifest.xml')),
    );
    for (final manifest in flavourManifests) {
      expect(
        manifest.readAsStringSync(),
        isNot(contains('uses-permission')),
        reason: '${manifest.path} declares a permission of its own',
      );
    }
  });
}
