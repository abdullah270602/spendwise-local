import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Turning a PIN into something safe to store.
///
/// A PIN is not a password: four digits is ten thousand guesses, and no
/// iteration count survives that if an attacker can try them offline. So the
/// real defences are elsewhere -- the hash lives inside the SQLCipher database
/// whose key is held by the Android keystore, and wrong attempts are rate
/// limited by a lockout that survives killing the app. Stretching is the last
/// layer, not the first: enough to make even an offline sweep cost real time,
/// cheap enough that unlocking never feels like waiting.
class PinHash {
  const PinHash({
    required this.iterations,
    required this.salt,
    required this.key,
  });

  final int iterations;
  final Uint8List salt;
  final Uint8List key;

  /// The cost is stored with the hash rather than hard-coded, so raising it
  /// later re-verifies old PINs at their own cost instead of locking people
  /// out of their own ledger.
  static const defaultIterations = 60000;
  static const _saltBytes = 32;
  static const _keyBytes = 32;

  static final _random = Random.secure();

  /// Derives a fresh hash with a new random salt.
  static PinHash create(String pin, {int iterations = defaultIterations}) {
    final salt = Uint8List.fromList(
      List<int>.generate(_saltBytes, (_) => _random.nextInt(256)),
    );
    return PinHash(
      iterations: iterations,
      salt: salt,
      key: pbkdf2(
        password: utf8.encode(pin),
        salt: salt,
        iterations: iterations,
        length: _keyBytes,
      ),
    );
  }

  /// True when [pin] derives this same key. The comparison is constant time:
  /// a fast "wrong" and a slow "wrong" are two different answers.
  bool matches(String pin) {
    final candidate = pbkdf2(
      password: utf8.encode(pin),
      salt: salt,
      iterations: iterations,
      length: key.length,
    );
    return constantTimeEquals(candidate, key);
  }

  /// A single self-describing line, so a future format change is detectable
  /// rather than silently misread.
  String encode() =>
      'pbkdf2-sha256:$iterations:${base64Encode(salt)}:${base64Encode(key)}';

  static PinHash? decode(String? stored) {
    if (stored == null) return null;
    final parts = stored.split(':');
    if (parts.length != 4 || parts[0] != 'pbkdf2-sha256') return null;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations < 1) return null;
    try {
      return PinHash(
        iterations: iterations,
        salt: base64Decode(parts[2]),
        key: base64Decode(parts[3]),
      );
    } on FormatException {
      return null;
    }
  }
}

/// PBKDF2-HMAC-SHA256, RFC 8018 section 5.2.
Uint8List pbkdf2({
  required List<int> password,
  required List<int> salt,
  required int iterations,
  int length = 32,
}) {
  final hmac = Hmac(sha256, password);
  final out = Uint8List(length);
  final blockSize = sha256.blockSize == 0 ? 32 : 32;
  var written = 0;
  var blockIndex = 1;

  while (written < length) {
    // U1 = PRF(P, S || INT_32_BE(i))
    final seed = Uint8List(salt.length + 4)
      ..setRange(0, salt.length, salt)
      ..buffer.asByteData().setUint32(salt.length, blockIndex);
    var u = Uint8List.fromList(hmac.convert(seed).bytes);
    final accumulator = Uint8List.fromList(u);
    for (var round = 1; round < iterations; round++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var i = 0; i < accumulator.length; i++) {
        accumulator[i] ^= u[i];
      }
    }
    final take = min(blockSize, length - written);
    out.setRange(written, written + take, accumulator);
    written += take;
    blockIndex++;
  }
  return out;
}

/// Compares two byte strings without leaking where they first differ.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}
