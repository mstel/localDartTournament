import 'engines/group_standings_engine.dart';
import 'tournament_models.dart';

class TournamentWinner {
  const TournamentWinner._();

  static String? profileId(CreatedTournament tournament) {
    final archiveWinner = _challongeWinner(tournament);
    if (tournament.importedArchive != null) return archiveWinner;

    for (final stage in tournament.runStages.reversed) {
      if (stage is KnockoutTournamentRunStage &&
          stage.rounds.isNotEmpty &&
          stage.rounds.last.length == 1 &&
          stage.rounds.last.single.hasResult) {
        return stage.rounds.last.single.winner?.profileId;
      }
    }

    final lastIndex = tournament.runStages.length - 1;
    if (lastIndex < 0 ||
        !tournament.completedStageIndexes.contains(lastIndex)) {
      return null;
    }
    final finalStage = tournament.runStages[lastIndex];
    if (finalStage is! GroupTournamentRunStage ||
        finalStage.groups.length != 1) {
      return null;
    }
    final standings = const GroupStandingsEngine().calculate(
      finalStage.groups.single,
      finalStage.tieBreakers,
    );
    if (standings.isEmpty) return null;
    if (standings.length > 1 &&
        const GroupStandingsEngine().compare(
              standings.first,
              standings[1],
              finalStage.tieBreakers,
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
