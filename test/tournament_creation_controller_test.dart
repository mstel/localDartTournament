import 'package:dart_tournament_manager/features/tournaments/application/tournament_creation_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new tournaments default to four boards without saving externally', () {
    final storage = _RecordingTournamentStorage();
    final tournament = TournamentCreationController(storage: storage)
        .createTournament(
          name: 'Testturnier',
          players: const [],
          stages: const [],
          runStages: const [],
        );

    expect(tournament.boardCount, 4);
    expect(storage.savedTournament, same(tournament));
  });
}

class _RecordingTournamentStorage extends TournamentStorage {
  CreatedTournament? savedTournament;

  @override
  Future<void> saveTournament(CreatedTournament tournament) async {
    savedTournament = tournament;
  }
}
