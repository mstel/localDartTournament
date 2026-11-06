import 'dart:convert';
import 'dart:io';

import 'package:dart_tournament_manager/features/statistics/domain/best_performance.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy 170+ data migrates to the 171+ category', () {
    final migrated = BestPerformance.fromJson({
      'type': 'score170',
      'playerName': 'Spieler 1',
      'value': 170,
    });

    expect(migrated.type, BestPerformanceType.score171Plus);
    expect(migrated.normalizedType, BestPerformanceType.score171Plus);
    expect(migrated.label, '171+');
    expect(migrated.value, isNull);
    expect(migrated.toJson()['type'], 'score171Plus');
  });

  test('new best performance categories preserve bullseye text', () {
    const performance = BestPerformance(
      type: BestPerformanceType.bullseyeFinish,
      playerName: 'Spieler 1',
      details: 'Bullseye',
    );

    final restored = BestPerformance.fromJson(performance.toJson());
    expect(restored.type, BestPerformanceType.bullseyeFinish);
    expect(restored.label, 'Bullseye Finish');
    expect(restored.details, 'Bullseye');
  });

  test('match best performances survive local tournament JSON roundtrip', () {
    final match = GroupMatch(
      homePlayer: TournamentPlayer(
        profileId: 'player-1',
        name: 'Spieler 1',
        isGenerated: false,
      ),
      awayPlayer: TournamentPlayer(
        profileId: 'player-2',
        name: 'Spieler 2',
        isGenerated: false,
      ),
      round: 1,
      homeLegs: 2,
      awayLegs: 0,
      bestPerformances: const [
        BestPerformance(
          type: BestPerformanceType.score180,
          playerName: 'Spieler 1',
          playerProfileId: 'player-1',
        ),
        BestPerformance(
          type: BestPerformanceType.highFinish,
          playerName: 'Spieler 2',
          playerProfileId: 'player-2',
          value: 120,
        ),
      ],
    );

    final restored = GroupMatch.fromJson(match.toJson());

    expect(restored.bestPerformances, hasLength(2));
    expect(restored.bestPerformances.first.type, BestPerformanceType.score180);
    expect(restored.bestPerformances.last.playerProfileId, 'player-2');
    expect(restored.bestPerformances.last.value, 120);
  });

  test(
    'tournament storage upgrades persisted legacy 170+ performances',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'best_performance_migration_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(
        '${directory.path}${Platform.pathSeparator}tournaments.json',
      );
      final match = GroupMatch(
        homePlayer: TournamentPlayer(
          profileId: 'player-1',
          name: 'Spieler 1',
          isGenerated: false,
        ),
        awayPlayer: TournamentPlayer(
          profileId: 'player-2',
          name: 'Spieler 2',
          isGenerated: false,
        ),
        round: 1,
        bestPerformances: const [
          BestPerformance(
            type: BestPerformanceType.score170,
            playerName: 'Spieler 1',
            value: 170,
          ),
        ],
      );
      final tournament = CreatedTournament(
        name: 'Migrationstest',
        players: [match.homePlayer!, match.awayPlayer!],
        stages: const [],
        runStages: [
          KnockoutTournamentRunStage(
            name: 'Finale',
            rounds: [
              [match],
            ],
          ),
        ],
      );
      final legacyTournament = tournament.toJson();
      final stages = legacyTournament['runStages'] as List;
      final firstStage = stages.first as Map<String, dynamic>;
      final rounds = firstStage['rounds'] as List;
      final firstRound = rounds.first as List;
      final serializedMatch = firstRound.first as Map<String, dynamic>;
      final performances = serializedMatch['bestPerformances'] as List;
      (performances.first as Map<String, dynamic>)
        ..['type'] = 'score170'
        ..['value'] = 170;
      await file.writeAsString(
        jsonEncode({
          'schemaVersion': 32,
          'tournaments': [legacyTournament],
        }),
      );

      final restored = (await TournamentStorage(
        file: file,
      ).loadTournaments()).single;
      final restoredMatch =
          (restored.runStages.single as KnockoutTournamentRunStage)
              .matches
              .single;
      expect(
        restoredMatch.bestPerformances.single.type,
        BestPerformanceType.score171Plus,
      );

      final upgradedDocument =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(upgradedDocument['schemaVersion'], 39);
      final upgradedTournament =
          (upgradedDocument['tournaments'] as List).single
              as Map<String, dynamic>;
      final upgradedStage =
          (upgradedTournament['runStages'] as List).first
              as Map<String, dynamic>;
      final upgradedMatch =
          ((upgradedStage['rounds'] as List).first as List).first
              as Map<String, dynamic>;
      final upgradedPerformance =
          (upgradedMatch['bestPerformances'] as List).single
              as Map<String, dynamic>;
      expect(upgradedPerformance['type'], 'score171Plus');
      expect(upgradedPerformance.containsKey('value'), isFalse);
      expect(File('${file.path}.v32.bak').existsSync(), isTrue);
    },
  );
}
