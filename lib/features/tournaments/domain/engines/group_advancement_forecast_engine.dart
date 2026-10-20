import 'dart:math';

import '../../../rankings/domain/local_elo_calculator.dart';
import '../tournament_models.dart';

class GroupAdvancementPlayerData {
  const GroupAdvancementPlayerData({
    this.rating = defaultEloRating,
    this.historicalWinRate = 0.5,
  });

  final int rating;
  final double historicalWinRate;
}

class AdvancementChance {
  const AdvancementChance({
    required this.groupWinProbability,
    required this.advancementProbability,
  });

  final double groupWinProbability;
  final double advancementProbability;
}

class GroupAdvancementForecastEngine {
  const GroupAdvancementForecastEngine();

  Map<String, AdvancementChance> calculate({
    required GroupTournamentRunStage stage,
    Map<String, GroupAdvancementPlayerData> players = const {},
    int simulations = 3000,
    int seed = 19,
  }) {
    if (simulations < 1) throw ArgumentError.value(simulations, 'simulations');
    final plan = stage.qualificationPlan;
    if (plan == null) return const {};
    final random = Random(seed);
    final outcomes = <String, _ChanceTotals>{};
    final simulatedStandings = <List<List<_SimulatedStanding>>>[];

    for (var groupIndex = 0; groupIndex < stage.groups.length; groupIndex++) {
      final group = stage.groups[groupIndex];
      final base = _baseStandings(group);
      final remaining = group.matches
          .where(
            (match) =>
                match.hasPlayers &&
                !match.isResolved &&
                !match.isDecider &&
                match.homePlayer != null &&
                match.awayPlayer != null,
          )
          .toList();
      for (final standing in base.values) {
        outcomes.putIfAbsent(standing.key, () => _ChanceTotals());
      }
      final groupSimulations = <List<_SimulatedStanding>>[];
      for (var simulation = 0; simulation < simulations; simulation++) {
        final standings = {
          for (final entry in base.entries) entry.key: entry.value.copy(),
        };
        for (final match in remaining) {
          final home = match.homePlayer!;
          final away = match.awayPlayer!;
          final homeStanding = standings[_playerKey(home)];
          final awayStanding = standings[_playerKey(away)];
          if (homeStanding == null || awayStanding == null) continue;
          final homeData =
              players[_playerKey(home)] ?? const GroupAdvancementPlayerData();
          final awayData =
              players[_playerKey(away)] ?? const GroupAdvancementPlayerData();
          final eloChance = eloExpectedScore(homeData.rating, awayData.rating);
          final historyChance =
              (0.5 +
                      (homeData.historicalWinRate -
                              awayData.historicalWinRate) /
                          2)
                  .clamp(0.05, 0.95);
          final homeChance = (eloChance * 0.7 + historyChance * 0.3).clamp(
            0.05,
            0.95,
          );
          final homeWins = random.nextDouble() < homeChance;
          final winnerLegs = 2;
          final loserLegs = random.nextDouble() < 0.35 ? 1 : 0;
          _recordResult(
            homeStanding,
            awayStanding,
            homeWins ? winnerLegs : loserLegs,
            homeWins ? loserLegs : winnerLegs,
          );
        }
        final ranked = _rank(standings.values.toList(), stage.tieBreakers);
        groupSimulations.add(ranked);
      }
      simulatedStandings.add(groupSimulations);
      final fixedPlaces = groupIndex < plan.fixedByGroup.length
          ? plan.fixedByGroup[groupIndex]
          : plan.fixedPerGroup;
      for (final ranked in groupSimulations) {
        if (ranked.isEmpty) continue;
        outcomes[ranked.first.key]!.groupWins++;
        for (var place = 0; place < min(fixedPlaces, ranked.length); place++) {
          outcomes[ranked[place].key]!.advances++;
        }
      }
    }

    if (plan.extraCount > 0 && plan.extraGroups.isNotEmpty) {
      for (var simulation = 0; simulation < simulations; simulation++) {
        final candidates = <({int groupIndex, _SimulatedStanding standing})>[];
        for (final groupNumber in plan.extraGroups) {
          final groupIndex = groupNumber - 1;
          if (groupIndex < 0 || groupIndex >= stage.groups.length) continue;
          final ranked = simulatedStandings[groupIndex][simulation];
          final rankIndex = plan.extraRank - 1;
          if (rankIndex >= 0 && rankIndex < ranked.length) {
            candidates.add((
              groupIndex: groupIndex,
              standing: ranked[rankIndex],
            ));
          }
        }
        candidates.sort((a, b) {
          final comparison = _compare(
            a.standing,
            b.standing,
            stage.tieBreakers,
          );
          return comparison != 0
              ? comparison
              : a.groupIndex.compareTo(b.groupIndex);
        });
        for (final candidate in candidates.take(plan.extraCount)) {
          outcomes[candidate.standing.key]!.advances++;
        }
      }
    }

    return {
      for (final entry in outcomes.entries)
        entry.key: AdvancementChance(
          groupWinProbability: entry.value.groupWins * 100 / simulations,
          advancementProbability: entry.value.advances * 100 / simulations,
        ),
    };
  }

