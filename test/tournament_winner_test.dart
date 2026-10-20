import 'dart:io';

import 'package:dart_tournament_manager/features/statistics/domain/local_statistics.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/imported_tournament_archive.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_winner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only the actual first place counts in win chance', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tournament_winner_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final database = LocalAppDatabase(
      baseDirectory: Directory('${directory.path}/database'),
    );
    final storage = TournamentStorage(
      file: File('${directory.path}${Platform.pathSeparator}tournaments.json'),
    );
    final annaProfile = await database.createPlayerProfile(displayName: 'Anna');
    final benProfile = await database.createPlayerProfile(displayName: 'Ben');
    final thirdProfile = await database.createPlayerProfile(
      displayName: 'Caro',
    );
    final anna = TournamentPlayer(
      profileId: annaProfile.id,
      name: annaProfile.displayName,
      isGenerated: false,
    );
    final ben = TournamentPlayer(
      profileId: benProfile.id,
      name: benProfile.displayName,
      isGenerated: false,
    );
    final caro = TournamentPlayer(
      profileId: thirdProfile.id,
      name: thirdProfile.displayName,
      isGenerated: false,
    );

    final annaWinner = _groupTournament('anna-wins', anna, ben, caro);
    final benWinner = _groupTournament('ben-wins', ben, anna, caro);
    final tiedTournament = _drawGroupTournament(anna, ben);
    final imported = CreatedTournament(
      id: 'challonge-placement',
      name: 'Imported tournament',
      players: [anna, ben],
      stages: const [],
      runStages: const [],
      importedArchive: ImportedTournamentArchive(
        sourceId: 'external-1',
        url: 'https://challonge.com/external-1',
        mode: 'single elimination',
        participants: [
          {
            'id': '1',
            'name': 'Anna',
            'profileId': annaProfile.id,
            'finalRank': 1,
          },
          {
            'id': '2',
            'name': 'Ben',
            'profileId': benProfile.id,
            'finalRank': 2,
          },
        ],
        matches: const [
          {'winner_id': '2'},
        ],
      ),
    );

    expect(TournamentWinner.profileId(annaWinner), annaProfile.id);
    expect(TournamentWinner.profileId(benWinner), benProfile.id);
    expect(TournamentWinner.profileId(tiedTournament), isNull);
    expect(TournamentWinner.profileId(imported), annaProfile.id);
    await storage.saveTournament(annaWinner);
    await storage.saveTournament(benWinner);
    await storage.saveTournament(imported);

    final stats = await LocalStatisticsService(
      database: database,
      storage: storage,
    ).forPlayers({annaProfile.id});

    expect(stats.tournaments, 3);
    expect(stats.tournamentWins, 2);
    expect(stats.tournamentWinRate, closeTo(200 / 3, 0.01));
  });

  test(
    'legacy normal tournaments stay excluded unless a ranking was assigned',
    () {
      final normal = CreatedTournament.fromJson(_legacyJson('legacy-normal'));
      final assigned = CreatedTournament.fromJson({
        ..._legacyJson('legacy-assigned'),
        'rankingIds': ['club-ranking'],
      });

      expect(normal.countsForRanking, isFalse);
      expect(normal.toJson()['countsForRanking'], isFalse);
      expect(assigned.countsForRanking, isTrue);
      assigned.rankingIds.add('another-ranking');
      expect(assigned.rankingIds, ['club-ranking', 'another-ranking']);
    },
  );

  test('ranking assignment from a loaded tournament persists', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ranking_assignment_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final storage = TournamentStorage(
      file: File('${directory.path}${Platform.pathSeparator}tournaments.json'),
    );
    final tournament = CreatedTournament.fromJson(_legacyJson('loaded-normal'));
    await storage.saveTournament(tournament);

    final loaded = (await storage.loadTournaments()).single;
    loaded
      ..countsForRanking = true
      ..rankingIds.add('club-ranking');
    await storage.saveTournament(loaded);

    final restored = (await storage.loadTournaments()).single;
    expect(restored.countsForRanking, isTrue);
    expect(restored.rankingIds, ['club-ranking']);
  });
}

CreatedTournament _drawGroupTournament(
  TournamentPlayer first,
  TournamentPlayer second,
) {
  final group = TournamentGroup(
    name: 'Group',
    playType: 'round_robin',
    players: [first, second],
    matches: [_result(first, second, 1, 1)],
  );
  return CreatedTournament(
    name: 'Tied tournament',
    players: [first, second],
    stages: const [],
    runStages: [
      GroupTournamentRunStage(
        name: 'Final standings',
        groupPlayType: 'round_robin',
        groups: [group],
        qualificationPlan: null,
        tieBreakers: const ['points', 'legDifference', 'legsFor'],
      ),
    ],
    completedStageIndexes: {0},
  );
}

CreatedTournament _groupTournament(
  String id,
  TournamentPlayer winner,
  TournamentPlayer second,
  TournamentPlayer third,
) {
  final matches = [
    _result(winner, second, 2, 0),
    _result(second, third, 2, 0),
    _result(winner, third, 2, 0),
  ];
  final group = TournamentGroup(
    name: 'Group',
    playType: 'round_robin',
    players: [winner, second, third],
    matches: matches,
  );
  return CreatedTournament(
    id: id,
    name: id,
    players: [winner, second, third],
    stages: const [],
    runStages: [
      GroupTournamentRunStage(
        name: 'Final standings',
        groupPlayType: 'round_robin',
        groups: [group],
        qualificationPlan: null,
        tieBreakers: const ['points', 'legDifference', 'legsFor'],
      ),
    ],
    completedStageIndexes: {0},
  );
}

GroupMatch _result(
  TournamentPlayer home,
  TournamentPlayer away,
  int homeLegs,
  int awayLegs,
) => GroupMatch(
  homePlayer: home,
  awayPlayer: away,
  round: 1,
  homeLegs: homeLegs,
  awayLegs: awayLegs,
);

Map<String, dynamic> _legacyJson(String id) => {
  'id': id,
  'name': id,
  'createdAt': DateTime(2026).toIso8601String(),
  'updatedAt': DateTime(2026).toIso8601String(),
  'players': const [],
  'stages': const [],
  'runStages': const [],
};
