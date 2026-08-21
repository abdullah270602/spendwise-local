import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifests preserve the local-only privacy boundary', () {
    final manifests = [
      'android/app/src/main/AndroidManifest.xml',
      'android/app/src/debug/AndroidManifest.xml',
      'android/app/src/profile/AndroidManifest.xml',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(manifests, isNot(contains('android.permission.INTERNET')));
    expect(manifests, contains('android:allowBackup="false"'));
    expect(manifests, contains('android:usesCleartextTraffic="false"'));
    expect(
      manifests,
      contains('android.permission.BIND_NOTIFICATION_LISTENER_SERVICE'),
    );
  });
}
