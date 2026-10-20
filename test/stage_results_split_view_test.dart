import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/result_entry.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/stage_results_split_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('group results use two compact, round-free columns on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final tournament = _groupStage();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StageResultsSplitView(
              stage: tournament,
              standingsFor: (_, _) => [],
              onEditResult: (_) {},
              canEditResults: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final groupA = tester.getRect(find.text('Gruppe A').first);
    final groupB = tester.getRect(find.text('Gruppe B').first);
    expect(groupA.center.dx, lessThan(groupB.center.dx));
    expect((groupA.center.dy - groupB.center.dy).abs(), lessThan(40));
    expect(find.textContaining('Gruppe A · R'), findsNothing);
    expect(find.text('Runde 1'), findsNothing);
    expect(find.byType(MatchResultTile), findsNWidgets(2));
    for (final tile in tester.widgetList<MatchResultTile>(
      find.byType(MatchResultTile),
    )) {
      expect(tile.compact, isTrue);
      expect(tile.showRoundLabel, isFalse);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('group results remain readable at mobile width', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StageResultsSplitView(
              stage: _groupStage(),
              standingsFor: (_, _) => [],
              onEditResult: (_) {},
              canEditResults: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gruppe A'), findsAtLeastNWidgets(1));
    expect(find.text('Gruppe B'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('group results stay responsive with larger text', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final size in [
      const Size(360, 800),
      const Size(800, 600),
      const Size(1440, 900),
      const Size(1920, 1080),
    ]) {
      for (final scale in [1.0, 2.0]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: StageResultsSplitView(
                  stage: _groupStage(),
                  standingsFor: (_, _) => [],
                  onEditResult: (_) {},
                  canEditResults: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$size at $scale×');
      }
    }
  });
}

GroupTournamentRunStage _groupStage() {
  final players = [
    TournamentPlayer.generated(1).copyWith(name: 'Spieler A'),
    TournamentPlayer.generated(2).copyWith(name: 'Spieler B'),
    TournamentPlayer.generated(3).copyWith(name: 'Spieler C'),
    TournamentPlayer.generated(4).copyWith(name: 'Spieler D'),
  ];
  return GroupTournamentRunStage(
    name: 'Gruppenphase',
    groupPlayType: 'round_robin',
    qualificationPlan: null,
    tieBreakers: defaultGroupTieBreakers,
    groups: [
      for (var index = 0; index < 2; index++)
        TournamentGroup(
          name: 'Gruppe ${index == 0 ? 'A' : 'B'}',
          playType: 'round_robin',
          players: players.sublist(index * 2, index * 2 + 2),
          matches: [
            GroupMatch(
              homePlayer: players[index * 2],
              awayPlayer: players[index * 2 + 1],
              round: 1,
            ),
          ],
        ),
    ],
  );
}
