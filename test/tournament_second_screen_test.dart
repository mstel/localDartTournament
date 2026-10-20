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
    const Size(1920, 1080),
    const Size(3840, 2160),
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
      expect(find.text('1x geworfen · A'), findsOneWidget);
      expect(find.byTooltip('Schließen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('compact TV view can switch between standings and forecast', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
    final selector = find.byType(SegmentedButton<bool>);
    expect(selector, findsOneWidget);
    expect(tester.widget<SegmentedButton<bool>>(selector).selected, {false});
    await tester.ensureVisible(find.text('Prognose'));
    await tester.tap(find.text('Prognose'));
    await tester.pump();
    expect(tester.widget<SegmentedButton<bool>>(selector).selected, {true});
    expect(tester.takeException(), isNull);
  });

  testWidgets('next-stage preview shows current qualifiers provisionally', (
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
    expect(
      find.textContaining('A\nAktuell weiter · Setzplatz vorläufig'),
      findsOneWidget,
    );
    expect(
      find.textContaining('B\nAktuell weiter · Setzplatz vorläufig'),
      findsOneWidget,
    );
    expect(find.text('Zur Übersichtsansicht zurückkehren'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Zur Übersichtsansicht zurückkehren'));
    await tester.pump();
    expect(find.text('Zuletzt beendete Matches'), findsOneWidget);
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
