import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/league/domain/league_match.dart';
import 'package:dart_tournament_manager/features/tournaments/application/order_of_play/global_order_of_play_service.dart';
import 'package:dart_tournament_manager/features/tournaments/application/order_of_play/order_of_play_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_director_snapshot.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/engines/global_waitlist_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

CreatedTournament oneStageFixture({int boards = 3}) {
  final players = [for (var i = 1; i <= 12; i++) TournamentPlayer.generated(i)];
  TournamentGroup group(String name, List<TournamentPlayer> members) =>
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
      );
  return CreatedTournament(
    id: 'director-global-one-stage',
    name: 'Test',
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

void _initializeWaitlist(CreatedTournament t, int stage) {
  final snapshot = TournamentDirectorSnapshot(t, stage);
  const OrderOfPlayController().initializeGlobalWaitlist(
    t,
    stage,
    allEntries: snapshot.entries,
    schedule: snapshot.schedule,
    isPreviewable: snapshot.isPreviewableMatch,
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
      // A flat global plan offers every collision-free match on every free
      // board; the simulator board is not a reservation.
      expect(
        snapshot.suggestionsForBoard(assignment.board),
        hasLength(overview.suggestions.length),
      );
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

  test('legacy dynamic + group is evaluated as the global waitlist', () {
    final t = twoGroupFixture(boards: 3)
      ..directorModeEnabled = true
      ..directorSchedulingStrategy = 'group'
      ..directorPlayOrderMode = 'dynamic';
    expect(const GlobalWaitlistEngine().applies(t), isTrue);

    _initializeWaitlist(t, 0);
    final waitlist = TournamentDirectorSnapshot(t, 0).globalWaitlist;
    // Only one stage with four players is open, so at most two disjoint
    // pairings can form the collision-free preview.
    expect(waitlist.fixed, hasLength(2));
    expect(waitlist.fixed.map((entry) => entry.match).toSet(), hasLength(2));
  });

  test(
    'dynamic + global keeps one shared fixed preview and refills after start',
    () {
      final t = oneStageFixture(boards: 3)
        ..directorModeEnabled = true
        ..directorSchedulingStrategy = 'global'
        ..directorPlayOrderMode = 'dynamic';
      _initializeWaitlist(t, 0);
      final before = TournamentDirectorSnapshot(t, 0);
      final overview = before.scheduleOverview;
      expect(
        overview.presentation,
        DirectorSchedulePresentation.globalWaitlist,
      );
      expect(overview.showBoardLabels, isFalse);
      expect(overview.note, contains('nächste freie Board'));
      expect(before.globalWaitlist.fixed, hasLength(4));

      final fixedMatches = before.globalWaitlist.fixed
          .map((entry) => entry.match)
          .toList();
      final generation = GlobalOrderOfPlayService.instance.generation(t, 0);
      final first = fixedMatches.first;
      expect(controller.start(t, 0, first, 1), isTrue);

      // A start moves the remaining fixed matches up and refills the preview
      // from the optimised area. No board is assigned in advance.
      final afterStart = TournamentDirectorSnapshot(t, 0);
      expect(afterStart.globalWaitlist.fixed, hasLength(4));
      expect(afterStart.globalWaitlist.fixed.first.match, isNot(same(first)));
      expect(
        afterStart.globalWaitlist.fixed.map((entry) => entry.match),
        isNot(contains(first)),
      );
      expect(GlobalOrderOfPlayService.instance.generation(t, 0), generation);

      first
        ..homeLegs = 1
        ..awayLegs = 0;
      controller.resultRecorded(first);
      expect(
        GlobalOrderOfPlayService.instance.generation(t, 0),
        greaterThan(generation),
      );
      expect(
        GlobalOrderOfPlayService.instance.remainingQueue(t, 0),
        isNot(contains(first)),
      );
      expect(
        afterStart.globalWaitlist.fixed
            .expand((entry) => entry.players)
            .toSet()
            .length,
        afterStart.globalWaitlist.fixed.expand((entry) => entry.players).length,
      );
    },
  );

  test(
    'fixed + global suggests matches on every free board while one runs',
    () {
      final t = oneStageFixture(boards: 4)
        ..directorModeEnabled = true
        ..directorSchedulingStrategy = 'global'
        ..directorPlayOrderMode = 'fixed_schedule';
      controller.initializeFixedSchedule(t);
      final runningMatch = controller.plan(t, 0).planned.first.entry.match;
      expect(controller.start(t, 0, runningMatch, 1), isTrue);

      final snapshot = TournamentDirectorSnapshot(t, 0);
      expect(snapshot.flatGlobalFixedSuggestions(), isNotEmpty);
      expect(snapshot.suggestionsForBoard(1), isEmpty);
      for (final board in [2, 3, 4]) {
        final suggestions = snapshot.suggestionsForBoard(board);
        expect(suggestions, isNotEmpty);
        expect(
          suggestions.every((assignment) => assignment.board == board),
          isTrue,
        );
        expect(
          suggestions
              .expand((assignment) => assignment.entry.players)
              .toSet()
              .length,
          suggestions.expand((assignment) => assignment.entry.players).length,
        );
        expect(
          suggestions.map((assignment) => assignment.entry.match),
          isNot(contains(runningMatch)),
        );
      }
    },
  );

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
