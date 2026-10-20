import 'package:dart_tournament_manager/features/statistics/domain/best_performance.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/tournament_second_screen_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('fixed second-screen layout fits $size with large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: TournamentSecondScreenView(
              tournament: _tournament(),
              isStandaloneWindow: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Zuletzt beendete Matches'), findsOneWidget);
      expect(find.text('170+'), findsOneWidget);
      expect(find.byTooltip('Schließen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('next-stage preview marks only guaranteed qualifiers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tournament = _tournament();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Vorschau für die nächste Etappe'), findsOneWidget);
    await tester.tap(find.text('Vorschau für die nächste Etappe'));
    await tester.pump();

    expect(find.text('KO · Turnierbaum-Vorschau'), findsOneWidget);
    expect(find.textContaining('A · vorläufig weiter'), findsOneWidget);
    expect(find.textContaining('B · vorläufig weiter'), findsNothing);
    expect(find.text('Vorschau schließen'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Vorschau schließen'));
    await tester.pump();
    expect(find.text('Zuletzt beendete Matches'), findsOneWidget);
  });

  testWidgets('shows a separate progress row for each group', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final tournament = _tournament();
    final stage = tournament.runStages.first as GroupTournamentRunStage;
    stage.groups.add(
      TournamentGroup(
        name: 'Gruppe B',
        playType: 'round_robin',
        players: stage.groups.first.players,
        matches: [
          GroupMatch(
            homePlayer: stage.groups.first.players[0],
            awayPlayer: stage.groups.first.players[1],
            round: 1,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('1. Gruppenphase · Gruppe A'), findsOneWidget);
    expect(find.text('1. Gruppenphase · Gruppe B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('priority notices show player names instead of profile IDs', (
    tester,
  ) async {
    final anna = TournamentPlayer(
      profileId: 'profile-anna-91',
      name: 'Anna',
      isGenerated: false,
    );
    final ben = TournamentPlayer(
      profileId: 'profile-ben-37',
      name: 'Ben',
      isGenerated: false,
    );
    final caro = TournamentPlayer(
      profileId: 'profile-caro-52',
      name: 'Caro',
      isGenerated: false,
    );
    final tournament = CreatedTournament(
      name: 'TV-Namen-Test',
      players: [anna, ben, caro],
      stages: const [],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppenphase',
          groupPlayType: 'round_robin',
          groups: [
            TournamentGroup(
              name: 'Gruppe A',
              playType: 'round_robin',
              players: [anna, ben, caro],
              matches: [
                GroupMatch(homePlayer: anna, awayPlayer: ben, round: 1),
                GroupMatch(homePlayer: anna, awayPlayer: caro, round: 2),
              ],
            ),
          ],
          qualificationPlan: null,
          tieBreakers: defaultGroupTieBreakers,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(tournament: tournament),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Priorität: Anna'), findsOneWidget);
    expect(find.textContaining('profile-anna-91'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps preview visible when switching the right-side panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: _tournament(),
            isStandaloneWindow: true,
          ),
        ),
      ),
    );
    await tester.pump();
    final previewButton = find.text('Vorschau für die nächste Etappe');
    await tester.ensureVisible(previewButton);
    await tester.tap(previewButton);
    await tester.pump();
    expect(find.text('KO · Turnierbaum-Vorschau'), findsOneWidget);

    final prognosisTab = find.text('Siegprognose & Weiterkommen');
    await tester.ensureVisible(prognosisTab);
    await tester.tap(prognosisTab);
    await tester.pump();

    expect(find.text('KO-Prognose & Weiterkommen'), findsOneWidget);
    expect(find.text('KO · Turnierbaum-Vorschau'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('can open directly in next-stage preview mode', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: _tournament(),
            isStandaloneWindow: true,
            showNextStagePreviewInitially: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('KO · Turnierbaum-Vorschau'), findsOneWidget);
    expect(find.text('Zur Übersichtsansicht zurückkehren'), findsOneWidget);
  });

  testWidgets('compact preview shows all eight first-round matches at 1080p', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: _largePreviewTournament(),
            isStandaloneWindow: true,
            showNextStagePreviewInitially: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('KO · Turnierbaum-Vorschau'), findsOneWidget);
    expect(find.text('Qualifikant offen').hitTestable(), findsNWidgets(16));
    expect(find.text('Halbfinale'), findsOneWidget);
    expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('standalone close control invokes its close handler', (
    tester,
  ) async {
    var didClose = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: _tournament(),
            isStandaloneWindow: true,
            onClose: () => didClose = true,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Schließen'));
    expect(didClose, isTrue);
  });
}

CreatedTournament _largePreviewTournament() {
  final players = [
    for (var index = 1; index <= 16; index++)
      TournamentPlayer.generated(index).copyWith(name: 'Spieler $index'),
  ];
  return CreatedTournament(
    name: 'Großes Testturnier',
    players: players,
    stages: const [
      TournamentStage(name: 'Gruppenphase', type: 'groups', groupSizes: [16]),
      TournamentStage(
        name: 'KO',
        type: 'single_knockout',
        knockoutParticipantCount: 16,
      ),
    ],
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
            matches: const [],
          ),
        ],
      ),
      KnockoutTournamentRunStage(
        name: 'KO',
        rounds: [
          [
            for (var index = 0; index < players.length; index += 2)
              GroupMatch(
                homePlayer: players[index],
                awayPlayer: players[index + 1],
                round: 1,
              ),
          ],
          [for (var index = 0; index < 4; index++) GroupMatch(round: 2)],
          [for (var index = 0; index < 2; index++) GroupMatch(round: 3)],
          [GroupMatch(round: 4)],
        ],
      ),
    ],
  );
}

CreatedTournament _tournament() {
  final a = TournamentPlayer.generated(1).copyWith(name: 'A');
  final b = TournamentPlayer.generated(2).copyWith(name: 'B');
  final c = TournamentPlayer.generated(3).copyWith(name: 'C');
  final d = TournamentPlayer.generated(4).copyWith(name: 'D');
  final group = TournamentGroup(
    name: 'Gruppe A',
    playType: 'round_robin',
    players: [a, b, c, d],
    matches: [
      GroupMatch(
        homePlayer: a,
        awayPlayer: b,
        round: 1,
        homeLegs: 2,
        awayLegs: 0,
      ),
      GroupMatch(
        homePlayer: a,
        awayPlayer: c,
        round: 2,
        homeLegs: 2,
        awayLegs: 0,
      ),
      GroupMatch(
        homePlayer: a,
        awayPlayer: d,
        round: 3,
        homeLegs: 2,
        awayLegs: 0,
        bestPerformances: const [
          BestPerformance(type: BestPerformanceType.score170, playerName: 'A'),
        ],
      ),
      GroupMatch(homePlayer: b, awayPlayer: c, round: 4),
      GroupMatch(homePlayer: b, awayPlayer: d, round: 5),
      GroupMatch(homePlayer: c, awayPlayer: d, round: 6),
    ],
  );
  return CreatedTournament(
    name: 'Testturnier',
    players: [a, b, c, d],
    stages: const [
      TournamentStage(
        name: 'Gruppenphase',
        type: 'groups',
        groupSizes: [4],
        qualifiedParticipantCount: 2,
      ),
      TournamentStage(
        name: 'KO',
        type: 'single_knockout',
        knockoutParticipantCount: 2,
        knockoutSlotOrder: [1, 2],
      ),
    ],
    runStages: [
      GroupTournamentRunStage(
        name: 'Gruppenphase',
        groupPlayType: 'round_robin',
        groups: [group],
        qualificationPlan: const QualificationPlan(
          totalQualifiers: 2,
          fixedPerGroup: 2,
          extraCount: 0,
          extraRank: 3,
          eligibleGroupSize: null,
          extraGroups: [],
          fixedByGroup: [2],
        ),
        tieBreakers: const ['points', 'legDifference', 'legsFor'],
      ),
      KnockoutTournamentRunStage(
        name: 'KO',
        rounds: [
          [GroupMatch(homePlayer: a, awayPlayer: b, round: 1)],
          [GroupMatch(round: 2)],
        ],
      ),
    ],
  );
}
