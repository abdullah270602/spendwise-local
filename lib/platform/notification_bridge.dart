import 'package:flutter/services.dart';

final class NotificationIngestionHealth {
  const NotificationIngestionHealth({
    required this.accessGranted,
    required this.listenerConnected,
    required this.pendingCount,
    required this.evictedCount,
    this.lastCaptureAt,
  });

  final bool accessGranted;
  final bool listenerConnected;
  final int pendingCount;
  final int evictedCount;
  final DateTime? lastCaptureAt;
}

enum NotificationTrayScanStatus {
  completed,
  accessRequired,
  listenerUnavailable,
}

final class NotificationTrayScanResult {
  const NotificationTrayScanResult({
    required this.status,
    this.activeCount = 0,
    this.eligibleCount = 0,
    this.queuedCount = 0,
    this.duplicateCount = 0,
    this.failedCount = 0,
  });

  final NotificationTrayScanStatus status;
  final int activeCount;
  final int eligibleCount;
  final int queuedCount;
  final int duplicateCount;
  final int failedCount;
}

final class NotificationSource {
  const NotificationSource({
    required this.packageName,
    required this.label,
    required this.configured,
    this.lastObservedAt,
    this.observationCount = 0,
    this.iconPng,
    this.installed = true,
    this.enabled = true,
    this.listenerConnected = false,
  });

  final String packageName;
  final String label;
  final bool configured;
  final DateTime? lastObservedAt;
  final int observationCount;
  final Uint8List? iconPng;
  final bool installed;
  final bool enabled;
  final bool listenerConnected;
}

final class NotificationBridge {
  const NotificationBridge();

  static const _channel = MethodChannel('com.spendwise.app/notifications');

  Future<bool> hasAccess() async =>
      await _channel.invokeMethod<bool>('isNotificationAccessGranted') ?? false;

  Future<void> openAccessSettings() =>
      _channel.invokeMethod<void>('openNotificationAccessSettings');

  Future<List<NotificationSource>> listSources() async {
    final rows =
        await _channel.invokeListMethod<Object?>('listNotificationSources') ??
        const [];
    return rows
        .map((value) {
          final row = Map<Object?, Object?>.from(value! as Map);
          final observed = (row['lastObservedAt'] as num?)?.toInt();
          final health = row['health'] is Map
              ? Map<Object?, Object?>.from(row['health']! as Map)
              : const <Object?, Object?>{};
          return NotificationSource(
            packageName: row['packageName']! as String,
            label: row['label']! as String,
            configured: row['configured'] == true,
            lastObservedAt: observed == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(observed, isUtc: true),
            observationCount: (row['observationCount'] as num?)?.toInt() ?? 0,
            iconPng: row['iconPng'] as Uint8List?,
            installed: health['installed'] != false,
            enabled: health['enabled'] != false,
            listenerConnected: health['listenerConnected'] == true,
          );
        })
        .toList(growable: false);
  }

  Future<void> setSources(Iterable<String> packageNames) =>
      _channel.invokeMethod<void>('setNotificationSources', {
        'packageNames': packageNames.toList(growable: false),
      });

  Future<Set<String>> setSourceEnabled(String packageName, bool enabled) async {
    final configured = await _channel.invokeListMethod<String>(
      'setNotificationSourceEnabled',
      {'packageName': packageName, 'enabled': enabled},
    );
    return (configured ?? const <String>[]).toSet();
  }

  Future<List<Map<String, Object?>>> peek({int limit = 500}) async {
    final rows =
        await _channel.invokeListMethod<Object?>('peekQueuedEvents', {
          'limit': limit,
        }) ??
        const [];
    return rows
        .map((value) => Map<String, Object?>.from(value! as Map))
        .toList(growable: false);
  }

  Future<void> acknowledge(Iterable<int> ids) => _channel.invokeMethod<void>(
    'ackQueuedEvents',
    {'ids': ids.toList(growable: false)},
  );

  Future<void> clear() => _channel.invokeMethod<void>('clearNotificationData');

  Future<NotificationTrayScanResult> scanCurrentTray() async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'scanCurrentNotificationTray',
    );
    final row = raw ?? const <Object?, Object?>{};
    final status = switch (row['status']) {
      'completed' => NotificationTrayScanStatus.completed,
      'accessRequired' => NotificationTrayScanStatus.accessRequired,
      'listenerUnavailable' => NotificationTrayScanStatus.listenerUnavailable,
      _ => throw const FormatException(
        'Android returned an invalid tray scan result.',
      ),
    };
    return NotificationTrayScanResult(
      status: status,
      activeCount: (row['activeCount'] as num?)?.toInt() ?? 0,
      eligibleCount: (row['eligibleCount'] as num?)?.toInt() ?? 0,
      queuedCount: (row['queuedCount'] as num?)?.toInt() ?? 0,
      duplicateCount: (row['duplicateCount'] as num?)?.toInt() ?? 0,
      failedCount: (row['failedCount'] as num?)?.toInt() ?? 0,
    );
  }

  Future<NotificationIngestionHealth> health() async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'getNotificationIngestionHealth',
    );
    final row = raw ?? const <Object?, Object?>{};
    final captured = (row['lastCaptureAt'] as num?)?.toInt();
    return NotificationIngestionHealth(
      accessGranted: row['notificationAccessGranted'] == true,
      listenerConnected: row['listenerConnected'] == true,
      pendingCount: (row['pendingCount'] as num?)?.toInt() ?? 0,
      evictedCount: (row['evictedEvidenceCount'] as num?)?.toInt() ?? 0,
      lastCaptureAt: captured == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(captured, isUtc: true),
    );
  }
}
