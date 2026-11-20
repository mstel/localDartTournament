import 'package:flutter_test/flutter_test.dart';

import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/brackets/knockout_seeding_mode_label.dart';

void main() {
  test('knockoutSeedingModeLabel uses consistent German labels', () {
    expect(
      knockoutSeedingModeLabel('cross'),
      'Gruppenplatzierung - Feste Kreuzpaarungen',
    );
    expect(
      knockoutSeedingModeLabel('random_cross'),
      'Gruppenplatzierung - Zufällige Kreuzpaarungen',
    );
    expect(
      knockoutSeedingModeLabel('elo'),
      'Leistungsbasierte Setzliste (ELO)',
    );
    expect(knockoutSeedingModeLabel('manual'), 'Manuelle Paarungszuordnung');
    expect(
      knockoutSeedingModeLabel('random'),
      'Zufallsauslosung beim Turnierstart',
    );
    expect(
      knockoutSeedingModeLabel('unbekannt'),
      'Gruppenplatzierung - Feste Kreuzpaarungen',
    );
  });

  test('label is taken from the matching planning stage', () {
    const runStage = KnockoutTournamentRunStage(name: 'KO', rounds: []);
    final tournament = CreatedTournament(
      name: 'Turnier',
      players: const [],
      stages: const [
        TournamentStage(
          name: 'KO',
          type: 'knockout',
          knockoutSeedingMode: 'elo',
        ),
      ],
      runStages: const [runStage],
    );

    expect(
      knockoutSeedingModeLabelForStage(tournament, runStage),
      'Leistungsbasierte Setzliste (ELO)',
    );
    expect(knockoutSeedingModeLabelForStage(null, runStage), isNull);
  });
}
