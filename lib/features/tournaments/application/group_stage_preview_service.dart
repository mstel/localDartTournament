import '../domain/engines/group_standings_engine.dart';
import '../domain/engines/qualification_certainty.dart';
import '../domain/tournament_models.dart';

class GroupStagePreviewService {
  const GroupStagePreviewService();

  List<TournamentPlayer> presentProjectedPlayers({
    required TournamentRunStage stage,
    required List<TournamentPlayer> projectedPlayers,
    required CreatedTournament tournament,
  }) {
    final matches = _matches(stage).toList();
    final hasResults = matches.any((match) => match.countsForStatistics);
    if (!hasResults) {
      final targetCount = _placeholderCount(stage, tournament, projectedPlayers);
      final requiredCount = targetCount > 0 ? targetCount : projectedPlayers.length;
      return List.generate(
        requiredCount,
        (index) => TournamentPlayer(
          name: 'Qualifikant ${index + 1} (noch offen)',
          isGenerated: true,
        ),
      );
    }
    final stageIsSet = isStageSet(stage);
    return [
      for (final player in projectedPlayers)
        player.copyWith(
          name:
              '${player.name} · '
              '${stageIsSet || _isCertainQualifier(stage, player, tournament) ? 'gesetzt' : 'vorläufig'}',
        ),
    ];
  }

  int _placeholderCount(
    TournamentRunStage stage,
    CreatedTournament tournament,
    List<TournamentPlayer> projectedPlayers,
  ) {
    if (stage is GroupTournamentRunStage) {
      final plan = stage.qualificationPlan;
      if (plan != null && plan.totalQualifiers > 0) {
        return plan.totalQualifiers;
      }
    }
    final stageIndex = tournament.runStages.indexOf(stage);
    if (stageIndex >= 0 && stageIndex + 1 < tournament.runStages.length) {
      final nextStage = tournament.runStages[stageIndex + 1];
      if (nextStage is KnockoutTournamentRunStage) {
        final firstRoundSize = nextStage.rounds.firstOrNull?.length ?? 0;
        if (firstRoundSize > 0) {
          return firstRoundSize * 2;
        }
      }
    }
    return projectedPlayers.length;
  }

  bool isStageSet(TournamentRunStage stage) {
    final matches = _matches(stage).where((match) => !match.isDecider).toList();
    return matches.isNotEmpty && matches.every((match) => match.isResolved);
  }

  bool _isCertainQualifier(
    TournamentRunStage stage,
    TournamentPlayer player,
    CreatedTournament tournament,
  ) {
    if (stage is! GroupTournamentRunStage) return false;
    final plan = stage.qualificationPlan;
    if (plan == null ||
        stage.groups.any((group) => group.playType.contains('knockout'))) {
      return false;
    }
    for (var groupIndex = 0; groupIndex < stage.groups.length; groupIndex++) {
      final group = stage.groups[groupIndex];
      final standings = const GroupStandingsEngine().calculate(
        group,
        stage.tieBreakers,
        tournament: tournament,
      );
      final rank = standings.indexWhere(
        (standing) =>
            standing.player.profileId != null && player.profileId != null
            ? standing.player.profileId == player.profileId
            : standing.player.name == player.name,
      );
      if (rank < 0) continue;
      final fixedPlaces = groupIndex < plan.fixedByGroup.length
          ? plan.fixedByGroup[groupIndex]
          : plan.fixedPerGroup;
      return const QualificationCertainty().isCertain(
        standing: standings[rank],
        place: rank + 1,
        fixedPlaces: fixedPlaces,
        standings: standings,
        matches: group.matches,
        tieBreakers: stage.tieBreakers,
      );
    }
    return false;
  }

  Iterable<GroupMatch> _matches(TournamentRunStage stage) sync* {
    if (stage is GroupTournamentRunStage) {
      for (final group in stage.groups) {
        yield* group.matches;
      }
    } else if (stage is KnockoutTournamentRunStage) {
      yield* stage.matches;
    }
  }
}
