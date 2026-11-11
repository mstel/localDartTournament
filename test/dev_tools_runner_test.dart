import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/dev_tools/domain/development_simulation_runner.dart';
import 'package:dart_tournament_manager/features/dev_tools/domain/tournament_simulation_scenarios.dart';

void main() {
  test(
    'Dev Tools runs all scenarios in an isolate and returns readable reports',
    () async {
      final results = await compute(runDevelopmentSimulations, false);
      expect(results.length, tournamentDevelopmentScenarios.length * 3);
      expect(results.every((result) => result['passed'] == true), isTrue);
      expect(
        results.every(
          (result) =>
              (result['detail'] as String).contains('Finale Teilnehmer:'),
        ),
        isTrue,
      );
    },
  );
}
