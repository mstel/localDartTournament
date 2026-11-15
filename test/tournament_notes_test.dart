import 'dart:convert';
import 'dart:io';

import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy tournament data defaults to no notes', () {
    final legacyData = CreatedTournament(
      id: 'legacy-notes',
      name: 'Älteres Turnier',
      players: const [],
      stages: const [],
      runStages: const [],
    ).toJson();

    expect(legacyData, isNot(contains('tournamentNotes')));
    expect(CreatedTournament.fromJson(legacyData).tournamentNotes, isEmpty);
  });

  test('tournament notes survive a storage round trip', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tournament_notes_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final storage = TournamentStorage(
      file: File('${directory.path}${Platform.pathSeparator}tournaments.json'),
    );
    final tournament = CreatedTournament(
      id: 'notes-round-trip',
      name: 'Notiztest',
      tournamentNotes: 'Board 3 war regelmäßig unterausgelastet.',
      players: [TournamentPlayer.generated(1), TournamentPlayer.generated(2)],
      stages: const [],
      runStages: const [],
    );

    await storage.saveTournament(tournament);

    final loaded = (await storage.loadTournaments()).single;
    final document =
        jsonDecode(
              await File(
                '${directory.path}${Platform.pathSeparator}tournaments.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(loaded.tournamentNotes, tournament.tournamentNotes);
    expect(document['schemaVersion'], TournamentStorage.schemaVersion);
  });
}
