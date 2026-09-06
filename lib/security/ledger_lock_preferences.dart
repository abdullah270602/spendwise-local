import '../app/spendwise_controller.dart';
import 'app_lock.dart';

/// The lock's few facts live in the ledger's own key/value table, which means
/// they sit inside the SQLCipher database like everything else, and "erase all
/// local data" takes the PIN with it rather than leaving a lock on an empty
/// app that nobody can open.
class LedgerLockPreferences implements LockPreferences {
  const LedgerLockPreferences(this.controller);

  final SpendWiseController controller;

  @override
  String? read(String key) => controller.viewPreference(key);

  @override
  void write(String key, String value) =>
      controller.setViewPreference(key, value);
}
