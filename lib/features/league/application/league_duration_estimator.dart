import '../../tournaments/domain/tournament_format_planner.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../../tournaments/domain/tournament_planning_parameters.dart';
import 'league_board_runtime.dart';
import '../domain/league_match.dart';

class LeagueDurationEstimate {
  const LeagueDurationEstimate({required this.minutes, required this.matches});

  final int minutes;
  final int matches;
}

class LeagueDurationEstimator {
  const LeagueDurationEstimator();

  LeagueDurationEstimate estimate({
    required LeagueMatch league,
    required int boards,
    required TournamentPlanningParameters parameters,
  }) {
    final players = [
      for (final name in league.homePlayers)
        TournamentPlayer(name: name, isGenerated: false),
      for (final name in league.awayPlayers)
        TournamentPlayer(name: name, isGenerated: false),
    ];
    final tournament = CreatedTournament(
      name: 'Ligaspiel-Zeitvorschau',
      players: players,
      stages: const [],
      runStages: const [],
      leagueMatch: league,
      boardCount: boards,
    );
    final schedule = LeagueBoardRuntime(tournament).schedule;
    final slots = schedule.planned.isEmpty
        ? 0
        : schedule.planned.last.block + 1;
    final matchMinutes = TournamentFormatPlanner(
      parameters: parameters,
    ).estimatedMatchMinutes(league.gameFormat);
    return LeagueDurationEstimate(
      minutes: (slots * matchMinutes).ceil(),
      matches: league.games.length,
    );
  }
}
