import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/tournament_models.dart';
import '../presentation/models/match_result.dart';

/// Only a single unresolved match is submitted. Never upload the reporter's
/// entire tournament snapshot or let reporters alter brackets and settings.
class TournamentResultRepository {
  static List<String> matchPath(CreatedTournament t, GroupMatch target) {
    List<String>? inMatches(List<GroupMatch> matches, List<String> path) {
      final index = matches.indexOf(target);
      return index < 0 ? null : [...path, '$index'];
    }

    List<String>? inRounds(List<List<GroupMatch>> rounds, List<String> path) {
      for (var r = 0; r < rounds.length; r++) {
        final found = inMatches(rounds[r], [...path, '$r']);
        if (found != null) return found;
      }
      return null;
    }

    for (var s = 0; s < t.runStages.length; s++) {
      final stage = t.runStages[s];
      final path = ['runStages', '$s'];
      if (stage is GroupTournamentRunStage) {
        for (var g = 0; g < stage.groups.length; g++) {
          final group = stage.groups[g];
          final p = [...path, 'groups', '$g'];
          final found =
              inMatches(group.matches, [...p, 'matches']) ??
              inMatches(group.placementMatches, [...p, 'placementMatches']) ??
              inRounds(group.knockoutRounds, [...p, 'knockoutRounds']);
          if (found != null) return found;
        }
      } else if (stage is KnockoutTournamentRunStage) {
        final found =
            inRounds(stage.rounds, [...path, 'rounds']) ??
            inMatches(stage.placementMatches, [...path, 'placementMatches']);
        if (found != null) return found;
      }
    }
    throw StateError('Spiel gehört nicht zum Turnier.');
  }

  Future<CreatedTournament> submit(
    CreatedTournament t,
    GroupMatch match,
    MatchResult result,
  ) async {
    if (match.isResolved ||
        result.isAnnulled ||
        result.homeLegs == null ||
        result.awayLegs == null) {
      throw StateError(
        'Nur offene Begegnungen können gemeldet werden. Korrekturen übernimmt die Turnierleitung.',
      );
    }
    final data = await Supabase.instance.client.rpc(
      'submit_tournament_result',
      params: {
        'target_tournament': t.id,
        'match_path': matchPath(t, match),
        'expected_home': match.homePlayer?.toJson(),
        'expected_away': match.awayPlayer?.toJson(),
        'expected_start': match.startedAt?.toUtc().toIso8601String(),
        'score': {
          'homeLegs': result.homeLegs,
          'awayLegs': result.awayLegs,
          'homeSets': result.homeSets,
          'awaySets': result.awaySets,
        },
      },
    );
    return CreatedTournament.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
