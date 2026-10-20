import 'package:dart_tournament_manager/app/second_screen_standalone_app.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final finished = CreatedTournament(
    id: 'finished',
    name: 'Finished',
    players: const [],
    stages: const [],
    runStages: const [],
    finishedAt: DateTime(2026),
  );
  final active = CreatedTournament(
    id: 'active',
    name: 'Active',
    players: const [],
    stages: const [],
    runStages: const [],
  );

  test('uses the requested tournament instead of the latest active one', () {
    expect(
      resolveSecondScreenTournament([
        finished,
        active,
      ], tournamentId: 'finished'),
      same(finished),
    );
  });

  test(
    'does not substitute another tournament when the requested id is stale',
    () {
      expect(
        resolveSecondScreenTournament([
          finished,
          active,
        ], tournamentId: 'missing'),
        isNull,
      );
    },
  );

  test('uses the most recent active tournament when no id is supplied', () {
    expect(resolveSecondScreenTournament([finished, active]), same(active));
  });
}
