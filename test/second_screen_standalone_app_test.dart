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
  )..updatedAt = DateTime.utc(2026, 1, 1);

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

  test(
    'standalone refreshes only when tournament identity or revision changes',
    () {
      final unchanged = CreatedTournament.fromJson(active.toJson());
      final revised = CreatedTournament.fromJson(active.toJson())
        ..updatedAt = active.updatedAt.add(const Duration(seconds: 1));

      expect(secondScreenTournamentChanged(active, unchanged), isFalse);
      expect(secondScreenTournamentChanged(active, revised), isTrue);
      expect(secondScreenTournamentChanged(active, finished), isTrue);
      expect(secondScreenTournamentChanged(active, null), isTrue);
    },
  );
}
