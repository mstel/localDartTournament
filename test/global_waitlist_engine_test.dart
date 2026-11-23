import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/application/order_of_play/order_of_play_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_director_snapshot.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/global_waitlist_state.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

CreatedTournament _threeGroupFixture() {
  final players = [for (var i = 1; i <= 15; i++) TournamentPlayer.generated(i)];
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
    id: 'global-waitlist-engine-test',
    name: 'Warteliste',
    players: players,
    stages: const [],
    boardCount: 4,
    runStages: [
      GroupTournamentRunStage(
        name: 'Gruppenphase',
        groupPlayType: 'round_robin',
        qualificationPlan: null,
        tieBreakers: defaultGroupTieBreakers,
        groups: [
          group('A', players.sublist(0, 4)),
          group('B', players.sublist(4, 9)),
          group('C', players.sublist(9, 15)),
        ],
      ),
    ],
  )..directorModeEnabled = true;
}

List<GroupMatch> _groupMatches(CreatedTournament t, String groupName) {
  final stage = t.runStages.single as GroupTournamentRunStage;
  return stage.groups.singleWhere((group) => group.name == groupName).matches;
}

void _resolve(GroupMatch match) {
  match
    ..homeLegs = 1
    ..awayLegs = 0;
}

void main() {
  const controller = OrderOfPlayController();

  CreatedTournament dynamicGlobal() => _threeGroupFixture()
    ..directorSchedulingStrategy = 'global'
    ..directorPlayOrderMode = 'dynamic';

  test(
    'fixed preview is stable across reads and free of player collisions',
    () {
      final t = dynamicGlobal();
      final first = TournamentDirectorSnapshot(t, 0);
      first.globalWaitlist;
      final keys = t.directorGlobalWaitlist.fixedKeys(0);
      expect(keys, hasLength(GlobalWaitlistState.defaultFixedCount));
      expect(
        TournamentDirectorSnapshot(
          t,
          0,
        ).globalWaitlist.fixed.map((entry) => entry.match),
        orderedEquals(first.globalWaitlist.fixed.map((entry) => entry.match)),
      );

      final players = first.globalWaitlist.fixed
          .expand((entry) => entry.players)
          .toList();
      expect(players.toSet(), hasLength(players.length));
      expect(
        first.scheduleOverview.note,
        'Die nächste Begegnung kommt an das nächste freie Board.',
      );
    },
  );

  test('starting the top match refills the preview from the dynamic area', () {
    final t = dynamicGlobal();
    final snapshot = TournamentDirectorSnapshot(t, 0);
    final previous = snapshot.globalWaitlist.fixed.map((e) => e.match).toList();
    final dynamicMatches = snapshot.globalWaitlist.dynamic
        .map((entry) => entry.match)
        .toList();
    final started = previous.first;
    expect(controller.start(t, 0, started, 1), isTrue);

    final refreshed = TournamentDirectorSnapshot(t, 0).globalWaitlist;
    expect(refreshed.fixed, hasLength(GlobalWaitlistState.defaultFixedCount));
    expect(
      refreshed.fixed.map((entry) => entry.match),
      isNot(contains(started)),
    );
    expect(
      refreshed.fixed.map((entry) => entry.match).toSet(),
      previous.skip(1).toSet().union({
        refreshed.fixed.map((entry) => entry.match).last,
      }),
    );
    expect(
      dynamicMatches,
      contains(refreshed.fixed.last.match),
      reason: 'Der Nachschub kommt aus dem dynamisch optimierten Bereich.',
    );
    final players = refreshed.fixed.expand((entry) => entry.players).toList();
    expect(players.toSet(), hasLength(players.length));
  });

  test(
    'relative group progress prioritises the group with the largest deficit',
    () {
      final t = dynamicGlobal();
      for (final match in _groupMatches(t, 'A').take(3)) {
        _resolve(match);
      }
      for (final match in _groupMatches(t, 'B').take(5)) {
        _resolve(match);
      }
      for (final match in _groupMatches(t, 'C').take(6)) {
        _resolve(match);
      }

      final progress = TournamentDirectorSnapshot(
        t,
        0,
      ).globalWaitlist.groupProgress;
      expect(progress.map((group) => group.label), contains('Gruppe C'));
      expect(progress.first.label, 'Gruppe C');
      expect(
        progress.map((group) => group.progressLabel),
        containsAll([
          '3 von 6 Partien · 50 %',
          '5 von 10 Partien · 50 %',
          '6 von 15 Partien · 40 %',
        ]),
      );
      expect(
        progress
            .where((group) => group.progressLabel.endsWith('50 %'))
            .map((group) => group.total),
        [10, 6],
      );
    },
  );

  test('fixed preview survives JSON round trip and storage reload', () async {
    final t = dynamicGlobal();
    TournamentDirectorSnapshot(t, 0).globalWaitlist;
    final state = t.directorGlobalWaitlist;
    expect(state.hasPersistedData, isTrue);

    final decoded = GlobalWaitlistState.fromJson(
      jsonDecode(jsonEncode(state.toJson())),
    );
    expect(decoded.fixedCount, state.fixedCount);
    expect(decoded.fixedKeys(0), state.fixedKeys(0));

    final dir = await Directory.systemTemp.createTemp('global_waitlist_test');
    addTearDown(() => dir.delete(recursive: true));
    final storage = TournamentStorage(
      file: File('${dir.path}/tournaments.json'),
    );
    await storage.saveTournament(t);
    final reloaded = (await storage.loadTournaments()).single;
    expect(reloaded.directorGlobalWaitlist.fixedKeys(0), state.fixedKeys(0));
    expect(
      TournamentDirectorSnapshot(
        reloaded,
        0,
      ).globalWaitlist.fixed.map((entry) => entry.match.label),
      orderedEquals(
        TournamentDirectorSnapshot(
          t,
          0,
        ).globalWaitlist.fixed.map((entry) => entry.match.label),
      ),
    );
  });

  test('other director modes keep their existing planning behaviour', () {
    final grouped = _threeGroupFixture()
      ..directorSchedulingStrategy = 'group'
      ..directorPlayOrderMode = 'dynamic';
    final fixed = _threeGroupFixture()
      ..directorSchedulingStrategy = 'global'
      ..directorPlayOrderMode = 'fixed_schedule';
    for (final t in [grouped, fixed]) {
      final snapshot = TournamentDirectorSnapshot(t, 0);
      expect(snapshot.usesGlobalWaitlist, isFalse);
      expect(snapshot.globalWaitlist.fixed, isEmpty);
      expect(
        snapshot.scheduleOverview.presentation,
        isNot(DirectorSchedulePresentation.globalWaitlist),
      );
    }
  });
}
