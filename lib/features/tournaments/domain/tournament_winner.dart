import 'engines/group_standings_engine.dart';
import 'tournament_models.dart';
import '../modes/kratzer/kratzer_engine.dart';

class TournamentWinner {
  const TournamentWinner._();

  static String? profileId(CreatedTournament tournament) {
    if (tournament.importedArchive != null) {
      return _challongeWinner(tournament);
    }

    return _liveWinner(tournament)?.profileId;
  }

  static String? name(CreatedTournament tournament) {
    if (tournament.leagueMatch != null) return null;
    final archive = tournament.importedArchive;
    if (archive != null) {
      final winners = archive.participants.where(
        (participant) => participant['finalRank'] == 1,
      );
      if (winners.length != 1) return null;
      final winner = winners.single;
      final name = winner['name'];
      if (name is String && name.trim().isNotEmpty) return name;
      final profileId = winner['profileId'];
      return tournament.players
          .where((player) => player.profileId == profileId)
          .map((player) => player.name)
          .firstOrNull;
    }

    return _liveWinner(tournament)?.name;
  }

  static TournamentPlayer? _liveWinner(CreatedTournament tournament) {
    final lastIndex = tournament.runStages.length - 1;
    if (lastIndex < 0 ||
        (!tournament.completedStageIndexes.contains(lastIndex) &&
            tournament.finishedAt == null)) {
      return null;
    }
    final finalStage = tournament.runStages[lastIndex];
    if (finalStage is KnockoutTournamentRunStage && finalStage.isKratzer) {
      final survivors = const KratzerEngine().activePlayers(
        players: finalStage.participants,
        completedMatches: finalStage.matches,
        lives: finalStage.eliminationLossLimit,
      );
      return survivors.length == 1 ? survivors.single : null;
    }
    if (finalStage is KnockoutTournamentRunStage &&
        finalStage.rounds.isNotEmpty &&
        finalStage.rounds.last.length == 1 &&
        finalStage.rounds.last.single.hasResult) {
      return finalStage.rounds.last.single.winner;
    }
    if (finalStage is! GroupTournamentRunStage ||
        finalStage.groups.length != 1) {
      return null;
    }
    final group = finalStage.groups.single;
    if (group.playType == 'mini_knockout' &&
        group.knockoutRounds.isNotEmpty &&
        group.knockoutRounds.last.length == 1 &&
        group.knockoutRounds.last.single.hasResult) {
      return group.knockoutRounds.last.single.winner;
    }
    final standings = const GroupStandingsEngine().calculate(
      group,
      finalStage.tieBreakers,
      tournament: tournament,
    );
    if (standings.isEmpty) return null;
    if (standings.length > 1 &&
        const GroupStandingsEngine().compare(
              standings.first,
              standings[1],
              finalStage.tieBreakers,
              matches: group.matches,
            ) ==
            0) {
      return null;
    }
    return standings.first.player;
  }

  static String? _challongeWinner(CreatedTournament tournament) {
    final archive = tournament.importedArchive;
    if (archive == null) return null;
    final winners = archive.participants.where(
      (participant) => participant['finalRank'] == 1,
    );
    if (winners.length != 1) return null;
    final winner = winners.single;
    final profileId = winner['profileId'];
    if (profileId is String && profileId.isNotEmpty) return profileId;
    final name = winner['name'];
    if (name is! String) return null;
    return tournament.players
        .where((player) => player.name == name)
        .map((player) => player.profileId)
        .firstOrNull;
  }
}
