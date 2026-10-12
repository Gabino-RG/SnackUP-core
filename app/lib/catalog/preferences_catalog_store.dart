import 'package:shared_preferences/shared_preferences.dart';
import 'local_catalog_repository.dart';

/// Non-critical example data only. Production persistence belongs to the API.
class PreferencesCatalogStore implements CatalogStore {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  static const key = 'snackup.catalog.example.v1';
  @override
  Future<String?> read() => _preferences.getString(key);
  @override
  Future<void> write(String value) => _preferences.setString(key, value);
}
