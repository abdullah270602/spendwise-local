/// What to put in front of somebody when something failed.
///
/// Two dozen snackbars interpolated the caught object straight into their
/// message -- `'Could not save transaction: $error'` -- which on a good day
/// prints `Invalid argument (amount): Needs a figure: null` and on a bad one
/// prints `Instance of 'SqliteException'` or a bracketed platform dump. None
/// of that is addressed to the person holding the phone: it is addressed to
/// whoever reads the stack trace, and there is nobody, because this app sends
/// no crash reports anywhere by design.
///
/// So the rule here is narrow. Keep the sentence the app itself wrote -- the
/// action that failed, which is always true and always useful -- and add the
/// error's own words only when they read as words. When they do not, say
/// plainly that there is nothing more to tell rather than handing over a
/// fragment of a stack trace as if it were an explanation.
library;

/// Markers of a string written for a debugger rather than a person. Any one of
/// them disqualifies the whole candidate: a message that has to be explained
/// is worse than no message, because it reads as the app breaking rather than
/// the action failing.
const _machineMarkers = [
  'Instance of',
  '#0',
  'package:',
  'dart:',
  'Exception(',
  'Error(',
  '<asynchronous',
];

/// The longest a reason can be and still be read at a glance in a snackbar
/// that dismisses itself. Anything longer is a dump, not a sentence.
const _reasonLimit = 120;

/// `action` is what the app was doing, written as a sentence without its full
/// stop: `'Could not save transaction'`. It is never dropped, because it is
/// the one part that is certainly true.
String failureText(String action, Object? error) {
  final reason = failureReason(error);
  return reason == null
      ? '$action. Something went wrong, and it did not say what.'
      : '$action. $reason';
}

/// The error's own words, if it has any fit to show. Null when it has none.
///
/// Exposed separately so a screen that words its own failure can still ask
/// whether there is anything worth appending.
String? failureReason(Object? error) {
  final raw = _words(error);
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length > _reasonLimit) return null;
  if (trimmed.contains('\n')) return null;
  for (final marker in _machineMarkers) {
    if (trimmed.contains(marker)) return null;
  }
  // Written as a sentence: these arrive as fragments -- `Needs a name` --
  // because they were written to sit after a colon in a debugger.
  final sentence = trimmed[0].toUpperCase() + trimmed.substring(1);
  return sentence.endsWith('.') ||
          sentence.endsWith('!') ||
          sentence.endsWith('?')
      ? sentence
      : '$sentence.';
}

/// The message an error carries, before it is judged. Written as a chain of
/// checks rather than a switch on types because `UnimplementedError`
/// implements `UnsupportedError` and `RangeError` extends `ArgumentError`:
/// order matters, and a switch hides which branch a subclass lands in.
String? _words(Object? error) {
  if (error == null) return null;
  if (error is String) return error;
  if (error is ArgumentError) {
    final message = error.message;
    return message is String ? message : null;
  }
  if (error is StateError) return error.message;
  if (error is FormatException) return error.message;
  if (error is UnsupportedError) return error.message;
  return _fromToString(error);
}

/// `Exception('No browser is available')` prints as `Exception: No browser is
/// available`, and that prefix is the only readable shape a bare `toString`
/// reliably has. Everything else -- a platform exception's bracketed tuple, a
/// database error's code -- is rejected by the checks above.
String? _fromToString(Object error) {
  final text = error.toString();
  const prefix = 'Exception: ';
  return text.startsWith(prefix) ? text.substring(prefix.length) : null;
}
