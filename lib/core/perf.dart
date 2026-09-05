import 'package:flutter/foundation.dart';

/// Debug-only timing for startup and ledger hot paths.
///
/// Guarded on [kDebugMode] so release builds pay nothing: the stopwatch is
/// never constructed and the branch folds away. Labels are printed with a
/// stable prefix so a run can be filtered out of logcat.
T timed<T>(String label, T Function() body) {
  if (!kDebugMode) return body();
  final watch = Stopwatch()..start();
  try {
    return body();
  } finally {
    watch.stop();
    debugPrint('SpendWisePerf: $label ${watch.elapsedMicroseconds / 1000}ms');
  }
}

Future<T> timedAsync<T>(String label, Future<T> Function() body) async {
  if (!kDebugMode) return body();
  final watch = Stopwatch()..start();
  try {
    return await body();
  } finally {
    watch.stop();
    debugPrint('SpendWisePerf: $label ${watch.elapsedMicroseconds / 1000}ms');
  }
}
