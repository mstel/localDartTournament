import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/persistence/storage_access.dart';

/// Dauerhaft gespeicherte Standardwerte, die beim Anlegen neuer Turniere und
/// Ligaspiele vorbelegt werden.
class GeneralDefaults {
  const GeneralDefaults({this.defaultBoardCount = 4});

  final int defaultBoardCount;

  static const schemaVersion = 1;
  static const int minimumBoardCount = 1;
  static const int maximumBoardCount = 64;

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'defaultBoardCount': defaultBoardCount,
  };

  factory GeneralDefaults.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != schemaVersion) {
      throw FormatException(
        'Unbekanntes Format für allgemeine Standardwerte '
        '(Version ${json['schemaVersion'] ?? 'fehlt'}).',
      );
    }
    final boards = json['defaultBoardCount'] as int?;
    if (boards == null ||
        boards < minimumBoardCount ||
        boards > maximumBoardCount) {
      throw const FormatException('Ungültige Anzahl Boards gespeichert.');
    }
    return GeneralDefaults(defaultBoardCount: boards);
  }
}

class GeneralDefaultsStorage {
  const GeneralDefaultsStorage();

  static const _key = 'general_defaults';

  Future<GeneralDefaults> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null) return const GeneralDefaults();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Ungültige allgemeine Standardwerte.');
    }
    return GeneralDefaults.fromJson(decoded);
  }

  Future<void> save(GeneralDefaults defaults) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(defaults.toJson()));
    StorageAccess.markLocalDataChanged();
  }
}
