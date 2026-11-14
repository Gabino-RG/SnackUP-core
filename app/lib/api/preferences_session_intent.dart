import 'package:shared_preferences/shared_preferences.dart';
import 'rest_session.dart';

/// A non-secret logout marker prevents cookie restoration after an offline exit.
/// No token, password or account data is stored here.
class PreferencesSessionIntentStore implements SessionIntentStore {
  PreferencesSessionIntentStore(String apiOrigin, {String? namespace})
    : _key =
          'snackup.logout.pending.$apiOrigin${namespace == null ? '' : '.$namespace'}';
  final String _key;
  final _preferences = SharedPreferencesAsync();
  @override
  Future<bool> readLogoutPending() async =>
      await _preferences.getBool(_key) ?? false;
  @override
  Future<void> writeLogoutPending(bool pending) =>
      _preferences.setBool(_key, pending);
}
