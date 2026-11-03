import 'package:shared_preferences/shared_preferences.dart';

import '../domain/player_insight.dart';

class PlayerInsightPreferences {
  const PlayerInsightPreferences({required this.enabledTypes});

  factory PlayerInsightPreferences.defaults() =>
      PlayerInsightPreferences(enabledTypes: PlayerInsightType.values.toSet());

  final Set<PlayerInsightType> enabledTypes;

  bool isEnabled(PlayerInsightType type) => enabledTypes.contains(type);

  PlayerInsightPreferences withEnabled(PlayerInsightType type, bool enabled) =>
      PlayerInsightPreferences(
        enabledTypes: {
          ...enabledTypes.where((item) => item != type),
          if (enabled) type,
        },
      );
}

class PlayerInsightPreferencesStorage {
  static const _key = 'player_insight_enabled_types';

  Future<PlayerInsightPreferences> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getStringList(_key);
    if (stored == null) return PlayerInsightPreferences.defaults();
    return PlayerInsightPreferences(
      enabledTypes: {
        for (final type in PlayerInsightType.values)
          if (stored.contains(type.name)) type,
      },
    );
  }

  Future<void> save(PlayerInsightPreferences value) async {
    final saved = await (await SharedPreferences.getInstance())
        .setStringList(_key, [
          for (final type in PlayerInsightType.values)
            if (value.isEnabled(type)) type.name,
        ]);
    if (!saved) {
      throw StateError(
        'Insights-Standardwerte konnten nicht gespeichert werden.',
      );
    }
  }
}
