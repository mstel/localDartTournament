import 'dart:io';

import 'package:dart_tournament_manager/features/tournaments/application/tournament_creation_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'new tournament defaults to four boards and is not ranked implicitly',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tournament_creation_controller_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final storage = TournamentStorage(
        file: File(
          '${directory.path}${Platform.pathSeparator}tournaments.json',
        ),
      );
      final tournament = TournamentCreationController(storage: storage)
          .createTournament(
            name: 'Boards default',
            players: const [],
            stages: const [],
            runStages: const [],
          );
      expect(tournament.boardCount, 4);
      expect(tournament.countsForRanking, isFalse);
      expect((await storage.loadTournaments()).single.boardCount, 4);
    },
  );
}
