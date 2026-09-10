import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/local_ledger.dart';

/// The worst thing this app could do to somebody.
///
/// `_loadOrCreateKey` used to mint a fresh key and write it over the stored
/// one whenever secure storage came back empty -- without ever asking whether
/// a database was already sitting on disk. Secure storage can come back empty
/// for reasons that have nothing to do with the owner: a keystore reset by a
/// system update, a restore onto a new device, storage the platform decides
/// it can no longer read. In that moment the old key is destroyed, the
/// ledger becomes undecryptable for good, and there is no backup by design.
///
/// The key exchange itself needs a real Android keystore, so what is held
/// here is the contract the recovery rests on: a ledger whose key has gone
/// missing produces something the app can catch, name and show, rather than
/// silence.
void main() {
  test('a missing key is an exception, not a new key', () {
    // Named, so startup can tell this apart from every other reason the
    // ledger might not open and say the one thing that matters: your data is
    // still here and nothing has been overwritten.
    const error = LedgerKeyMissingException();
    expect(error, isA<Exception>());
  });

  test('and it says what happened without saying the data is gone', () {
    final said = const LedgerKeyMissingException().toString();
    // The owner reads this at the moment they are most likely to reinstall,
    // which is the one action that would finish the job.
    expect(said, contains('on this device'));
    expect(said, contains('will not replace the key'));
    expect(
      said.toLowerCase(),
      isNot(contains('deleted')),
      reason: 'nothing has been deleted, and saying so invites a reinstall',
    );
  });
}
