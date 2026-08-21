import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/platform/notification_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.spendwise.app/notifications');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('decodes configured notification sources', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'listNotificationSources');
          return [
            {
              'packageName': 'pk.example.bank',
              'label': 'Example Bank',
              'configured': true,
              'lastObservedAt': 1700000000000,
            },
          ];
        });

    final sources = await const NotificationBridge().listSources();
    expect(sources.single.packageName, 'pk.example.bank');
    expect(sources.single.configured, isTrue);
    expect(sources.single.lastObservedAt, isNotNull);
  });

  test('acknowledges only the committed native queue ids', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'ackQueuedEvents');
          expect(call.arguments, {
            'ids': [3, 7],
          });
          return null;
        });

    await const NotificationBridge().acknowledge([3, 7]);
  });
}
