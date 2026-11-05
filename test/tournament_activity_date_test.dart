import 'package:dart_tournament_manager/features/tournaments/application/tournament_creation_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_activity_logger.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual tournament date and activity log survive JSON round trips', () {
    final date = DateTime(2020, 4, 17);
    final activityTime = DateTime(2026, 8, 3, 14, 25);
    final tournament =
        CreatedTournament(
          name: 'Historisches Turnier',
          players: const [],
          stages: const [],
          runStages: const [],
          tournamentDate: date,
          startedAt: DateTime(2026, 8, 3, 13),
        )..addActivity(
          'tournament_date_changed',
          'Turnierdatum geändert',
          timestamp: activityTime,
        );

    final restored = CreatedTournament.fromJson(tournament.toJson());

    expect(restored.tournamentDate, date);
    expect(restored.effectiveDate, date);
    expect(restored.startedAt!.isAtSameMomentAs(tournament.startedAt!), isTrue);
    expect(restored.activityLog, hasLength(1));
    expect(restored.activityLog.single.type, 'tournament_date_changed');
    expect(restored.activityLog.single.message, 'Turnierdatum geändert');
    expect(
      restored.activityLog.single.timestamp.isAtSameMomentAs(activityTime),
      isTrue,
    );
  });

  test('legacy tournaments keep their technical creation date as fallback', () {
    final restored = CreatedTournament.fromJson({
      'name': 'Alt',
      'createdAt': '2019-02-03T00:00:00.000Z',
      'players': const [],
      'stages': const [],
      'runStages': const [],
    });

    expect(restored.tournamentDate, isNull);
    expect(restored.effectiveDate, restored.createdAt);
  });

  test('new tournament creation accepts the user-selected date', () async {
    final storage = _RecordingTournamentStorage();
    final selectedDate = DateTime(2018, 11, 9);

    final created = await TournamentCreationController(storage: storage)
        .createTournament(
          name: 'Nachgetragen',
          players: const [],
          stages: const [],
          runStages: const [],
          tournamentDate: selectedDate,
        );

    expect(created.tournamentDate, selectedDate);
    expect(storage.savedTournament, same(created));
  });

  test(
    'ranking renames are logged on tournaments assigned to that ranking',
    () async {
      final included = CreatedTournament(
        name: 'Ranglistenturnier',
        players: const [],
        stages: const [],
        runStages: const [],
        rankingIds: const ['ranking-1'],
      );
      final excluded = CreatedTournament(
        name: 'Andere Rangliste',
        players: const [],
        stages: const [],
        runStages: const [],
        rankingIds: const ['ranking-2'],
      );
      final storage = _RecordingTournamentStorage()
        ..tournaments.addAll([included, excluded]);

      await TournamentActivityLogger(storage: storage).recordRankingRename(
        rankingId: 'ranking-1',
        oldName: 'Alt',
        newName: 'Neu',
      );

      expect(included.activityLog, hasLength(1));
      expect(
        included.activityLog.single.message,
        'Ranglistenname geändert: Alt → Neu',
      );
      expect(excluded.activityLog, isEmpty);
      expect(storage.savedTournament, same(included));
    },
  );
}

class _RecordingTournamentStorage extends TournamentStorage {
  CreatedTournament? savedTournament;
  final List<CreatedTournament> tournaments = [];

  @override
  Future<List<CreatedTournament>> loadTournaments() async =>
      List<CreatedTournament>.of(tournaments);

  @override
  Future<void> saveTournament(CreatedTournament tournament) async {
    savedTournament = tournament;
    if (!tournaments.contains(tournament)) tournaments.add(tournament);
  }
}
