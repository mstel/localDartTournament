import 'package:dart_tournament_manager/features/statistics/domain/best_performance.dart';
import 'package:dart_tournament_manager/features/tournaments/application/group_advancement_forecast_service.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/engines/group_advancement_forecast_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/tournament_second_screen_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tournament clock precedes the mode switch on TV surfaces', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in [const Size(360, 800), const Size(1440, 900)]) {
      for (final isStandalone in [false, true]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TournamentSecondScreenView(
                tournament: _tournament(),
                isStandaloneWindow: isStandalone,
              ),
            ),
          ),
        );
        await tester.pump();

        final clock = tester.getRect(find.textContaining('Turnieruhr:'));
        final modeSwitch = tester.getRect(find.byType(SegmentedButton<bool>));
        expect(clock.bottom, lessThanOrEqualTo(modeSwitch.top));
        expect(tester.takeException(), isNull);
      }
    }
  });

  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
    const Size(1920, 1080),
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

  testWidgets(
    '1920x1080 second screen shows exactly two full recent results and scrolls',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
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
      await tester.pump();

      final viewport = tester.getRect(
        find.byKey(const ValueKey('recent-results-scroll')),
      );
      final resultRects = [
        for (final key in ['recent-result-3-A-D', 'recent-result-2-A-C'])
          tester.getRect(find.byKey(ValueKey(key))),
      ];
      final fullyVisible = resultRects
          .where(
            (rect) =>
                rect.top >= viewport.top && rect.bottom <= viewport.bottom,
          )
          .length;

      expect(fullyVisible, 2);
      expect(find.byKey(const ValueKey('recent-result-1-A-B')), findsNothing);
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const ValueKey('recent-results-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      await tester.drag(
        find.byKey(const ValueKey('recent-results-scroll')),
        const Offset(0, -100),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('recent-result-1-A-B')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'next-stage preview uses current standings for projected qualifiers',
    (tester) async {
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
      expect(find.textContaining('A · gesetzt'), findsOneWidget);
      expect(find.textContaining('B · vorläufig'), findsOneWidget);
      expect(find.text('Vorschau schließen'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Vorschau schließen'));
      await tester.pump();
      expect(find.text('Zuletzt beendete Matches'), findsOneWidget);
    },
  );

  testWidgets(
    'projected bracket uses current qualifiers from two six-player groups',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TournamentSecondScreenView(
              tournament: _twoGroupPreviewTournament(),
              isStandaloneWindow: true,
              showNextStagePreviewInitially: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Jonas · vorläufig'), findsOneWidget);
      expect(find.textContaining('Dietmar · vorläufig'), findsOneWidget);
      expect(find.textContaining('Bernd ·'), findsNothing);
      expect(find.textContaining('Lars · vorläufig'), findsOneWidget);
      expect(find.textContaining('Mika · vorläufig'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('next-stage preview labels fixed qualifiers as set', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tournament = _tournament();
    final group =
        (tournament.runStages.first as GroupTournamentRunStage).groups.first;
    for (var index = 3; index < group.matches.length; index++) {
      group.matches[index]
        ..homeLegs = 2
        ..awayLegs = 0;
    }
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
    await tester.tap(find.text('Vorschau für die nächste Etappe'));
    await tester.pump();

    expect(find.textContaining('A · gesetzt'), findsOneWidget);
    expect(find.textContaining('B · gesetzt'), findsOneWidget);
    expect(find.text('Die Setzplätze der Etappe stehen fest.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forecast tab shows tournament and advancement probabilities', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final forecastService = _FixedForecastService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: _tournament(),
            isStandaloneWindow: true,
            forecastService: forecastService,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Siegprognose & Weiterkommen'));
    await tester.pump();
    await tester.pump();

    expect(find.text('KO-Prognose & Weiterkommen'), findsOneWidget);
    expect(find.textContaining('73.0 % Sieg'), findsAtLeastNWidgets(1));
    expect(find.textContaining('88.0 % weiter'), findsAtLeastNWidgets(1));
    expect(forecastService.calls, 1);
    expect(tester.takeException(), isNull);
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
    final dana = TournamentPlayer(
      profileId: 'profile-dana-64',
      name: 'Dana',
      isGenerated: false,
    );
    final tournament = CreatedTournament(
      name: 'TV-Namen-Test',
      players: [anna, ben, caro, dana],
      stages: const [],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppenphase',
          groupPlayType: 'round_robin',
          groups: [
            TournamentGroup(
              name: 'Gruppe A',
              playType: 'round_robin',
              players: [anna, ben, caro, dana],
              matches: [
                GroupMatch(
                  homePlayer: ben,
                  awayPlayer: caro,
                  round: 1,
                  homeLegs: 3,
                  awayLegs: 1,
                ),
                GroupMatch(
                  homePlayer: ben,
                  awayPlayer: dana,
                  round: 2,
                  homeLegs: 3,
                  awayLegs: 1,
                ),
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

CreatedTournament _twoGroupPreviewTournament() {
  final groupA = [
    for (var index = 1; index <= 6; index++)
      TournamentPlayer.generated(index).copyWith(
        name: ['Jonas', 'Dietmar', 'Bernd', 'A4', 'A5', 'A6'][index - 1],
      ),
  ];
  final groupB = [
    for (var index = 7; index <= 12; index++)
      TournamentPlayer.generated(
        index,
      ).copyWith(name: ['Lars', 'Mika', 'Noah', 'B4', 'B5', 'B6'][index - 7]),
  ];

  List<GroupMatch> groupMatches(
    List<TournamentPlayer> players,
    Set<String> winningPairings,
  ) {
    GroupMatch buildMatch(int home, int away) {
      final homeWins = winningPairings.contains(
        '${players[home].name}:${players[away].name}',
      );
      final awayWins = winningPairings.contains(
        '${players[away].name}:${players[home].name}',
      );
      return GroupMatch(
        homePlayer: players[home],
        awayPlayer: players[away],
        round: 1,
        homeLegs: homeWins
            ? 2
            : awayWins
            ? 0
            : null,
        awayLegs: homeWins
            ? 0
            : awayWins
            ? 2
            : null,
      );
    }

    return [
      for (var home = 0; home < players.length; home++)
        for (var away = home + 1; away < players.length; away++)
          buildMatch(home, away),
    ];
  }

  return CreatedTournament(
    name: 'Zwei Gruppen',
    players: [...groupA, ...groupB],
    stages: const [
      TournamentStage(name: 'Gruppenphase', type: 'groups', groupSizes: [6, 6]),
      TournamentStage(
        name: 'KO',
        type: 'single_knockout',
        knockoutParticipantCount: 4,
        knockoutSeedingMode: 'cross',
      ),
    ],
    runStages: [
      GroupTournamentRunStage(
        name: 'Gruppenphase',
        groupPlayType: 'round_robin',
        groups: [
          TournamentGroup(
            name: 'Gruppe A',
            playType: 'round_robin',
            players: groupA,
            matches: groupMatches(groupA, const {
              'Jonas:Dietmar',
              'Jonas:Bernd',
              'Dietmar:Bernd',
            }),
          ),
          TournamentGroup(
            name: 'Gruppe B',
            playType: 'round_robin',
            players: groupB,
            matches: groupMatches(groupB, const {
              'Lars:Mika',
              'Lars:Noah',
              'Mika:Noah',
            }),
          ),
        ],
        qualificationPlan: const QualificationPlan(
          totalQualifiers: 4,
          fixedPerGroup: 2,
          extraCount: 0,
          extraRank: 0,
          eligibleGroupSize: null,
          extraGroups: [],
          fixedByGroup: [2, 2],
        ),
        tieBreakers: defaultGroupTieBreakers,
      ),
      KnockoutTournamentRunStage(
        name: 'KO',
        rounds: [
          [
            GroupMatch(homePlayer: groupA[2], awayPlayer: groupB[2], round: 1),
            GroupMatch(homePlayer: groupA[1], awayPlayer: groupB[1], round: 1),
          ],
          [GroupMatch(round: 2)],
        ],
      ),
    ],
  );
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

class _FixedForecastService extends GroupAdvancementForecastService {
  _FixedForecastService() : super(simulations: 1);

  int calls = 0;

  @override
  Future<Map<String, AdvancementChance>> calculate({
    required CreatedTournament tournament,
    required GroupTournamentRunStage stage,
  }) async {
    calls++;
    return {
      for (final player in stage.groups.expand((group) => group.players))
        player.profileId ?? player.name: const AdvancementChance(
          groupWinProbability: 73,
          advancementProbability: 88,
        ),
    };
  }
}
