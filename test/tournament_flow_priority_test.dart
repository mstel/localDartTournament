import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_flow_priority.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_flow_priority_settings.dart';

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

  test(
    'matches against the caught-up player are last among prioritized matches',
    () {
      final stage = _stage();
      final group = stage.groups.first;
      final matches = group.matches;
      final caughtUpPlayer = group.players.first;
      final caughtUpMatches = matches
          .where(
            (match) =>
                match.homePlayer == caughtUpPlayer ||
                match.awayPlayer == caughtUpPlayer,
          )
          .take(2);
      for (final match in caughtUpMatches) {
        _finish(match);
      }
      final priority = TournamentFlowPriority.forStage(
        stage,
        settings: const TournamentFlowPrioritySettings(
          playerMatchDeficitThreshold: 1,
        ),
      );
      final openMatchesAgainstLeader = matches.where(
        (match) =>
            !match.isResolved &&
            (match.homePlayer == caughtUpPlayer ||
                match.awayPlayer == caughtUpPlayer),
      );
      final catchUpMatches = matches.where(
        (match) =>
            !match.isResolved &&
            match.homePlayer != caughtUpPlayer &&
            match.awayPlayer != caughtUpPlayer,
      );
      String matchKey(GroupMatch match) =>
          '${match.homePlayer?.name}-${match.awayPlayer?.name}';
      final prioritizedKeys = priority.prioritizedMatches.map(matchKey).toSet();
      final deprioritizedKeys = priority.deprioritizedMatches
          .map(matchKey)
          .toSet();

      expect(
        prioritizedKeys,
        containsAll(openMatchesAgainstLeader.map(matchKey)),
      );
      expect(prioritizedKeys, containsAll(catchUpMatches.map(matchKey)));
      expect(
        deprioritizedKeys,
        unorderedEquals(openMatchesAgainstLeader.map(matchKey)),
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

  test(
    'percentage mode does not treat equal relative progress as a group deficit',
    () {
      final stage = _stageWithSizes([5, 5, 4, 4]);
      _finishCycle(stage.groups[0]);
      _finishCycle(stage.groups[1]);
      _finishPath(stage.groups[2]);
      _finishPath(stage.groups[3]);

      final priority = TournamentFlowPriority.forStage(
        stage,
        settings: const TournamentFlowPrioritySettings(
          usePercentageForGroups: true,
        ),
      );

      expect(
        priority.notices.where((notice) => notice.contains('Gruppe')),
        isEmpty,
      );
      expect(priority.prioritizedMatches, isEmpty);
    },
  );

  test(
    'percentage mode compares group progress against the longest group schedule',
    () {
      final stage = _stageWithSizes([5, 5, 4, 4]);
      _finishCycle(stage.groups[0]);
      _finishCycle(stage.groups[1]);
      _finishPath(stage.groups[2]);
      _finishCount(stage.groups[3], 5);

      final priority = TournamentFlowPriority.forStage(
        stage,
        settings: const TournamentFlowPrioritySettings(
          usePercentageForGroups: true,
        ),
      );

      expect(priority.notices, contains(contains('Gruppe C')));
      expect(priority.notices, isNot(contains(contains('Gruppe D'))));
    },
  );
}

void _finish(GroupMatch match) {
  match
    ..homeLegs = 3
    ..awayLegs = 0;
}

GroupTournamentRunStage _stage() {
  return _stageWithSizes([4, 4]);
}

GroupTournamentRunStage _stageWithSizes(List<int> sizes) {
  var playerIndex = 0;
  final groups = [
    for (var groupIndex = 0; groupIndex < sizes.length; groupIndex++)
      _group('Gruppe ${String.fromCharCode(65 + groupIndex)}', [
        for (var index = 0; index < sizes[groupIndex]; index++)
          TournamentPlayer.generated(++playerIndex),
      ]),
  ];
  return GroupTournamentRunStage(
    name: 'Gruppenphase',
    groupPlayType: 'round_robin',
    groups: groups,
    qualificationPlan: null,
    tieBreakers: defaultGroupTieBreakers,
  );
}

TournamentGroup _group(String name, List<TournamentPlayer> players) {
  return TournamentGroup(
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
}

void _finishCycle(TournamentGroup group) {
  final players = group.players;
  for (var index = 0; index < players.length - 1; index++) {
    _finishPair(group, index, index + 1);
  }
  _finishPair(group, 0, players.length - 1);
}

void _finishPath(TournamentGroup group) {
  for (var index = 0; index < group.players.length - 1; index++) {
    _finishPair(group, index, index + 1);
  }
}

void _finishCount(TournamentGroup group, int count) {
  for (final match in group.matches.take(count)) {
    _finish(match);
  }
}

void _finishPair(TournamentGroup group, int first, int second) {
  final firstPlayer = group.players[first];
  final secondPlayer = group.players[second];
  final match = group.matches.firstWhere(
    (match) =>
        (match.homePlayer == firstPlayer && match.awayPlayer == secondPlayer) ||
        (match.homePlayer == secondPlayer && match.awayPlayer == firstPlayer),
  );
  _finish(match);
}
