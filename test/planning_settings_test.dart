import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/settings/data/planning_settings_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_planning_parameters.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_format_planner.dart';

void main() {
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
      expect((await storage.load()).minutes501DoubleOut, 5);
      expect((await storage.load()).boardIdleMinutes, 4);
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
    },
  );

  test(
    'version 2 settings migrate old leg defaults and add board idle time',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'planning_settings_migration_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/settings.json');
      await file.writeAsString('''
      {"schemaVersion":2,"parameters":{
        "minutes301DoubleOut":8,
        "minutes501DoubleOut":10,
        "minutes301SingleOut":5,
        "minutes501SingleOut":7
      }}
    ''');
      final values = await PlanningSettingsStorage(file: file).load();
      expect(values.minutes301DoubleOut, 3);
      expect(values.minutes501DoubleOut, 5);
      expect(values.minutes301SingleOut, 2);
      expect(values.minutes501SingleOut, 4);
      expect(values.boardIdleMinutes, 4);
    },
  );

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
      expect(values.boardIdleMinutes, 4);
    },
  );

  test('leg duration changes actual planning time', () {
    final base = TournamentFormatPlanner(
      parameters: TournamentPlanningParameters.fromValues({
        PlanningParameter.maximumGroups: 1,
      }),
    ).suggest(request).single;
    final slower = TournamentFormatPlanner(
      parameters: TournamentPlanningParameters.fromValues({
        PlanningParameter.maximumGroups: 1,
        PlanningParameter.minutes501DoubleOut: 20,
      }),
    ).suggest(request).single;
    expect(slower.estimatedMinutes, greaterThan(base.estimatedMinutes));
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
