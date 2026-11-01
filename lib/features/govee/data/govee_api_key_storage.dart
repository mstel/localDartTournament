import 'package:shared_preferences/shared_preferences.dart';

class GoveeApiKeyStorage {
  static const _key = 'govee_api_key';

  Future<String?> load() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  Future<void> save(String value) async {
    final key = value.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(
        value,
        'value',
        'API-Key darf nicht leer sein.',
      );
    }
    final saved = await (await SharedPreferences.getInstance()).setString(
      _key,
      key,
    );
    if (!saved) {
      throw StateError('Govee API-Key konnte nicht gespeichert werden.');
    }
  }

  Future<void> delete() async {
    final deleted = await (await SharedPreferences.getInstance()).remove(_key);
    if (!deleted) {
      throw StateError('Govee API-Key konnte nicht gelöscht werden.');
    }
  }
}
