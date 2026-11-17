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
    required this.tournamentWinProbability,
  });

  /// Chance to finish the group in first place.
  final double groupWinProbability;

  /// Chance to reach the next stage.
  final double advancementProbability;

  /// Chance to win the whole tournament, including the following K.O. stage.
  final double tournamentWinProbability;
}

class GroupAdvancementForecastEngine {
  const GroupAdvancementForecastEngine();

  Map<String, AdvancementChance> calculate({
    required GroupTournamentRunStage stage,
    Map<String, GroupAdvancementPlayerData> players = const {},
    int simulations = 3000,
    int seed = 19,
    KnockoutTournamentRunStage? knockoutStage,
  }) {
    if (simulations < 1) throw ArgumentError.value(simulations, 'simulations');
    final plan = stage.qualificationPlan;
    if (plan == null) return const {};
    final random = Random(seed);
    final outcomes = <String, _ChanceTotals>{};
    final simulatedStandings = <List<List<_SimulatedStanding>>>[];
    final advancingBySimulation = List<List<String>>.generate(
      simulations,
      (_) => <String>[],
    );
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
          final homeChance = _winProbability(_playerKey(home), _playerKey(away), players);
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
        groupSimulations.add(
          _rank(standings.values.toList(), stage.tieBreakers),
        );
      }
      simulatedStandings.add(groupSimulations);
      final fixedPlaces = groupIndex < plan.fixedByGroup.length
          ? plan.fixedByGroup[groupIndex]
          : plan.fixedPerGroup;
      for (var simulation = 0; simulation < simulations; simulation++) {
        final ranked = groupSimulations[simulation];
        if (ranked.isEmpty) continue;
        outcomes[ranked.first.key]!.groupWins++;
        for (var place = 0; place < min(fixedPlaces, ranked.length); place++) {
          final key = ranked[place].key;
          outcomes[key]!.advances++;
          advancingBySimulation[simulation].add(key);
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
          final key = candidate.standing.key;
          outcomes[key]!.advances++;
          if (!advancingBySimulation[simulation].contains(key)) {
            advancingBySimulation[simulation].add(key);
          }
        }
      }
    }

    if (knockoutStage != null && knockoutStage.rounds.isNotEmpty) {
      for (var simulation = 0; simulation < simulations; simulation++) {
        final field = _orderedKnockoutField(
          advancingBySimulation[simulation],
          knockoutStage,
        );
        final champion = _simulateKnockoutChampion(
          field,
          players,
          random,
        );
        if (champion != null) outcomes[champion]!.tournamentWins++;
      }
    }

    return {
      for (final entry in outcomes.entries)
        entry.key: AdvancementChance(
          groupWinProbability: entry.value.groupWins * 100 / simulations,
          advancementProbability: entry.value.advances * 100 / simulations,
          tournamentWinProbability:
              entry.value.tournamentWins * 100 / simulations,
        ),
    };
  }

  double _winProbability(
    String homeKey,
    String awayKey,
    Map<String, GroupAdvancementPlayerData> players,
  ) {
    final homeData =
        players[homeKey] ?? const GroupAdvancementPlayerData();
    final awayData =
        players[awayKey] ?? const GroupAdvancementPlayerData();
    final eloChance = eloExpectedScore(homeData.rating, awayData.rating);
    final historyChance =
        (0.5 + (homeData.historicalWinRate - awayData.historicalWinRate) / 2)
            .clamp(0.05, 0.95);
    return (eloChance * 0.7 + historyChance * 0.3).clamp(0.05, 0.95);
  }

  /// Keep the real bracket order where possible; unknown qualifiers are added
  /// afterwards so every simulation still has a complete field.
  List<String> _orderedKnockoutField(
    List<String> advancing,
    KnockoutTournamentRunStage knockoutStage,
  ) {
    final advancingSet = advancing.toSet();
    final ordered = <String>[];
    for (final player in knockoutStage.participants) {
      final key = _playerKey(player);
      if (advancingSet.contains(key) && !ordered.contains(key)) {
        ordered.add(key);
      }
    }
    for (final key in advancing) {
      if (!ordered.contains(key)) ordered.add(key);
    }
    return ordered;
  }

  String? _simulateKnockoutChampion(
    List<String> field,
    Map<String, GroupAdvancementPlayerData> players,
    Random random,
  ) {
    var round = List<String>.from(field);
    if (round.length < 2) return round.isEmpty ? null : round.first;
    while (round.length > 1) {
      final next = <String>[];
      for (var index = 0; index + 1 < round.length; index += 2) {
        final home = round[index];
        final away = round[index + 1];
        next.add(
          random.nextDouble() < _winProbability(home, away, players)
              ? home
              : away,
        );
      }
      if (round.length.isOdd) next.add(round.last);
      round = next;
    }
    return round.first;
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
        'headToHead' => _compareHeadToHead(a, b),
        'legDifference' => b.legDifference.compareTo(a.legDifference),
        'legsFor' => b.legsFor.compareTo(a.legsFor),
        _ => 0,
      };
      if (comparison != 0) return comparison;
    }
    return a.player.name.compareTo(b.player.name);
  }

  int _compareHeadToHead(_SimulatedStanding first, _SimulatedStanding second) {
    final firstRecord = first.headToHead[second.key];
    final secondRecord = second.headToHead[first.key];
    final points = (secondRecord?.points ?? 0).compareTo(
      firstRecord?.points ?? 0,
    );
    if (points != 0) return points;

    final firstDifference =
        (firstRecord?.legsFor ?? 0) - (firstRecord?.legsAgainst ?? 0);
    final secondDifference =
        (secondRecord?.legsFor ?? 0) - (secondRecord?.legsAgainst ?? 0);
    final difference = secondDifference.compareTo(firstDifference);
    if (difference != 0) return difference;
    return (secondRecord?.legsFor ?? 0).compareTo(firstRecord?.legsFor ?? 0);
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
    final homeHeadToHead = home.headToHead.putIfAbsent(
      away.key,
      _HeadToHeadRecord.new,
    );
    final awayHeadToHead = away.headToHead.putIfAbsent(
      home.key,
      _HeadToHeadRecord.new,
    );
    homeHeadToHead.legsFor += homeLegs;
    homeHeadToHead.legsAgainst += awayLegs;
    awayHeadToHead.legsFor += awayLegs;
    awayHeadToHead.legsAgainst += homeLegs;
    if (homeLegs > awayLegs) {
      home.wins++;
      home.points += 3;
      away.losses++;
      homeHeadToHead.points += 3;
    } else if (awayLegs > homeLegs) {
      away.wins++;
      away.points += 3;
      home.losses++;
      awayHeadToHead.points += 3;
    } else {
      home.draws++;
      away.draws++;
      home.points++;
      away.points++;
      homeHeadToHead.points++;
      awayHeadToHead.points++;
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
  final Map<String, _HeadToHeadRecord> headToHead = {};
  int get legDifference => legsFor - legsAgainst;

  _SimulatedStanding copy() {
    final copied = _SimulatedStanding(key: key, player: player)
      ..played = played
      ..wins = wins
      ..draws = draws
      ..losses = losses
      ..legsFor = legsFor
      ..legsAgainst = legsAgainst
      ..points = points;
    copied.headToHead.addAll({
      for (final entry in headToHead.entries) entry.key: entry.value.copy(),
    });
    return copied;
  }
}

class _HeadToHeadRecord {
  int points = 0;
  int legsFor = 0;
  int legsAgainst = 0;

  _HeadToHeadRecord copy() => _HeadToHeadRecord()
    ..points = points
    ..legsFor = legsFor
    ..legsAgainst = legsAgainst;
}

class _ChanceTotals {
  int groupWins = 0;
  int advances = 0;
  int tournamentWins = 0;
}