  Map<String, _SimulatedStanding> _baseStandings(TournamentGroup group) {
    final standings = {
      for (final player in group.players)
        _playerKey(player): _SimulatedStanding(
          key: _playerKey(player),
          player: player,
        ),
    };
    for (final match in group.matches.where(
      (match) => match.hasResult && !match.isDecider,
    )) {
      final home = match.homePlayer;
      final away = match.awayPlayer;
      if (home == null || away == null) continue;
      final homeStanding = standings[_playerKey(home)];
      final awayStanding = standings[_playerKey(away)];
      if (homeStanding == null || awayStanding == null) continue;
      _recordResult(
        homeStanding,
        awayStanding,
        match.homeLegs ?? 0,
        match.awayLegs ?? 0,
      );
    }
    return standings;
  }

  List<_SimulatedStanding> _rank(
    List<_SimulatedStanding> standings,
    List<String> tieBreakers,
  ) {
    standings.sort((a, b) => _compare(a, b, tieBreakers));
    return standings;
  }

  int _compare(
    _SimulatedStanding a,
    _SimulatedStanding b,
    List<String> tieBreakers,
  ) {
    for (final rule in tieBreakers) {
      final comparison = switch (rule) {
        'points' => b.points.compareTo(a.points),
        'legDifference' => b.legDifference.compareTo(a.legDifference),
        'legsFor' => b.legsFor.compareTo(a.legsFor),
        _ => 0,
      };
      if (comparison != 0) return comparison;
    }
    return a.player.name.compareTo(b.player.name);
  }

  void _recordResult(
    _SimulatedStanding home,
    _SimulatedStanding away,
    int homeLegs,
    int awayLegs,
  ) {
    home.played++;
    away.played++;
    home.legsFor += homeLegs;
    home.legsAgainst += awayLegs;
    away.legsFor += awayLegs;
    away.legsAgainst += homeLegs;
    if (homeLegs > awayLegs) {
      home.wins++;
      home.points += 3;
      away.losses++;
    } else if (awayLegs > homeLegs) {
      away.wins++;
      away.points += 3;
      home.losses++;
    } else {
      home.draws++;
      away.draws++;
      home.points++;
      away.points++;
    }
  }

  String _playerKey(TournamentPlayer player) => player.profileId ?? player.name;
}

class _SimulatedStanding {
  _SimulatedStanding({required this.key, required this.player});

  final String key;
  final TournamentPlayer player;
  int played = 0;
  int wins = 0;
  int draws = 0;
  int losses = 0;
  int legsFor = 0;
  int legsAgainst = 0;
  int points = 0;
  int get legDifference => legsFor - legsAgainst;

  _SimulatedStanding copy() => _SimulatedStanding(key: key, player: player)
    ..played = played
    ..wins = wins
    ..draws = draws
    ..losses = losses
    ..legsFor = legsFor
    ..legsAgainst = legsAgainst
    ..points = points;
}

class _ChanceTotals {
  int groupWins = 0;
  int advances = 0;
}
