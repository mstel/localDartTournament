import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/tournament_timing_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('historical tournament end time is not manually editable', (
    tester,
  ) async {
    final tournament = CreatedTournament(
      name: 'Archivturnier',
      players: const [],
      stages: const [],
      runStages: const [],
      startedAt: DateTime(2026, 1, 1),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentTimingPanel(
            tournament: tournament,
            onStart: () async {},
            onEditTimes: (_, _) async {},
          ),
        ),
      ),
    );

    expect(find.text('Endzeit festlegen'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
