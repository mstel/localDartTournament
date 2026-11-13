import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

void main() {
  test('reopening waits for the preceding result save', () async {
    final directory = await Directory.systemTemp.createTemp(
      'result_persistence',
    );
    addTearDown(() => directory.delete(recursive: true));
    final storage = TournamentStorage(
      file: File('${directory.path}/tournaments.json'),
    );
    final match = GroupMatch(
      round: 1,
      homePlayer: TournamentPlayer.generated(1),
      awayPlayer: TournamentPlayer.generated(2),
    );
    final tournament = CreatedTournament(
      name: 'Test',
      players: [],
      stages: [],
      runStages: [
        KnockoutTournamentRunStage(
          name: 'KO',
          rounds: [
            [match],
          ],
        ),
      ],
    );
    await storage.saveTournament(tournament);
    match.homeLegs = 2;
    match.awayLegs = 1;
    final save = storage.saveTournament(tournament);
    final reopened = await storage.loadTournaments();
    await save;
    expect(
      (reopened.single.runStages.single as KnockoutTournamentRunStage)
          .matches
          .single
          .homeLegs,
      2,
    );
  });

  test('loaded KO group list and bracket reference the same match', () {
    final match = GroupMatch(
      round: 1,
      homePlayer: TournamentPlayer.generated(1),
      awayPlayer: TournamentPlayer.generated(2),
    );
    final group = TournamentGroup(
      name: 'A',
      playType: 'mini_knockout',
      players: [],
      matches: [match],
      knockoutRounds: [
        [match],
      ],
    );
    final loaded = TournamentGroup.fromJson(group.toJson());
    loaded.matches.single.homeLegs = 2;
    loaded.matches.single.awayLegs = 1;
    expect(loaded.knockoutRounds.single.single.homeLegs, 2);
    final reloaded = TournamentGroup.fromJson(loaded.toJson());
    expect(reloaded.knockoutRounds.single.single.homeLegs, 2);
  });

  test(
    'active tournaments stay in SQLite until close, then enter year archive and master',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tournament_archive_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/tournaments.json');
      final storage = TournamentStorage(file: file);
      final tournament = CreatedTournament(
        id: 'season-2026-event-1',
        name: 'Saison 2026',
        players: [],
        stages: [],
        runStages: [],
        tournamentDate: DateTime(2026, 7, 12),
        countsForRanking: true,
        rankingIds: const ['ranking-2026'],
      );

      await storage.saveTournament(tournament);
      expect(
        (await LocalAppDatabase(
          baseDirectory: directory,
        ).loadActiveTournamentCopies()).single.id,
        tournament.id,
      );
      expect(
        (jsonDecode(await file.readAsString()) as Map)['tournaments'],
        isEmpty,
      );

      tournament.finishedAt = DateTime(2026, 7, 12, 22);
      await storage.saveTournament(tournament);

      final archived = await storage.loadTournamentsForRanking('ranking-2026');
      expect(archived.map((item) => item.id), [tournament.id]);
      expect(
        (await LocalAppDatabase(
          baseDirectory: directory,
        ).loadActiveTournamentCopies()),
        isEmpty,
      );
      final master = jsonDecode(await file.readAsString()) as Map;
      expect((master['tournaments'] as List).single['id'], tournament.id);
      expect(master['archiveGeneration'], isNotNull);
      final archiveDirectory = Directory('${directory.path}/ranking_archives');
      expect(
        archiveDirectory.listSync().whereType<File>().any(
          (entry) => entry.path.contains('ranking-archive-'),
        ),
        isTrue,
      );

      await storage.deleteTournament(tournament.id);
      expect(await storage.loadTournamentsForRanking('ranking-2026'), isEmpty);
      expect((await storage.loadTournaments()), isEmpty);
      expect(
        (jsonDecode(await file.readAsString()) as Map)['tournaments'],
        isEmpty,
      );
    },
  );
}
