import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/pages/tournament_results_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'completed tournament reopens paused with results and can be completed again',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tournament = _completedTournament();
      final storage = _MemoryTournamentStorage();

      await tester.pumpWidget(
        MaterialApp(
          home: TournamentResultsPage(tournament: tournament, storage: storage),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tournament.reopenedForCorrections, isFalse);
      expect(find.byTooltip('Einstellungen'), findsOneWidget);
      expect(find.byTooltip('Hauptmenü'), findsNothing);

      await tester.tap(find.byTooltip('Einstellungen'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Turnier erneut öffnen'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(tournament.finishedAt, isNull);
      expect(tournament.reopenedForCorrections, isTrue);
      expect(
        find.text('Abgeschlossenes Turnier (Normales Turnier)'),
        findsOneWidget,
      );
      expect(find.text('Turnierdetails'), findsNothing);
      expect(tournament.isClockPaused, isTrue);
      expect(tournament.completedStageIndexes, isEmpty);
      final reopenedMatch =
          (tournament.runStages.single as GroupTournamentRunStage)
              .groups
              .single
              .matches
              .single;
      expect(reopenedMatch.homeLegs, 3);
      expect(reopenedMatch.awayLegs, 1);
      final finishButtons = find.widgetWithText(
        FilledButton,
        'Turnier abschließen',
      );
      expect(finishButtons, findsOneWidget);
      expect(tester.widget<FilledButton>(finishButtons).onPressed, isNotNull);
      expect(tester.takeException(), isNull);

      tester.widget<FilledButton>(finishButtons).onPressed!();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(tournament.reopenedForCorrections, isFalse);
      expect(tournament.finishedAt, isNotNull);
      expect(tournament.completedStageIndexes, {0});
      expect(find.text('Turnierergebnisse'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

CreatedTournament _completedTournament() {
  final players = [
    TournamentPlayer.generated(1),
    TournamentPlayer.generated(2),
  ];
  final match = GroupMatch(
    homePlayer: players[0],
    awayPlayer: players[1],
    round: 1,
    homeLegs: 3,
    awayLegs: 1,
    startedAt: DateTime(2026, 10, 22, 17),
    finishedAt: DateTime(2026, 10, 22, 17, 20),
  );
  return CreatedTournament(
    name: 'Abgeschlossenes Turnier',
    players: players,
    stages: const [
      TournamentStage(name: 'Finale', type: 'groups', groupSizes: [2]),
    ],
    runStages: [
      GroupTournamentRunStage(
        name: 'Finale',
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
    startedAt: DateTime(2026, 10, 22, 17),
    finishedAt: DateTime(2026, 10, 22, 17, 20),
    plannedMinutes: 60,
    completedStageIndexes: {0},
  );
}

class _MemoryTournamentStorage extends TournamentStorage {
  Map<String, dynamic>? _saved;

  @override
  Future<void> saveTournament(CreatedTournament tournament) async {
    _saved = tournament.toJson();
  }

  @override
  Future<List<CreatedTournament>> loadTournaments() async {
    final saved = _saved;
    return saved == null
        ? []
        : [CreatedTournament.fromJson(Map<String, dynamic>.from(saved))];
  }
}
