import '../domain/engines/group_standings_engine.dart';
import '../domain/tournament_models.dart';

/// unterscheidbar: Tabellenphasen (Gruppe/Schweizer/Kratzer) und KO-Bäume.
enum TournamentPhaseViewType { table, knockout, kratzer }

extension TournamentPhaseViewTypeJson on TournamentPhaseViewType {
  String get jsonValue => switch (this) {
    TournamentPhaseViewType.table => 'table',
    TournamentPhaseViewType.knockout => 'knockout',
    TournamentPhaseViewType.kratzer => 'kratzer',
  };
}

/// Abgeleitete Tabellenzeile für Gruppe, Schweizer System und Kratzer.
class TournamentPhaseStandingView {
  const TournamentPhaseStandingView({
    required this.rank,
    required this.playerId,
    required this.player,
    required this.played,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.legsFor,
    required this.legsAgainst,
    required this.legDifference,
    required this.points,
  });

  final int rank;
  final String? playerId;
  final String player;
  final int played;
  final int wins;
  final int draws;
  final int losses;
  final int legsFor;
  final int legsAgainst;
  final int legDifference;
  final int points;

  static TournamentPhaseStandingView fromStanding(
    PlayerStanding standing,
    int rank,
  ) => TournamentPhaseStandingView(
    rank: rank,
    playerId: standing.player.profileId,
    player: standing.player.name,
    played: standing.played,
    wins: standing.wins,
    draws: standing.draws,
    losses: standing.losses,
    legsFor: standing.legsFor,
    legsAgainst: standing.legsAgainst,
    legDifference: standing.legDifference,
    points: standing.points,
  );

  Map<String, dynamic> toJson() => {
    'rank': rank,
    'playerId': playerId,
    'player': player,
    'played': played,
    'wins': wins,
    'draws': draws,
    'losses': losses,
    'legsFor': legsFor,
    'legsAgainst': legsAgainst,
    'legDifference': legDifference,
    'points': points,
  };
}

class TournamentPhaseGroupView {
  const TournamentPhaseGroupView({
    required this.group,
    required this.standings,
    required this.groupNumber,
  });

  final TournamentGroup group;
  final List<PlayerStanding> standings;
  final int groupNumber;

  Map<String, dynamic> toJson() => {
    'name': group.name,
    'groupNumber': groupNumber,
    'playType': group.playType,
    'standings': [
      for (var index = 0; index < standings.length; index++)
        TournamentPhaseStandingView.fromStanding(
          standings[index],
          index + 1,
        ).toJson(),
    ],
    'matches': [for (final match in group.matches) match.toJson()],
    'placementMatches': [
      for (final match in group.placementMatches) match.toJson(),
    ],
    'knockoutRounds': [
      for (final round in group.knockoutRounds)
        [for (final match in round) match.toJson()],
    ],
  };
}

/// Eine Phase eines abgeschlossenen Turniers in der Detailansicht.
///
/// Die Domain-Objekte bleiben erhalten, damit die App dieselben Widgets wie
/// im Laufbetrieb nutzen kann; [toJson] liefert die API-Darstellung.
class TournamentPhaseView {
  const TournamentPhaseView({
    required this.index,
    required this.name,
    required this.type,
    required this.stage,
    this.groups = const [],
    this.knockoutStage,
    this.livesRemaining = const {},
  });

  final int index;
  final String name;
  final TournamentPhaseViewType type;
  final TournamentRunStage stage;
  final List<TournamentPhaseGroupView> groups;
  final KnockoutTournamentRunStage? knockoutStage;
  final Map<String, int> livesRemaining;

  String get stageKind => switch (stage) {
    GroupTournamentRunStage() => 'groups',
    KnockoutTournamentRunStage() => 'knockout',
    _ => 'unknown',
  };

  String? get playType => stage is GroupTournamentRunStage
      ? (stage as GroupTournamentRunStage).groupPlayType
      : null;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'index': index,
      'name': name,
      'type': type.jsonValue,
      'stageKind': stageKind,
      'playType': playType,
    };
    if (groups.isNotEmpty) {
      json['groups'] = [for (final group in groups) group.toJson()];
    }
    final knockout = knockoutStage;
    if (knockout != null) {
      json['rounds'] = [
        for (final round in knockout.rounds)
          [for (final match in round) match.toJson()],
      ];
      json['placementMatches'] = [
        for (final match in knockout.placementMatches) match.toJson(),
      ];
      json['eliminationLossLimit'] = knockout.eliminationLossLimit;
      if (type == TournamentPhaseViewType.kratzer) {
        json['livesRemaining'] = {
          for (final entry in livesRemaining.entries) entry.key: entry.value,
        };
      }
    }
    return json;
  }
}

class TournamentPhaseViews {
  const TournamentPhaseViews();

  List<TournamentPhaseView> derive(CreatedTournament tournament) {
    final views = <TournamentPhaseView>[];
    for (var index = 0; index < tournament.runStages.length; index++) {
      final stage = tournament.runStages[index];
      if (stage is GroupTournamentRunStage) {
        views.add(
          TournamentPhaseView(
            index: index,
            name: stage.name,
            type: TournamentPhaseViewType.table,
            stage: stage,
            groups: [
              for (
                var groupIndex = 0;
                groupIndex < stage.groups.length;
                groupIndex++
              )
                TournamentPhaseGroupView(
                  group: stage.groups[groupIndex],
                  standings: const GroupStandingsEngine().calculate(
                    stage.groups[groupIndex],
                    stage.tieBreakers,
                    tournament: tournament,
                  ),
                  groupNumber: groupIndex + 1,
                ),
            ],
          ),
        );
        continue;
      }
      if (stage is KnockoutTournamentRunStage) {
        views.add(
          TournamentPhaseView(
            index: index,
            name: stage.name,
            type: stage.isKratzer
                ? TournamentPhaseViewType.kratzer
                : TournamentPhaseViewType.knockout,
            stage: stage,
            knockoutStage: stage,
            livesRemaining: stage.isKratzer
                ? {
                    for (final player in stage.participants)
                      player.name: stage.livesRemainingFor(player),
                  }
                : const {},
          ),
        );
      }
    }
    return views;
  }
}
