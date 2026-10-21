import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/application/group_stage_preview_service.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

void main() {
  const service = GroupStagePreviewService();

  test('keeps projected qualifiers open before any group result', () {
    final tournament = _tournament();
    final projected = service.presentProjectedPlayers(
      stage: tournament.runStages.single,
      projectedPlayers: [tournament.players.first],
      tournament: tournament,
    );

    expect(projected.single.name, 'Qualifikant 1 (noch offen)');
  });

  test('labels a projected but catchable leader as provisional', () {
    final tournament = _tournament();
    final group =
        (tournament.runStages.single as GroupTournamentRunStage).groups.single;
    group.matches.first
      ..homeLegs = 3
      ..awayLegs = 0;

    final projected = service.presentProjectedPlayers(
      stage: tournament.runStages.single,
      projectedPlayers: [tournament.players.first],
      tournament: tournament,
    );

    expect(projected.single.name, 'Spieler 1 · vorläufig');
  });

  test('labels an uncatchable group leader as set before the group ends', () {
    final tournament = _tournament();
    final group =
        (tournament.runStages.single as GroupTournamentRunStage).groups.single;
    for (final match in group.matches.take(3)) {
      match
        ..homeLegs = 3
        ..awayLegs = 0;
    }

    final projected = service.presentProjectedPlayers(
      stage: tournament.runStages.single,
      projectedPlayers: [tournament.players.first],
      tournament: tournament,
    );

    expect(projected.single.name, 'Spieler 1 · gesetzt');
  });
}

CreatedTournament _tournament() {
  final players = [
    for (var index = 1; index <= 4; index++)
      TournamentPlayer(
        profileId: 'player-$index',
        name: 'Spieler $index',
        isGenerated: false,
      ),
  ];
  final matches = [
    for (var home = 0; home < players.length; home++)
      for (var away = home + 1; away < players.length; away++)
        GroupMatch(
          homePlayer: players[home],
          awayPlayer: players[away],
          round: 1,
        ),
  ];
  final stage = GroupTournamentRunStage(
    name: 'Gruppenphase',
    groupPlayType: 'round_robin',
    groups: [
      TournamentGroup(
        name: 'Gruppe A',
        playType: 'round_robin',
        players: players,
        matches: matches,
      ),
    ],
    qualificationPlan: const QualificationPlan(
      totalQualifiers: 1,
      fixedPerGroup: 1,
      extraCount: 0,
      extraRank: 0,
      eligibleGroupSize: null,
      extraGroups: [],
      fixedByGroup: [1],
    ),
    tieBreakers: defaultGroupTieBreakers,
  );
  return CreatedTournament(
    name: 'Test',
    players: players,
    stages: const [],
    runStages: [stage],
  );
}
