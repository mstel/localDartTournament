import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/player_insight.dart';

class PlayerInsightPreferences {
  const PlayerInsightPreferences({
    required this.enabledTypes,
    this.thresholds = const {},
  });

  factory PlayerInsightPreferences.defaults() => PlayerInsightPreferences(
    enabledTypes: PlayerInsightType.values.toSet(),
    thresholds: {for (final type in PlayerInsightType.values) type: defaultThreshold(type)},
  );

  static int defaultThreshold(PlayerInsightType type) => switch (type) {
    PlayerInsightType.bogeyOpponent => 7,
    PlayerInsightType.giantKiller => 200,
    PlayerInsightType.lastLegStanding => 3,
    PlayerInsightType.momentum => 1,
    PlayerInsightType.rival => 4,
    _ => 1,
  };

  final Set<PlayerInsightType> enabledTypes;
  final Map<PlayerInsightType, int> thresholds;

  bool isEnabled(PlayerInsightType type) => enabledTypes.contains(type);

  int thresholdFor(PlayerInsightType type) =>
      thresholds[type] ?? defaultThreshold(type);

  PlayerInsightPreferences withEnabled(PlayerInsightType type, bool enabled) =>
      PlayerInsightPreferences(
        enabledTypes: {
          ...enabledTypes.where((item) => item != type),
          if (enabled) type,
        },
        thresholds: thresholds,
      );

  PlayerInsightPreferences withThreshold(PlayerInsightType type, int value) =>
      PlayerInsightPreferences(
        enabledTypes: enabledTypes,
        thresholds: {
          ...thresholds,
          type: value,
        },
      );
}

class PlayerInsightPreferencesStorage {
  static const _key = 'player_insight_enabled_types';
  static const _thresholdKey = 'player_insight_thresholds';

  Future<PlayerInsightPreferences> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getStringList(_key);
    final rawThresholds = preferences.getString(_thresholdKey);
    final thresholds = <PlayerInsightType, int>{};
    if (rawThresholds != null) {
      final decoded = jsonDecode(rawThresholds);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final type = PlayerInsightType.values.firstWhere(
            (value) => value.name == entry.key,
            orElse: () => PlayerInsightType.momentum,
          );
          final rawValue = entry.value;
          final value = rawValue is int
              ? rawValue
              : int.tryParse(rawValue?.toString() ?? '') ??
                    PlayerInsightPreferences.defaultThreshold(type);
          thresholds[type] = value;
        }
      }
    }
    final enabledTypes = <PlayerInsightType>{};
    if (stored == null) {
      return PlayerInsightPreferences.defaults();
    }
    for (final type in PlayerInsightType.values) {
      if (stored.contains(type.name)) {
        enabledTypes.add(type);
      }
    }
    return PlayerInsightPreferences(
      enabledTypes: enabledTypes,
      thresholds: {
        ...thresholds,
        for (final type in PlayerInsightType.values)
          if (!thresholds.containsKey(type)) type: PlayerInsightPreferences.defaultThreshold(type),
      },
    );
  }

  Future<void> save(PlayerInsightPreferences value) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await Future.wait([
      preferences.setStringList(_key, [
        for (final type in PlayerInsightType.values)
          if (value.isEnabled(type)) type.name,
      ]),
      preferences.setString(
        _thresholdKey,
        jsonEncode({
          for (final entry in value.thresholds.entries)
            entry.key.name: entry.value,
        }),
      ),
    ]);
    if (!saved.every((item) => item)) {
      throw StateError(
        'Insights-Standardwerte konnten nicht gespeichert werden.',
      );
    }
  }
}
