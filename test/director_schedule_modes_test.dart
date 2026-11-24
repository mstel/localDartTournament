import 'package:flutter_test/flutter_test.dart';

import 'package:dart_tournament_manager/features/settings/data/director_mode_defaults.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/director_schedule_modes.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

CreatedTournament _tournament() => CreatedTournament(
  name: 'Modi-Test',
  players: const [],
  stages: const [],
  runStages: const [],
);

void main() {
  group('DirectorScheduleModes', () {
    test('legacy dynamic + group maps to plain dynamic', () {
      final json = _tournament().toJson()
        ..['directorPlayOrderMode'] = 'dynamic'
        ..['directorSchedulingStrategy'] = 'group';

      final tournament = CreatedTournament.fromJson(json);

      expect(tournament.directorPlayOrderMode, 'dynamic');
      expect(tournament.directorSchedulingStrategy, 'global');
    });

    test('missing flags map to dynamic + global', () {
      final json = _tournament().toJson()
        ..remove('directorPlayOrderMode')
        ..remove('directorSchedulingStrategy');

      final tournament = CreatedTournament.fromJson(json);

      expect(tournament.directorPlayOrderMode, 'dynamic');
      expect(tournament.directorSchedulingStrategy, 'global');
    });

    test('legacy fixed_order remains a fixed schedule', () {
      final json = _tournament().toJson()
        ..['directorPlayOrderMode'] = 'fixed_order'
        ..['directorSchedulingStrategy'] = 'group';

      final tournament = CreatedTournament.fromJson(json);

      expect(tournament.directorPlayOrderMode, 'fixed_schedule');
      expect(tournament.directorSchedulingStrategy, 'group');
    });

    test('settings defaults cannot persist dynamic + group', () {
      final defaults = DirectorModeDefaults.fromJson({
        'tournaments': {'scheduleMode': 'dynamic', 'boardAssignment': 'group'},
      });

      expect(defaults.tournamentScheduleMode, 'dynamic');
      expect(defaults.tournamentBoardAssignment, 'global');

      final applied = defaults.applyToTournament(_tournament());
      expect(applied.directorPlayOrderMode, 'dynamic');
      expect(applied.directorSchedulingStrategy, 'global');
    });

    test('manual schedule marker survives a JSON round trip', () {
      final tournament = _tournament()
        ..directorPlayOrderMode = 'fixed_schedule'
        ..directorSchedulingStrategy = 'group'
        ..fixedScheduleManuallyAdjusted = true;

      final restored = CreatedTournament.fromJson(tournament.toJson());

      expect(restored.fixedScheduleManuallyAdjusted, isTrue);
    });

    test('normalizeJson exposes the canonical pair', () {
      final normalized = DirectorScheduleModes.normalizeJson({
        'directorPlayOrderMode': 'dynamic',
        'directorSchedulingStrategy': 'group',
      });

      expect(normalized['directorPlayOrderMode'], 'dynamic');
      expect(normalized['directorSchedulingStrategy'], 'global');
    });
  });
}
