import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/spendwise_controller.dart';
import 'package:spendwise/data/local_ledger.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.spendwise.app/notifications');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'drains a large notification backlog without losing or duplicating events',
    () async {
      final ledger = LocalLedger.openInMemoryForTests();
      final controller = SpendWiseController.forTests(ledger);
      addTearDown(controller.dispose);

      const batchSize = 250;
      final acknowledgedIds = <int>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'scanCurrentNotificationTray':
                return {
                  'status': 'completed',
                  'activeCount': batchSize,
                  'eligibleCount': batchSize,
                  'queuedCount': batchSize,
                  'duplicateCount': 0,
                  'failedCount': 0,
                };
              case 'peekQueuedEvents':
                return List.generate(
                  batchSize,
                  (i) => {
                    'id': i,
                    'packageName': 'pk.example.bank',
                    'notificationKey': 'key-$i',
                    'title': 'Debit alert',
                    'text': 'Rs. 100 debited',
                  },
                );
              case 'ackQueuedEvents':
                final ids = (call.arguments as Map)['ids'] as List;
                acknowledgedIds.addAll(ids.cast<int>());
                return null;
              case 'getNotificationIngestionHealth':
                return {
                  'notificationAccessGranted': true,
                  'listenerConnected': true,
                  'pendingCount': 0,
                  'evictedEvidenceCount': 0,
                };
              case 'listNotificationSources':
                return <Map<String, Object?>>[];
              case 'isNotificationAccessGranted':
                return true;
              default:
                return null;
            }
          });

      final result = await controller.scanNotificationTray();

      expect(result.status, NotificationTrayScanViewStatus.completed);
      expect(result.queuedCount, batchSize);
      expect(acknowledgedIds, hasLength(batchSize));
      expect(
        acknowledgedIds.toSet(),
        List.generate(batchSize, (i) => i).toSet(),
      );
    },
  );
}
