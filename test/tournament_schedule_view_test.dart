import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/tournament_schedule_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('explains remaining lives in multi-loss knockout matches', (
    tester,
  ) async {
    final first = TournamentPlayer.generated(1);
    final second = TournamentPlayer.generated(2);
    final match = GroupMatch(
      homePlayer: first,
      awayPlayer: second,
      round: 1,
      homeLegs: 1,
      awayLegs: 3,
    );
    final tournament = CreatedTournament(
      name: 'Doppel-K.-o.',
      players: [first, second],
      stages: const [
        TournamentStage(name: 'Doppel-K.-o.', type: 'double_knockout'),
      ],
      runStages: [
        KnockoutTournamentRunStage(
          name: 'Doppel-K.-o.',
          rounds: [
            [match],
          ],
          eliminationLossLimit: 2,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: TournamentScheduleView(tournament: tournament)),
    );

    expect(find.textContaining('${first.name}: noch 1 Leben'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows all group and knockout matches in a responsive table', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final first = TournamentPlayer.generated(1);
    final second = TournamentPlayer.generated(2);
    final groupMatch = GroupMatch(
      homePlayer: first,
      awayPlayer: second,
      round: 1,
      homeLegs: 3,
      awayLegs: 1,
    );
    final knockoutMatch = GroupMatch(
      homePlayer: first,
      awayPlayer: second,
      round: 1,
      boardNumber: 2,
      homeLegs: 3,
      awayLegs: 1,
    );
    final tournament = CreatedTournament(
      name: 'Vereinsturnier',
      players: [first, second],
      stages: const [
        TournamentStage(name: 'Gruppenphase', type: 'groups'),
        TournamentStage(
          name: 'Finalrunde',
          type: 'single_knockout',
          knockoutSeedingMode: 'cross',
        ),
      ],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppenphase',
          groupPlayType: 'round_robin',
          groups: [
            TournamentGroup(
              name: 'A',
              playType: 'round_robin',
              players: [first, second],
              matches: [groupMatch],
            ),
          ],
          qualificationPlan: null,
          tieBreakers: const [],
        ),
        KnockoutTournamentRunStage(
          name: 'Finalrunde',
          rounds: [
            [knockoutMatch],
          ],
        ),
      ],
    );
    GroupMatch? editedMatch;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: TournamentScheduleView(
          tournament: tournament,
          onEditResult: (match) => editedMatch = match,
        ),
      ),
    );

    expect(find.text('1. Gruppenphase'), findsOneWidget);
    expect(find.text('2. Finalrunde'), findsOneWidget);
    expect(find.text('Gruppe A · Runde 1'), findsOneWidget);
    expect(find.text('3:1'), findsNWidgets(2));
    expect(
      find.text('Setzung: Cross-Setzung nach Gruppenplatzierungen.'),
      findsOneWidget,
    );
    expect(find.textContaining('ausgeschieden'), findsOneWidget);
    expect(find.text('Board'), findsWidgets);
    expect(find.byType(DataTable), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('K.-o.-Baum im Vollbild öffnen'));
    await tester.pumpAndSettle();
    expect(find.text('Finale'), findsWidgets);
    expect(find.text('Spieler 1'), findsWidgets);
    final bracketDialog = find.byType(Dialog).last;
    await tester.tap(
      find.descendant(
        of: bracketDialog,
        matching: find.byTooltip('Ergebnis bearbeiten'),
      ),
    );
    expect(editedMatch, same(knockoutMatch));
    expect(tester.takeException(), isNull);
  });
}
