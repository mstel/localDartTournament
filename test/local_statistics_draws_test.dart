import 'dart:io';

import 'package:dart_tournament_manager/features/statistics/domain/local_statistics.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allowed tied match is a draw, never a drawn leg', () async {
    final directory = await Directory.systemTemp.createTemp(
      'local_statistics_draws_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final database = LocalAppDatabase(baseDirectory: directory);
    final homeProfile = await database.createPlayerProfile(
      displayName: 'Alex Dart',
    );
    final awayProfile = await database.createPlayerProfile(
      displayName: 'Robin Pfeil',
    );
    final home = TournamentPlayer(
      name: homeProfile.displayName,
      profileId: homeProfile.id,
      isGenerated: false,
    );
    final away = TournamentPlayer(
      name: awayProfile.displayName,
      profileId: awayProfile.id,
      isGenerated: false,
    );
    final drawnMatch = GroupMatch(
      round: 1,
      homePlayer: home,
      awayPlayer: away,
      homeLegs: 2,
      awayLegs: 2,
    );
    final tournament = CreatedTournament(
      id: 'draw-statistics-tournament',
      name: 'Unentschieden Cup',
      players: [home, away],
      stages: const [
        TournamentStage(
          name: 'Gruppe A',
          type: 'groups',
          groupCount: 1,
          groupSizes: [2],
          gameFormat: TournamentGameFormat(bestOfLegs: 4),
        ),
      ],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppe A',
          groupPlayType: 'round_robin',
          groups: [
            TournamentGroup(
              name: 'A',
              playType: 'round_robin',
              players: [home, away],
              matches: [drawnMatch],
            ),
          ],
          qualificationPlan: null,
          tieBreakers: defaultGroupTieBreakers,
        ),
      ],
    );
    final storage = TournamentStorage(
      file: File('${directory.path}${Platform.pathSeparator}tournaments.json'),
    );
    await storage.saveTournament(tournament);

    final stats = await LocalStatisticsService(
      database: database,
      storage: storage,
    ).forPlayers({homeProfile.id});

    expect(drawnMatch.isResolved, isTrue);
    expect(stats.matches, 1);
    expect(stats.wins, 0);
    expect(stats.draws, 1);
    expect(stats.losses, 0);
    expect(stats.legsWon, 2);
    expect(stats.legsLost, 2);
  });
}
