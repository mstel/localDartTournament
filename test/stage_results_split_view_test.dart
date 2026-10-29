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
      expect(tester.getSize(find.byWidget(tile)).height, lessThan(60));
    }
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

  testWidgets('one large group uses two match columns and player filtering', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stage = _oneLargeGroup();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StageResultsSplitView(
              stage: stage,
              standingsFor: (group, _) => [
                for (final player in group.players) PlayerStanding(player),
              ],
              onEditResult: (match) {
                match
                  ..homeLegs = 2
                  ..awayLegs = 0;
              },
              canEditResults: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tiles = find.byType(MatchResultTile);
    expect(tiles, findsNWidgets(15));
    final firstTile = tester.getRect(tiles.at(0));
    final secondTile = tester.getRect(tiles.at(1));
    expect((firstTile.center.dy - secondTile.center.dy).abs(), lessThan(8));
    expect(
      (firstTile.center.dx - secondTile.center.dx).abs(),
      greaterThan(300),
    );
    expect(
      tester
          .getRect(
            find
                .descendant(of: tiles.first, matching: find.byType(IconButton))
                .first,
          )
          .height,
      greaterThanOrEqualTo(48),
    );

    await tester.tap(find.text('Spieler 1').first);
    await tester.pumpAndSettle();
    expect(find.text('Spiele von Spieler 1'), findsOneWidget);
    expect(find.byType(MatchResultTile), findsNWidgets(5));

    await tester.tap(find.byTooltip('Ergebnis').first);
    await tester.pumpAndSettle();
    expect(find.text('Spiele von Spieler 1'), findsNothing);
    expect(find.byType(MatchResultTile), findsNWidgets(14));

    final standingsPlayer = find.text('Spieler 2').last;
    expect(tester.getRect(standingsPlayer).left, greaterThan(1200));
    await tester.tap(standingsPlayer);
    await tester.pumpAndSettle();
    expect(find.text('Spiele von Spieler 2'), findsOneWidget);
    expect(find.byType(MatchResultTile), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('knockout results open a responsive full bracket preview', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final playerA = TournamentPlayer.generated(1).copyWith(name: 'Spieler A');
    final playerB = TournamentPlayer.generated(2).copyWith(name: 'Spieler B');
    final stage = KnockoutTournamentRunStage(
      name: 'KO',
      rounds: [
        [GroupMatch(homePlayer: playerA, awayPlayer: playerB, round: 1)],
        [GroupMatch(round: 2)],
      ],
    );

    for (final size in [
      const Size(360, 800),
      const Size(800, 600),
      const Size(1440, 900),
    ]) {
      for (final textScale in [1.0, 2.0]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: StageResultsSplitView(
                  stage: stage,
                  standingsFor: (_, _) => [],
                  onEditResult: (_) {},
                  canEditResults: true,
                  bracketBuilder: (_, _, _, _, _, _) =>
                      const Text('Vollständiger Turnierbaum'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final previewButton = find.text('Vorschau nächste Etappe');
        await tester.ensureVisible(previewButton);
        await tester.tap(previewButton);
        await tester.pumpAndSettle();

        expect(find.text('Vollständiger Turnierbaum'), findsOneWidget);
        expect(find.byTooltip('Zurück zu Ergebnisse'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$size at $textScale×');
        await tester.tap(find.byTooltip('Zurück zu Ergebnisse'));
        await tester.pumpAndSettle();
        expect(previewButton, findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$size at $textScale×');
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

GroupTournamentRunStage _oneLargeGroup() {
  final players = [
    for (var index = 1; index <= 6; index++)
      TournamentPlayer.generated(index).copyWith(name: 'Spieler $index'),
  ];
  return GroupTournamentRunStage(
    name: 'Gruppenphase',
    groupPlayType: 'round_robin',
    qualificationPlan: null,
    tieBreakers: defaultGroupTieBreakers,
    groups: [
      TournamentGroup(
        name: 'Gruppe A',
        playType: 'round_robin',
        players: players,
        matches: [
          for (var home = 0; home < players.length; home++)
            for (var away = home + 1; away < players.length; away++)
              GroupMatch(
                homePlayer: players[home],
                awayPlayer: players[away],
                round: 1,
              ),
        ],
      ),
    ],
  );
}
