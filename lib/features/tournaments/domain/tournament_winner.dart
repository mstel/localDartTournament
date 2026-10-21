import 'engines/group_standings_engine.dart';
import 'tournament_models.dart';

class TournamentWinner {
  const TournamentWinner._();

  static String? profileId(CreatedTournament tournament) {
    final archiveWinner = _challongeWinner(tournament);
    if (tournament.importedArchive != null) return archiveWinner;

    final lastIndex = tournament.runStages.length - 1;
    if (lastIndex < 0 ||
        (!tournament.completedStageIndexes.contains(lastIndex) &&
            tournament.finishedAt == null)) {
      return null;
    }
    final finalStage = tournament.runStages[lastIndex];
    if (finalStage is KnockoutTournamentRunStage &&
        finalStage.rounds.isNotEmpty &&
        finalStage.rounds.last.length == 1 &&
        finalStage.rounds.last.single.hasResult) {
      return finalStage.rounds.last.single.winner?.profileId;
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
      return group.knockoutRounds.last.single.winner?.profileId;
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
    return standings.first.player.profileId;
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
