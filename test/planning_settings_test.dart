import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/settings/data/planning_settings_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_planning_parameters.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_format_planner.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/planning_duration.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_creation_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

void main() {
  test('new tournament drafts default to four boards', () async {
    final storage = _RecordingTournamentStorage();
    final tournament = TournamentCreationController(storage: storage)
        .createTournament(
          name: 'Vier Boards',
          players: const [],
          stages: const [],
          runStages: const [],
        );
    expect(tournament.boardCount, 4);
    await storage.saveCompleted;
  });

  const request = TournamentPlanningRequest(
    requireGroupPhase: true,
    players: 8,
    boards: 2,
    minimumMatchesPerPlayer: 0,
    minimumMinutes: 0,
    maximumMinutes: 10000,
    x01Selection: '501',
    checkoutType: 'double_out',
  );

  test(
    'saved values survive a new storage instance and repeated saves',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'planning_settings_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/settings.json');
      final storage = PlanningSettingsStorage(file: file);
      final defaults = await storage.load();
      expect(defaults.minutes301DoubleOut, 3);
      expect(defaults.minutes501DoubleOut, 5);
      expect(defaults.minutes301SingleOut, 2);
      expect(defaults.minutes501SingleOut, 4);
      expect(defaults.boardIdleMinutes, 4);
      await storage.save(
        TournamentPlanningParameters.fromValues({
          PlanningParameter.minutes501DoubleOut: 15,
        }),
      );
      expect(
        (await PlanningSettingsStorage(file: file).load()).minutes501DoubleOut,
        15,
      );
      await storage.save(const TournamentPlanningParameters());
      expect((await storage.load()).minutes501DoubleOut, 5);
      await file.writeAsString('{"schemaVersion":99,"parameters":{}}');
      await expectLater(storage.load(), throwsFormatException);
      expect(await file.readAsString(), '{"schemaVersion":99,"parameters":{}}');
    },
  );

  test(
    'schema 3 settings load without rewriting and remain schema 3 on save',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'planning_settings_schema3_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/settings.json');
      const original =
          '{"schemaVersion":3,"parameters":{"minutes501DoubleOut":17,'
          '"maximumSuggestions":7}}';
      await file.writeAsString(original);

      final storage = PlanningSettingsStorage(file: file);
      final parameters = await storage.load();
      expect(parameters.minutes501DoubleOut, 17);
      expect(parameters.maximumSuggestions, 7);
      expect(await file.readAsString(), original);

      await storage.save(parameters);
      final backup = File('${file.path}.bak');
      expect(await backup.readAsString(), original);
      final saved =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(saved['schemaVersion'], 3);
      final roundTripped = TournamentPlanningParameters.fromJson(
        saved['parameters'] as Map<String, dynamic>,
      );
      expect(roundTripped.minutes501DoubleOut, 17);
      expect(roundTripped.maximumSuggestions, 7);
    },
  );

  test('legacy settings schemas 1 and 2 retain parameter values', () async {
    final directory = await Directory.systemTemp.createTemp(
      'planning_settings_legacy_',
    );
    addTearDown(() => directory.delete(recursive: true));
    for (final version in [1, 2]) {
      final file = File('${directory.path}/settings-v$version.json');
      final content =
          '{"schemaVersion":$version,"parameters":{"minutes501DoubleOut":17}}';
      await file.writeAsString(content);

      final parameters = await PlanningSettingsStorage(file: file).load();
      expect(parameters.minutes501DoubleOut, 17);
      expect(await file.readAsString(), content);
    }
  });

  test(
    'invalid values are rejected and missing stored fields use defaults',
    () {
      expect(
        () => TournamentPlanningParameters.fromValues({
          PlanningParameter.maximumGroups: 0,
        }),
        throwsArgumentError,
      );
      final values = TournamentPlanningParameters.fromJson({
        'maximumGroups': -1,
        'minutes501DoubleOut': 12,
      });
      expect(values.maximumGroups, 4);
      expect(values.minutes501DoubleOut, 12);
      expect(values.maximumSuggestions, 3);
    },
  );

  test('leg duration changes actual planning time', () {
    final base = TournamentFormatPlanner(
      parameters: TournamentPlanningParameters.fromValues({
        PlanningParameter.maximumGroups: 1,
        PlanningParameter.boardIdleMinutes: 0,
      }),
    ).suggest(request).single;
    final slower = TournamentFormatPlanner(
      parameters: TournamentPlanningParameters.fromValues({
        PlanningParameter.maximumGroups: 1,
        PlanningParameter.minutes501DoubleOut: 20,
        PlanningParameter.boardIdleMinutes: 0,
      }),
    ).suggest(request).single;
    expect(slower.estimatedMinutes, base.estimatedMinutes * 4);
  });

  test('group block duration includes idle time between board waves', () {
    final estimate = PlanningDuration.calculate(
      groupSizes: const [4],
      qualifiers: 0,
      boards: 2,
      matchMinutes: 10,
      boardIdleMinutes: 4,
    );

    expect(estimate.groupSlots, 3);
    expect(estimate.groupMinutes, 38);
    expect(estimate.totalMinutes, 38);
  });

  test('group, suggestion and qualification parameters reach suggestions', () {
    final suggestions = TournamentFormatPlanner(
      parameters: TournamentPlanningParameters.fromValues({
        PlanningParameter.maximumGroups: 6,
        PlanningParameter.maximumSuggestions: 6,
        PlanningParameter.qualifiersPerGroup: 1,
      }),
    ).suggest(request);
    expect(suggestions.length, 2);
    expect(suggestions.map((s) => s.stages.first.groupCount), contains(2));
    final twoGroups = suggestions.firstWhere(
      (s) => s.stages.first.groupCount == 2,
    );
    expect(twoGroups.qualifiersPerGroup, 1);
    expect(twoGroups.totalMatches, 13);
  });
}

class _RecordingTournamentStorage extends TournamentStorage {
  CreatedTournament? savedTournament;
  final Completer<void> _completed = Completer<void>();

  Future<void> get saveCompleted => _completed.future;

  @override
  Future<void> saveTournament(CreatedTournament tournament) async {
    savedTournament = tournament;
    _completed.complete();
  }
}
