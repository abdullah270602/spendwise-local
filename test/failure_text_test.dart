import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/failure_text.dart';

/// Two dozen snackbars printed the caught object into the sentence they showed
/// the owner: `'Could not save transaction: $error'`. On a good day that is a
/// fragment written for a debugger; on a bad one it is `Instance of
/// 'SqliteException'`. Nobody reads a stack trace here -- this app sends no
/// crash reports anywhere by design -- so the fragment is addressed to nobody
/// and reads as the app breaking rather than the action failing.
void main() {
  group('the action is always stated', () {
    test('even when the error says nothing usable', () {
      expect(
        failureText('Could not save transaction', _Opaque()),
        startsWith('Could not save transaction.'),
      );
    });

    test('and nothing machine-written is appended to it', () {
      final text = failureText('Could not save transaction', _Opaque());
      expect(text, isNot(contains('Instance of')));
      expect(text, isNot(contains('_Opaque')));
    });
  });

  group('an error with words of its own keeps them', () {
    test('an argument the ledger refused', () {
      expect(
        failureText(
          'Could not record that',
          ArgumentError.value('', 'counterparty', 'Needs a name'),
        ),
        'Could not record that. Needs a name.',
      );
    });

    test('a state the app could not be in', () {
      expect(
        failureText('Could not open it', StateError('No browser is available')),
        'Could not open it. No browser is available.',
      );
    });

    test('a plain exception, without its class name', () {
      expect(
        failureReason(Exception('That account is already archived')),
        'That account is already archived.',
      );
    });

    test('a format the import could not read', () {
      expect(
        failureReason(const FormatException('Not a number')),
        'Not a number.',
      );
    });

    test('and it is not punctuated twice', () {
      expect(failureReason(StateError('Already done.')), 'Already done.');
    });
  });

  group('what is refused', () {
    test('a platform dump, because the brackets are not prose', () {
      expect(failureReason(_Platform()), isNull);
    });

    test('anything carrying a stack frame', () {
      expect(
        failureReason(Exception('boom\n#0 main (package:x/x.dart:1)')),
        isNull,
      );
    });

    test('a paragraph, which is a dump wearing a sentence', () {
      expect(failureReason(Exception('word ' * 40)), isNull);
    });

    test('an empty message, which says nothing at all', () {
      expect(failureReason(StateError('   ')), isNull);
      expect(failureReason(null), isNull);
    });
  });
}

class _Opaque implements Exception {}

class _Platform implements Exception {
  @override
  String toString() =>
      'PlatformException(channel-error, Unable to establish connection, null)';
}
