import 'dart:convert';

import 'package:dart_tournament_manager/features/tournaments/application/order_of_play/order_of_play_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_director_snapshot.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

CreatedTournament _fixture({int boards = 3}) {
  final players = [
    for (var index = 1; index <= 12; index++)
      TournamentPlayer.generated(index).copyWith(name: 'Spieler $index'),
  ];
  TournamentGroup group(String name, List<TournamentPlayer> members) =>
      TournamentGroup(
        name: name,
        playType: 'round_robin',
        players: members,
        matches: [
          for (var home = 0; home < members.length; home++)
            for (var away = home + 1; away < members.length; away++)
              GroupMatch(
                homePlayer: members[home],
                awayPlayer: members[away],
                round: home + away + 1,
              ),
        ],
      );
  return CreatedTournament(
    id: 'director-snapshot-test-$boards',
    name: 'Leitung',
    players: players,
    stages: const [],
    boardCount: boards,
    runStages: [
      GroupTournamentRunStage(
        name: 'Gruppenphase',
        groupPlayType: 'round_robin',
        qualificationPlan: null,
        tieBreakers: defaultGroupTieBreakers,
        groups: [
          group('A', players.sublist(0, 4)),
          group('B', players.sublist(4, 8)),
          group('C', players.sublist(8, 12)),
        ],
      ),
    ],
  );
}

CreatedTournament _dynamicGlobal({int boards = 3}) => _fixture(boards: boards)
  ..directorModeEnabled = true
  ..directorSchedulingStrategy = 'global'
  ..directorPlayOrderMode = 'dynamic';

void _initializeWaitlist(CreatedTournament tournament) {
  const controller = OrderOfPlayController();
  controller.initializeGlobalWaitlist(
    tournament,
    0,
    allEntries: controller.entries(tournament),
    schedule: controller.plan(tournament, 0),
    isPreviewable: (match) => !match.hasTeamParticipant,
  );
}

void main() {
  const controller = OrderOfPlayController();

  test('constructing and reading the snapshot never persists the waitlist', () {
    final tournament = _dynamicGlobal();
    final before = jsonEncode(tournament.directorGlobalWaitlist.toJson());

    final snapshot = TournamentDirectorSnapshot(tournament, 0);
    expect(snapshot.globalWaitlist, isNotNull);
    expect(snapshot.scheduleOverview, isNotNull);
    expect(snapshot.waitlistPreviewEntries(), isNotNull);
    expect(snapshot.suggestionsForBoard(1), isNotNull);

    expect(jsonEncode(tournament.directorGlobalWaitlist.toJson()), before);
  });

  test('fixed + global suggests later blocks that are playable now', () {
    final tournament = _fixture()
      ..directorModeEnabled = true
      ..directorSchedulingStrategy = 'global'
      ..directorPlayOrderMode = 'fixed_schedule';
    controller.initializeFixedSchedule(tournament);

    final snapshot = TournamentDirectorSnapshot(tournament, 0);
    final laterPlanned = snapshot.schedule.planned.where(
      (assignment) =>
          assignment.entry.stageIndex == 0 &&
          assignment.block > 0 &&
          assignment.entry.match.hasPlayers,
    );
    expect(laterPlanned, isNotEmpty);

    final suggestions = snapshot.flatGlobalFixedSuggestions();
    final later = suggestions.firstWhere(
      (assignment) => assignment.entry.stageIndex == 0 && assignment.block > 0,
    );
    expect(suggestions, contains(later));
    final players = suggestions.expand((item) => item.entry.players).toList();
    expect(players.toSet(), hasLength(players.length));
    expect(
      snapshot
          .suggestionsForBoard(2, limit: 16)
          .map((assignment) => assignment.entry.match),
      contains(later.entry.match),
    );
  });

  test('dynamic suggestions skip a busy preview entry on a free board', () {
    final tournament = _dynamicGlobal();
    _initializeWaitlist(tournament);
    final preview = TournamentDirectorSnapshot(tournament, 0).globalWaitlist;
    final previewed = preview.fixed.first;
    final fixedMatches = preview.fixed.map((entry) => entry.match).toSet();
    final outOfOrder = controller
        .entries(tournament)
        .firstWhere(
          (entry) =>
              entry.stageIndex == 0 &&
              entry.match.hasPlayers &&
              !entry.match.isResolved &&
              !fixedMatches.contains(entry.match) &&
              entry.players.any(previewed.players.contains),
        )
        .match;
    // The running match is not part of the fixed preview, but it blocks a
    // previewed entry that shares a player with it.
    expect(controller.start(tournament, 0, outOfOrder, 1), isTrue);

    final snapshot = TournamentDirectorSnapshot(tournament, 0);
    final waitlist = snapshot.globalWaitlist;
    final skipped = waitlist.skipped.map((entry) => entry.match).toSet();
    expect(skipped, contains(previewed.match));

    // The running board cannot take another match; every other free board can.
    expect(snapshot.suggestionsForBoard(1), isEmpty);
    final next = snapshot.suggestionsForBoard(2);
    expect(next, hasLength(1));
    expect(next.single.board, 2);
    expect(next.single.entry.match, isNot(previewed.match));
    expect(skipped.contains(next.single.entry.match), isFalse);

    // Busy entries stay visible for display, but carry the skipped marker.
    expect(
      snapshot.waitlistPreviewEntries().map((item) => item.entry.match),
      contains(previewed.match),
    );
    expect(
      snapshot.scheduleOverview.skippedPreviewMatches,
      contains(previewed.match),
    );
    expect(
      snapshot.scheduleOverview.skippedPreviewNote,
      'vorläufig übersprungen',
    );
  });

  test('there is no dynamic + group presentation any more', () {
    final tournament = _fixture()
      ..directorModeEnabled = true
      ..directorSchedulingStrategy = 'group'
      ..directorPlayOrderMode = 'dynamic';
    final snapshot = TournamentDirectorSnapshot(tournament, 0);

    expect(snapshot.usesGlobalWaitlist, isTrue);
    final overview = snapshot.scheduleOverview;
    expect(
      overview.presentation,
      isNot(DirectorSchedulePresentation.groupFirstOnly),
    );
    expect(overview.groups, isEmpty);
    expect(overview.showBoardLabels, isFalse);
    // Even a legacy group strategy cannot reintroduce board-local planning.
    expect(snapshot.usesGlobalBoardPool, isTrue);
    expect(snapshot.globalBoardAssignments(), isNotEmpty);
  });
}
