import 'dart:io';

import 'package:dart_tournament_manager/features/statistics/domain/best_performance.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/website/application/website_read_model_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late LocalAppDatabase database;
  late TournamentStorage tournamentStorage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('website_read_model_');
    database = LocalAppDatabase(baseDirectory: directory);
    tournamentStorage = TournamentStorage(
      file: File('${directory.path}${Platform.pathSeparator}tournaments.json'),
    );
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'publishes completed tournaments and derived private catalog data',
    () async {
      final player = await database.createPlayerProfile(
        firstName: 'Ada',
        lastName: 'Dart',
        country: 'DE',
        city: 'Berlin',
        dartsSetupJson: PlayerProfile.encodeMetadata(
          nickname: 'Ace',
          birthdate: '1990-01-01',
          autodartsName: 'private-id',
        ),
      );
      const ranking = LocalRanking(
        id: 'series-ranking',
        name: 'Vereinsserie',
        type: RankingType.series,
        participationPoints: 2,
        firstPlacePoints: 0,
        bestPerformancePoints: 0,
      );
      await database.saveLocalRanking(ranking);
      await database.setRankingPlayers(ranking.id, [player.id]);
      final opponent = TournamentPlayer(name: 'Bert', isGenerated: true);
      final participant = TournamentPlayer(
        profileId: player.id,
        name: player.displayName,
        isGenerated: false,
      );
      final match = GroupMatch(
        homePlayer: participant,
        awayPlayer: opponent,
        round: 1,
        homeLegs: 3,
        awayLegs: 1,
        finishedAt: DateTime.utc(2026, 10, 20),
        bestPerformances: [
          BestPerformance(
            type: BestPerformanceType.score180,
            playerName: player.displayName,
            playerProfileId: player.id,
            value: 180,
          ),
        ],
      );
      final completed = CreatedTournament(
        id: 'finished',
        name: 'Vereinsturnier',
        players: [participant, opponent],
        stages: const [],
        runStages: [
          GroupTournamentRunStage(
            name: 'Gruppen',
            groupPlayType: 'round_robin',
            groups: [
              TournamentGroup(
                name: 'Gruppe A',
                playType: 'round_robin',
                players: [participant, opponent],
                matches: [match],
              ),
            ],
            qualificationPlan: null,
            tieBreakers: const [],
          ),
        ],
        rankingIds: [ranking.id],
        finishedAt: DateTime.utc(2026, 10, 20),
      );
      final unfinished = CreatedTournament(
        id: 'unfinished',
        name: 'Laufendes Turnier',
        players: [participant, opponent],
        stages: const [],
        runStages: const [],
      );
      await tournamentStorage.saveTournament(completed);
      await tournamentStorage.saveTournament(unfinished);

      final model = await WebsiteReadModelService(
        database: database,
        tournamentStorage: tournamentStorage,
      ).create();

      expect(model['schemaVersion'], WebsiteReadModelService.schemaVersion);
      expect(model['players'], [
        {
          'id': player.id,
          'firstName': 'Ada',
          'lastName': 'Dart',
          'fullName': 'Ada Dart',
          'nickname': 'Ace',
          'country': 'DE',
          'city': 'Berlin',
          'createdAt': player.createdAt.toUtc().toIso8601String(),
        },
      ]);
      expect(model['rankings'], [
        {'id': ranking.id, 'name': ranking.name, 'type': 'series'},
      ]);
      expect(model['rankingStandings'], [
        {
          'rankingId': ranking.id,
          'entries': [
            {
              'position': 1,
              'playerId': player.id,
              'name': player.displayName,
              'points': 2,
              'participations': 1,
              'setsWon': 0,
              'firstPlaces': 0,
              'secondPlaces': 0,
              'thirdPlaces': 0,
              'bestPerformances': 1,
            },
          ],
        },
      ]);
      expect(model['completedTournaments'], hasLength(1));
      expect((model['completedTournaments'] as List).single['id'], 'finished');
      expect(WebsiteReadModelService.createTournamentIndex(model), {
        'schemaVersion': 1,
        'generatedAt': model['generatedAt'],
        'completedTournaments': [
          {
            'id': 'finished',
            'name': 'Vereinsturnier',
            'finishedAt': '2026-10-20T00:00:00.000Z',
            'startedAt': null,
            'createdAt':
                (model['completedTournaments'] as List).single['createdAt'],
            'playerCount': 2,
            'matchCount': 1,
            'mode': 'groups:round_robin',
            'hasImportedArchive': false,
          },
        ],
      });
      expect(model['statistics'], [
        {
          'playerId': player.id,
          'tournaments': 1,
          'matches': 1,
          'wins': 1,
          'losses': 0,
          'draws': 0,
          'tournamentWins': 0,
          'legsWon': 3,
          'legsLost': 1,
          'legsDrawn': 0,
          'setsWon': 0,
          'setsLost': 0,
        },
      ]);
      expect(model['bestPerformances'], [
        {
          'type': 'score180',
          'playerName': 'Ada Dart',
          'playerProfileId': player.id,
          'value': 180,
          'playerId': player.id,
        },
      ]);
      final serialized = model.toString();
      expect(serialized, isNot(contains('1990-01-01')));
      expect(serialized, isNot(contains('private-id')));
      expect(serialized, isNot(contains('dartsSetupJson')));
    },
  );

  test('does not expose a reopened tournament until it is finalized', () {
    final tournament = CreatedTournament(
      name: 'Korrigierbares Turnier',
      players: const [],
      stages: const [],
      runStages: const [],
      finishedAt: DateTime.utc(2026, 10, 20),
      reopenedForCorrections: true,
    );

    expect(WebsiteReadModelService.completedTournaments([tournament]), isEmpty);
  });
}
