import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_flow_priority.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

void main() {
  test('one match behind does not trigger player prioritization', () {
    final stage = _stage();
    _finish(stage.groups.first.matches.first);

    final priority = TournamentFlowPriority.forStage(stage);

    expect(priority.notices, isEmpty);
    expect(priority.prioritizedMatches, isEmpty);
  });

  test(
    'two matches behind prioritizes open matches for the trailing player',
    () {
      final stage = _stage();
      final matches = stage.groups.first.matches;
      _finish(matches[0]);
      _finish(matches[1]);

      final priority = TournamentFlowPriority.forStage(stage);

      expect(priority.notices.single, contains('Spieler 4'));
      expect(
        priority.prioritizedMatches,
        containsAll(
          matches.where(
            (match) =>
                match.hasPlayers &&
                (match.homePlayer == stage.groups.first.players.last ||
                    match.awayPlayer == stage.groups.first.players.last) &&
                !match.isResolved,
          ),
        ),
      );
    },
  );

  test('group imbalance needs three played matches before prioritizing', () {
    final stage = _stage();
    final leading = stage.groups.first;
    final trailing = stage.groups.last;
    _finish(leading.matches[0]);
    _finish(leading.matches[1]);

    final belowThreshold = TournamentFlowPriority.forStage(stage);
    expect(
      belowThreshold.notices.where((n) => n.contains('Gruppe B')),
      isEmpty,
    );

    _finish(leading.matches[2]);
    final atThreshold = TournamentFlowPriority.forStage(stage);

    expect(atThreshold.notices, contains(contains('Gruppe B')));
    expect(
      atThreshold.prioritizedMatches,
      containsAll(trailing.matches.where((match) => !match.isResolved)),
    );
  });
}

void _finish(GroupMatch match) {
  match
    ..homeLegs = 3
    ..awayLegs = 0;
}

GroupTournamentRunStage _stage() {
  final firstGroupPlayers = [
    for (var index = 1; index <= 4; index++) TournamentPlayer.generated(index),
  ];
  final secondGroupPlayers = [
    for (var index = 5; index <= 8; index++) TournamentPlayer.generated(index),
  ];
  TournamentGroup group(String name, List<TournamentPlayer> players) =>
      TournamentGroup(
        name: name,
        playType: 'round_robin',
        players: players,
        matches: [
          for (var home = 0; home < players.length; home++)
            for (var away = home + 1; away < players.length; away++)
              GroupMatch(
                homePlayer: players[home],
                awayPlayer: players[away],
                round: 1,
              ),
        ],
      );
  return GroupTournamentRunStage(
    name: 'Gruppenphase',
    groupPlayType: 'round_robin',
    groups: [
      group('Gruppe A', firstGroupPlayers),
      group('Gruppe B', secondGroupPlayers),
    ],
    qualificationPlan: null,
    tieBreakers: defaultGroupTieBreakers,
  );
}
