/// Notifications that are furniture, not events.
///
/// Android makes an app that works in the background post a permanent notice
/// saying so — "Messages is doing work in the background". It is not a
/// message, it reports nothing, and it never becomes a transaction. Asking
/// the user about it is asking them to do the operating system's paperwork,
/// and because Android re-posts it, the same non-question came back however
/// many times it was dismissed.
///
/// These are dropped at capture rather than parsed and filed away, because
/// there is nothing to keep: a foreground-service notice has no content that
/// would ever be worth re-reading.
library;

/// Whether this envelope is a persistent system or service notice.
bool isBackgroundServiceNotice(Map<String, Object?> envelope) {
  final status = envelope['statusBarNotification'];
  if (status is Map) {
    // `ongoing` is the flag Android sets on a notification the user is not
    // meant to dismiss: foreground services, media transports, ongoing calls.
    // A bank never posts a transaction alert this way — an alert reports
    // something that already finished.
    if (status['ongoing'] == true) return true;
  }

  // Set explicitly by the platform for a running background service, and by
  // apps for a determinate progress bar (a download, a sync, an upload).
  const furniture = {'service', 'progress', 'sys', 'transport'};
  final category = envelope['category'];
  if (category is String && furniture.contains(category.toLowerCase())) {
    return true;
  }
  return false;
}
