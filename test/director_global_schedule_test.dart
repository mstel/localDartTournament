import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/league/domain/league_match.dart';
import 'package:dart_tournament_manager/features/tournaments/application/order_of_play/global_order_of_play_service.dart';
import 'package:dart_tournament_manager/features/tournaments/application/order_of_play/order_of_play_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_director_snapshot.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

CreatedTournament twoGroupFixture({int boards = 3, LeagueMatch? leagueMatch}) {
  final players = [for (var i = 1; i <= 8; i++) TournamentPlayer.generated(i)];
  GroupTournamentRunStage stage(String name, List<TournamentPlayer> members) =>
      GroupTournamentRunStage(
        name: name,
        groupPlayType: 'round_robin',
        qualificationPlan: null,
        tieBreakers: defaultGroupTieBreakers,
        groups: [
          TournamentGroup(
            name: name,
            playType: 'round_robin',
            players: members,
            matches: [
              for (var a = 0; a < members.length; a++)
                for (var b = a + 1; b < members.length; b++)
                  GroupMatch(
                    homePlayer: members[a],
                    awayPlayer: members[b],
                    round: 1,
                  ),
            ],
          ),
        ],
      );
  return CreatedTournament(
    id: 'director-global-schedule-${boards.toString()}-${leagueMatch != null}',
    name: 'Test',
    players: players,
    stages: const [],
    boardCount: boards,
    leagueMatch: leagueMatch,
    runStages: [
      stage('A', players.sublist(0, 4)),
      stage('B', players.sublist(4, 8)),
    ],
  );
}

void main() {
  const controller = OrderOfPlayController();

  setUp(() => GlobalOrderOfPlayService.instance.invalidateAll());

  test('fixed + global shows a flat, collision-free fixed list', () {
    final t = twoGroupFixture(boards: 3)
      ..directorModeEnabled = true
      ..directorSchedulingStrategy = 'global'
      ..directorPlayOrderMode = 'fixed_schedule';
    controller.initializeFixedSchedule(t);

    final snapshot = TournamentDirectorSnapshot(t, 0);
    final overview = snapshot.scheduleOverview;
    expect(overview.presentation, DirectorSchedulePresentation.globalFlat);
    expect(overview.showBoardLabels, isFalse);
    expect(overview.note, isNotNull);
    expect(overview.suggestions, isNotEmpty);
    expect(overview.groups, isEmpty);

    final playerIds = overview.suggestions
        .expand((assignment) => assignment.entry.players)
        .toList();
    expect(playerIds.toSet(), hasLength(playerIds.length));
    for (final assignment in overview.suggestions) {
      expect(snapshot.suggestionsForBoard(assignment.board), hasLength(1));
    }
  });

  test('fixed + group keeps the complete group schedule with board labels', () {
    final t = twoGroupFixture(boards: 2)
      ..directorModeEnabled = true
      ..directorSchedulingStrategy = 'group'
      ..directorPlayOrderMode = 'fixed_schedule'
      ..directorGroupBoardAssignments['0:A'] = [1]
      ..directorGroupBoardAssignments['1:B'] = [2];
    controller.initializeFixedSchedule(t);

    final overview = TournamentDirectorSnapshot(t, 0).scheduleOverview;
    expect(overview.presentation, DirectorSchedulePresentation.groupFull);
    expect(overview.showBoardLabels, isTrue);
    expect(overview.groups['0:A'], isNotEmpty);
    expect(overview.suggestions, isEmpty);
  });

  test('dynamic + group only exposes the first suggestion per board', () {
    final t = twoGroupFixture(boards: 3)
      ..directorModeEnabled = true
      ..directorSchedulingStrategy = 'group'
      ..directorPlayOrderMode = 'dynamic';
    final snapshot = TournamentDirectorSnapshot(t, 0);

    expect(snapshot.suggestionsForBoard(1, limit: 5), hasLength(1));
    final overview = snapshot.scheduleOverview;
    expect(overview.presentation, DirectorSchedulePresentation.groupFirstOnly);
    expect(overview.note, 'Rest wird dynamisch berechnet');
    expect(overview.groups.keys, contains('0:A'));
    for (final assignments in overview.groups.values) {
      expect(assignments.length, lessThanOrEqualTo(2));
    }
  });

  test('dynamic + global keeps board suggestions stable until a result', () {
    final t = twoGroupFixture(boards: 3)
      ..directorModeEnabled = true
      ..directorSchedulingStrategy = 'global'
      ..directorPlayOrderMode = 'dynamic';
    final before = TournamentDirectorSnapshot(t, 0);
    final boardSuggestions = before.globalBoardSuggestions();
    expect(boardSuggestions, isNotEmpty);
    final generation = GlobalOrderOfPlayService.instance.generation(t, 0);

    final board = boardSuggestions.keys.first;
    final match = boardSuggestions[board]!;
    expect(controller.start(t, 0, match, board), isTrue);

    // Starting a match is not a result: the published suggestions stay put.
    expect(
      GlobalOrderOfPlayService.instance.boardSuggestions(t, 0),
      boardSuggestions,
    );
    expect(GlobalOrderOfPlayService.instance.generation(t, 0), generation);

    match
      ..homeLegs = 1
      ..awayLegs = 0;
    controller.resultRecorded(match);

    final after = GlobalOrderOfPlayService.instance.boardSuggestions(t, 0);
    expect(
      GlobalOrderOfPlayService.instance.generation(t, 0),
      greaterThan(generation),
    );
    expect(after[board], isNot(same(match)));
    expect(
      GlobalOrderOfPlayService.instance.remainingQueue(t, 0),
      isNot(contains(match)),
    );

    final overview = TournamentDirectorSnapshot(t, 0).scheduleOverview;
    expect(overview.presentation, DirectorSchedulePresentation.globalPerBoard);
    expect(overview.showBoardLabels, isFalse);
    expect(overview.note, contains('dynamisch berechnet'));
    expect(
      overview.suggestions
          .expand((assignment) => assignment.entry.players)
          .toSet()
          .length,
      overview.suggestions
          .expand((assignment) => assignment.entry.players)
          .length,
    );
  });

  test('fewest-match hint lists comma-separated player names', () {
    final t = twoGroupFixture(boards: 2)
      ..directorModeEnabled = true
      ..directorSchedulingStrategy = 'group'
      ..directorPlayOrderMode = 'dynamic';
    final snapshot = TournamentDirectorSnapshot(t, 0);
    final entry = snapshot.schedule.planned.first.entry;
    final names = snapshot.fewestMatchesPlayerNames(entry);
    expect(names, isNotEmpty);
    expect(snapshot.fewestMatchesLabel(entry), names.join(', '));
  });

  test('league tournaments keep the unchanged schedule presentation', () {
    final league = LeagueMatch.rhl(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: ['A', 'B', 'C', 'D'],
      awayPlayers: ['E', 'F', 'G', 'H'],
    );
    final t = twoGroupFixture(boards: 3, leagueMatch: league)
      ..directorModeEnabled = true
      ..directorSchedulingStrategy = 'global'
      ..directorPlayOrderMode = 'fixed_schedule';
    controller.initializeFixedSchedule(t);

    final snapshot = TournamentDirectorSnapshot(t, 0);
    expect(snapshot.isNormalRanking, isFalse);
    expect(
      snapshot.scheduleOverview.presentation,
      DirectorSchedulePresentation.unchanged,
    );
    expect(snapshot.hideScheduleBoardLabels, isFalse);
    expect(snapshot.globalBoardSuggestions(), isEmpty);
    expect(snapshot.flatGlobalFixedSuggestions(), isEmpty);
  });
}
