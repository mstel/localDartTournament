import 'package:shared_preferences/shared_preferences.dart';

import '../domain/tournament_flow_priority_settings.dart';

class TournamentFlowPriorityPreferences {
  static const playerThresholdKey =
      'tournaments.v1.priority_player_match_threshold';
  static const groupThresholdKey =
      'tournaments.v1.priority_group_match_threshold';
  static const percentageKey = 'tournaments.v1.priority_group_percentage';

  Future<TournamentFlowPrioritySettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final settings = TournamentFlowPrioritySettings(
      playerMatchDeficitThreshold:
          preferences.getInt(playerThresholdKey) ??
          const TournamentFlowPrioritySettings().playerMatchDeficitThreshold,
      groupMatchDeficitThreshold:
          preferences.getInt(groupThresholdKey) ??
          const TournamentFlowPrioritySettings().groupMatchDeficitThreshold,
      usePercentageForGroups:
          preferences.getBool(percentageKey) ??
          const TournamentFlowPrioritySettings().usePercentageForGroups,
    );
    return settings.isValid ? settings : const TournamentFlowPrioritySettings();
  }

  Future<void> save(TournamentFlowPrioritySettings settings) async {
    if (!settings.isValid) {
      throw ArgumentError.value(
        settings,
        'settings',
        'Prioritätsschwellen müssen ganze Zahlen von 1 bis 999 sein.',
      );
    }
    final preferences = await SharedPreferences.getInstance();
    final saved = await Future.wait([
      preferences.setInt(
        playerThresholdKey,
        settings.playerMatchDeficitThreshold,
      ),
      preferences.setInt(
        groupThresholdKey,
        settings.groupMatchDeficitThreshold,
      ),
      preferences.setBool(percentageKey, settings.usePercentageForGroups),
    ]);
    if (saved.any((value) => !value)) {
      throw StateError(
        'Hinweiseinstellungen konnten nicht gespeichert werden.',
      );
    }
  }
}
