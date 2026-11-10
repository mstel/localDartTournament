import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_run_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show TournamentRunPage;

class _MemoryTournamentStorage extends TournamentStorage {
  @override
  Future<void> saveTournament(CreatedTournament tournament) async {}
}

CreatedTournament _tournament({required bool hasResult}) {
  final players = [
    TournamentPlayer.generated(1),
    TournamentPlayer.generated(2),
  ];
  final match = GroupMatch(
    homePlayer: players[0],
    awayPlayer: players[1],
    round: 1,
    homeLegs: hasResult ? 3 : null,
    awayLegs: hasResult ? 1 : null,
  );
  return CreatedTournament(
    name: 'Konfigurationstest',
    players: players,
    stages: const [TournamentStage(name: 'Gruppenphase', type: 'groups')],
    runStages: [
      GroupTournamentRunStage(
        name: 'Gruppenphase',
        groupPlayType: 'round_robin',
        qualificationPlan: null,
        tieBreakers: defaultGroupTieBreakers,
        groups: [
          TournamentGroup(
            name: 'Gruppe A',
            playType: 'round_robin',
            players: players,
            matches: [match],
          ),
        ],
      ),
    ],
  );
}

void main() {
  for (final hasResult in [false, true]) {
    testWidgets(
      'configuration editing is ${hasResult ? 'disabled' : 'enabled'} when result=$hasResult',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final storage = _MemoryTournamentStorage();
        await tester.pumpWidget(
          MaterialApp(
            home: TournamentRunPage(
              tournament: _tournament(hasResult: hasResult),
              tournamentStorage: storage,
              runController: TournamentRunController(storage: storage),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Einstellungen'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Turnierkonfiguration bearbeiten'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        final editButton = tester.widget<OutlinedButton>(
          find.ancestor(
            of: find.text('Turnierkonfiguration bearbeiten'),
            matching: find.byType(OutlinedButton),
          ),
        );
        expect(editButton.onPressed == null, hasResult);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
