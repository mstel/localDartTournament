import 'dart:ui' show PointerDeviceKind;

import 'package:dart_tournament_manager/features/statistics/domain/best_performance.dart';
import 'package:dart_tournament_manager/features/tournaments/application/group_advancement_forecast_service.dart';
import 'package:dart_tournament_manager/features/tournaments/application/order_of_play/order_of_play_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/engines/group_advancement_forecast_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/second_screen_widget_placement.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/statistics/domain/player_monthly_performance.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/tournament_second_screen_view.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/recommended_matches_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('recommended table splits two groups into four match columns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetDevicePixelRatio);

    final players = [
      for (var index = 1; index <= 8; index++)
        TournamentPlayer.generated(index).copyWith(name: 'Spieler $index'),
    ];
    final groups = [
      for (var groupIndex = 0; groupIndex < 2; groupIndex++)
        RecommendedMatchGroup(
          name: 'Gruppe ${groupIndex == 0 ? 'A' : 'B'}',
          matches: [
            for (var index = 0; index < 6; index++)
              GroupMatch(
                homePlayer: players[groupIndex * 4 + index % 4],
                awayPlayer: players[groupIndex * 4 + (index + 1) % 4],
                round: index + 1,
              ),
          ],
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 1100,
              child: RecommendedMatchesTable(
                groups: groups,
                prioritizedMatches: const {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final groupAColumns = [
      tester.getRect(find.byKey(const ValueKey('recommended-group-Gruppe A'))),
      tester.getRect(
        find.byKey(const ValueKey('recommended-group-Gruppe A-1')),
      ),
    ];
    final groupBColumns = [
      tester.getRect(find.byKey(const ValueKey('recommended-group-Gruppe B'))),
      tester.getRect(
        find.byKey(const ValueKey('recommended-group-Gruppe B-1')),
      ),
    ];
    expect(groupAColumns[0].center.dy, closeTo(groupAColumns[1].center.dy, 4));
    expect(groupBColumns[0].center.dy, closeTo(groupBColumns[1].center.dy, 4));
    expect(groupAColumns[0].center.dx, lessThan(groupAColumns[1].center.dx));
    expect(groupBColumns[0].center.dx, lessThan(groupBColumns[1].center.dx));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'recommended-match-',
            ),
      ),
      findsNWidgets(12),
    );
  });

  testWidgets('Kratzer matches render in the monitor schedule', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final players = [
      for (var index = 1; index <= 3; index++)
        TournamentPlayer.generated(index).copyWith(name: 'Spieler $index'),
    ];
    final tournament = CreatedTournament(
      name: 'Kratzer',
      players: players,
      stages: const [TournamentStage(name: 'Kratzer', type: 'kratzer')],
      runStages: [
        KnockoutTournamentRunStage(
          name: 'Kratzer',
          rounds: [
            [
              GroupMatch(
                isKratzer: true,
                players: players,
                scratchEligiblePlayers: players,
                round: 1,
              ),
            ],
          ],
          isKratzer: true,
          eliminationLossLimit: 2,
          participants: players,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nächste Partien · Vorschläge'), findsOneWidget);
    expect(
      find.text(players.map((player) => player.shortDisplayName).join(' · ')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('director mode shows board status and upcoming matches on TV', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tournament = _tournament()
      ..directorModeEnabled = true
      ..boardCount = 4;
    final forecastService = _FixedForecastService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            forecastService: forecastService,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(forecastService.calls, lessThanOrEqualTo(1));
    expect(find.text('Boards & nächste Begegnungen'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('second-screen-director-board-1')),
      findsOneWidget,
    );
    final boardOne = tester.getTopLeft(
      find.byKey(const ValueKey('second-screen-director-board-1')),
    );
    final boardTwo = tester.getTopLeft(
      find.byKey(const ValueKey('second-screen-director-board-2')),
    );
    final boardThree = tester.getTopLeft(
      find.byKey(const ValueKey('second-screen-director-board-3')),
    );
    expect(boardTwo.dy, closeTo(boardOne.dy, 1));
    expect(boardTwo.dx, greaterThan(boardOne.dx));
    expect(boardThree.dy, greaterThan(boardOne.dy));
    expect(find.text('Spielplan'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('running matches are clearly separated from suggestions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tournament = _tournament()
      ..directorModeEnabled = true
      ..boardCount = 2;
    final match = const OrderOfPlayController()
        .plan(tournament, 0)
        .planned
        .first
        .entry
        .match;
    expect(
      const OrderOfPlayController().start(tournament, 0, match, 1),
      isTrue,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage([tournament]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aktuelle Partien (1)'), findsOneWidget);
    expect(find.textContaining('JETZT LIVE · BOARD 1'), findsOneWidget);
    expect(
      find.byKey(
        ValueKey(
          'second-screen-running-match-${match.round}-'
          '${match.homePlayer?.profileId ?? match.homePlayer?.name}-'
          '${match.awayPlayer?.profileId ?? match.awayPlayer?.name}',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Boards & nächste Begegnungen'), findsOneWidget);
    expect(
      find.textContaining('Empfohlene Partien für Board 1'),
      findsOneWidget,
    );
    expect(find.text('Aktuell: ${match.participantShortLabel}'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('four active matches fit on one row on a desktop monitor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final players = [
      for (var index = 1; index <= 8; index++)
        TournamentPlayer.generated(index).copyWith(name: 'Spieler $index'),
    ];
    final matches = [
      for (var index = 0; index < 4; index++)
        GroupMatch(
          homePlayer: players[index * 2],
          awayPlayer: players[index * 2 + 1],
          round: 1,
        ),
    ];
    final tournament = CreatedTournament(
      name: 'Vier Boards',
      players: players,
      stages: const [],
      boardCount: 4,
      directorModeEnabled: true,
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppenphase',
          groupPlayType: 'round_robin',
          groups: [
            TournamentGroup(
              name: 'Gruppe A',
              playType: 'round_robin',
              players: players,
              matches: matches,
            ),
          ],
          qualificationPlan: null,
          tieBreakers: const [],
        ),
      ],
    );
    for (var index = 0; index < matches.length; index++) {
      expect(
        const OrderOfPlayController().start(
          tournament,
          0,
          matches[index],
          index + 1,
        ),
        isTrue,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage([tournament]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tiles = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'second-screen-running-match-',
          ),
    );
    expect(tiles, findsNWidgets(4));
    final tileTops = [
      for (final tile in tester.widgetList(tiles))
        tester.getTopLeft(find.byWidget(tile)).dy,
    ];
    expect(
      tileTops.reduce((left, right) => left > right ? left : right) -
          tileTops.reduce((left, right) => left < right ? left : right),
      lessThan(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('player insights only appear on the enabled standalone monitor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tournament = _tournamentWithPlayerInsights()
      ..directorModeEnabled = true
      ..showPlayerInsights = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage([tournament]),
            database: _PlayerInsightTestDatabase(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hot Streak'), findsWidgets);
    expect(
      find.byTooltip('Marvin hat seine letzten 3 Matches in Folge gewonnen.'),
      findsWidgets,
    );

    tournament.showPlayerInsights = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage([tournament]),
            database: _PlayerInsightTestDatabase(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hot Streak'), findsNothing);

    tournament.showPlayerInsights = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            storage: _MemoryTournamentStorage([tournament]),
            database: _PlayerInsightTestDatabase(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hot Streak'), findsNothing);
    expect(tester.takeException(), isNull);
  });

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
        final modeSwitch = tester.getRect(
          find.byWidgetPredicate(
            (widget) => widget is SegmentedButton || widget is DropdownButton,
          ),
        );
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
      expect(find.text('171+'), findsOneWidget);
      expect(find.byTooltip('Schließen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('second screen fits four groups and all matches in its table', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final players = [
      for (var index = 1; index <= 8; index++)
        TournamentPlayer.generated(index).copyWith(
          name: 'Spielername mit außergewöhnlicher Länge Nummer $index',
        ),
    ];
    final matches = [
      for (var index = 0; index < 10; index++)
        GroupMatch(
          homePlayer: players[index % players.length],
          awayPlayer: players[(index + 1) % players.length],
          round: index + 1,
        ),
    ];
    final tournament = CreatedTournament(
      name: 'Langnamen',
      players: players,
      stages: const [
        TournamentStage(name: 'Gruppenphase', type: 'groups', groupSizes: [8]),
      ],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppenphase',
          groupPlayType: 'round_robin',
          groups: [
            TournamentGroup(
              name: 'Gruppe A',
              playType: 'round_robin',
              players: players,
              matches: matches,
            ),
          ],
          qualificationPlan: null,
          tieBreakers: defaultGroupTieBreakers,
        ),
      ],
    );
    final stage = tournament.runStages.single as GroupTournamentRunStage;
    for (var index = 0; index < 3; index++) {
      stage.groups.add(
        TournamentGroup(
          name: 'Gruppe ${String.fromCharCode(66 + index)}',
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
      );
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

    expect(find.text('Nächste Partien · Vorschläge'), findsOneWidget);
    expect(find.byType(RecommendedMatchesTable), findsOneWidget);
    final groupRects = [
      for (final name in ['Gruppe A', 'Gruppe B', 'Gruppe C', 'Gruppe D'])
        tester.getRect(find.byKey(ValueKey('recommended-group-$name'))),
    ];
    expect(
      groupRects.every((rect) => (rect.top - groupRects.first.top).abs() < 4),
      isTrue,
    );
    final visibleMatches = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'recommended-match-',
          ),
    );
    expect(visibleMatches, findsNWidgets(13));
    for (var index = 0; index < 10; index++) {
      final playerTexts = tester
          .widgetList<Text>(
            find.descendant(
              of: visibleMatches.at(index),
              matching: find.byType(Text),
            ),
          )
          .where(
            (text) =>
                text.data?.startsWith(
                  'Spielername mit außergewöhnlicher Länge',
                ) ??
                false,
          )
          .toList();
      expect(playerTexts, hasLength(2));
      for (final text in playerTexts) {
        expect(text.maxLines, 1);
      }
    }
    expect(find.text('Vollständiger Spielplan'), findsNothing);
    await tester.pump(const Duration(seconds: 10));
    expect(visibleMatches, findsNWidgets(13));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'second screen scrolls through recent results in a two-match viewport',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tournament = _tournament();
      final group =
          (tournament.runStages.first as GroupTournamentRunStage).groups.first;
      group.matches.addAll([
        GroupMatch(
          homePlayer: group.players[1],
          awayPlayer: group.players[3],
          round: 7,
          homeLegs: 2,
          awayLegs: 0,
        ),
        GroupMatch(
          homePlayer: group.players[2],
          awayPlayer: group.players[3],
          round: 8,
          homeLegs: 2,
          awayLegs: 0,
        ),
      ]);
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

      final viewport = tester.getRect(
        find.byKey(const ValueKey('recent-results-scroll')),
      );
      final resultRects = [
        for (final key in ['recent-result-8-C-D', 'recent-result-7-B-D'])
          tester.getRect(find.byKey(ValueKey(key))),
      ];
      expect(resultRects.first.top, lessThan(resultRects.last.top));
      expect(resultRects.every((rect) => rect.height <= 66), isTrue);
      expect(
        resultRects.every(
          (rect) =>
              rect.top >= viewport.top && rect.bottom <= viewport.bottom + 1,
        ),
        isTrue,
        reason: 'Viewport $viewport; rows $resultRects',
      );
      expect(
        find.byKey(const ValueKey('recent-result-3-A-D')).hitTestable(),
        findsNothing,
      );
      await tester.drag(
        find.descendant(
          of: find.byKey(const ValueKey('recent-results-scroll')),
          matching: find.byType(ListView),
        ),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recent-result-3-A-D')), findsOneWidget);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('recent-result-3-A-D')))
            .overlaps(viewport),
        isTrue,
      );
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

  testWidgets(
    'active KO overview shows actual players in a full-width bracket',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tournament = _twoGroupPreviewTournament()..activeStageIndex = 1;

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
      await tester.pumpAndSettle();

      expect(find.text('KO · Turnierbaum'), findsOneWidget);
      expect(find.text('6/33 gespielt'), findsOneWidget);
      expect(find.text('KO: 0/3'), findsOneWidget);
      expect(
        find.text('Keine K.-o.-Etappe als Nächstes geplant.'),
        findsNothing,
      );
      expect(find.text('Qualifikant offen'), findsNothing);
      expect(find.text('Bernd'), findsOneWidget);
      expect(find.text('Noah'), findsOneWidget);
      expect(find.text('Spielplan'), findsNothing);
      expect(find.text('Tabellen & Zwischenstände'), findsNothing);
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
    await tester.tap(find.text('Tabellen & Zwischenstände'));
    await tester.pumpAndSettle();
    expect(find.text('Tabellen & Zwischenstände'), findsAtLeastNWidgets(1));
    expect(find.text('Kombiniert'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('widget picker offers the combined forecast widget only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: CreatedTournament(
              name: 'Widget-Auswahl',
              players: const [],
              stages: const [],
              runStages: const [],
            ),
            isStandaloneWindow: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Layout anpassen'));
    await tester.pump();
    await tester.tap(find.text('Widget hinzufügen'));
    await tester.pump();

    final picker = find.byType(SimpleDialog);
    expect(
      find.descendant(
        of: picker,
        matching: find.text('Tabellen/Siegprognose mit Umschalter'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: picker,
        matching: find.text('Siegprognose & Weiterkommen'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shows overall and per-group match counts without progress bars',
    (tester) async {
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

      expect(find.text('3/9 gespielt'), findsOneWidget);
      expect(find.text('3/6'), findsAtLeastNWidgets(2));
      expect(find.text('0/1'), findsAtLeastNWidgets(2));
      expect(find.text('Gesamt'), findsNothing);
      expect(find.text('Fortschritt nach Etappen'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('recent results highlight winners and current qualification', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tournament = _tournament();
    final stage = tournament.runStages.first as GroupTournamentRunStage;
    for (var index = 0; index < stage.groups.single.matches.length; index++) {
      stage.groups.single.matches[index]
        ..homeLegs = 2
        ..awayLegs = 0
        ..finishedAt = DateTime.utc(2026, 1, index + 1);
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

    expect(find.textContaining('Gesetzt'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Ausgeschieden'), findsAtLeastNWidgets(1));
    final recentMatch = find.byKey(const ValueKey('recent-result-6-C-D'));
    expect(recentMatch, findsOneWidget);
    final winnerSpans = <TextSpan>[];
    void collectSpans(InlineSpan span) {
      if (span is! TextSpan) return;
      winnerSpans.add(span);
      for (final child in span.children ?? const <InlineSpan>[]) {
        collectSpans(child);
      }
    }

    for (final richText in tester.widgetList<RichText>(
      find.descendant(of: recentMatch, matching: find.byType(RichText)),
    )) {
      collectSpans(richText.text);
    }
    expect(
      winnerSpans.any(
        (span) =>
            span.text == 'C' && span.style?.color == const Color(0xFF4ED9A4),
      ),
      isTrue,
    );
    expect(
      find.descendant(
        of: recentMatch,
        matching: find.textContaining('Ausgeschieden'),
      ),
      findsOneWidget,
    );
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

  testWidgets('keeps full-height preview visible across right-side modes', (
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
    final fullscreenButton = find.byTooltip('KO-Vorschau im Vollbild öffnen');
    expect(fullscreenButton, findsOneWidget);
    await tester.ensureVisible(fullscreenButton);
    await tester.tap(fullscreenButton);
    await tester.pumpAndSettle();
    expect(find.text('KO · Turnierbaum-Vorschau'), findsNWidgets(2));
    expect(find.text('Zur Übersichtsansicht zurückkehren'), findsOneWidget);
    await tester.tap(find.text('Zur Übersichtsansicht zurückkehren'));
    await tester.pumpAndSettle();
    expect(find.text('KO · Turnierbaum-Vorschau'), findsOneWidget);

    final prognosisTab = find.text('Siegprognose & Weiterkommen');
    await tester.ensureVisible(prognosisTab);
    await tester.tap(prognosisTab);
    await tester.pump();

    expect(
      find.byWidgetPredicate((widget) => widget is SegmentedButton),
      findsOneWidget,
    );
    expect(find.text('KO · Turnierbaum-Vorschau'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('applying an unchanged layout restores the original overview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final storage = _MemoryTournamentStorage();
    final tournament = _tournament();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
            storage: storage,
          ),
        ),
      ),
    );
    await tester.pump();
    final originalBoards = tester.getRect(
      find.text('Nächste Partien · Vorschläge'),
    );
    final standingsTitle = find.text('Tabellen & Zwischenstände').first;
    final originalStandings = tester.getRect(standingsTitle);
    await tester.tap(find.text('Layout anpassen'));
    await tester.pump();

    expect(find.textContaining('Turnieruhr:'), findsOneWidget);

    await tester.tap(find.text('Layout anwenden'));
    await tester.pump();

    expect(find.text('Layout anwenden'), findsNothing);
    expect(find.byTooltip('Höhe verkleinern'), findsNothing);
    expect(
      tester.getRect(find.text('Nächste Partien · Vorschläge')),
      originalBoards,
    );
    expect(tester.getRect(standingsTitle), originalStandings);
    expect(tournament.secondScreenActiveLayout, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('monitor widget columns stack independently', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tournament = _tournament()
      ..secondScreenActiveLayout = 'Standard'
      ..secondScreenLayouts['Standard'] = const [
        SecondScreenWidgetPlacement(
          widgetId: 'boards',
          widthUnits: 2,
          heightUnits: 2,
        ),
        SecondScreenWidgetPlacement(
          widgetId: 'standings',
          widthUnits: 2,
          heightUnits: 2,
        ),
        SecondScreenWidgetPlacement(widgetId: 'recent', widthUnits: 2),
        SecondScreenWidgetPlacement(widgetId: 'stageProgress'),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Layout anpassen'));
    await tester.pump();
    for (var index = 0; index < 2; index++) {
      await tester.tap(find.byTooltip('Höhe verkleinern').first);
      await tester.pump();
    }
    await tester.pump();

    final boards = tester.getRect(
      find.byKey(const ValueKey('monitor-widget-boards')),
    );
    final recent = tester.getRect(
      find.byKey(const ValueKey('monitor-widget-recent')),
    );
    final standings = tester.getRect(
      find.byKey(const ValueKey('monitor-widget-standings')),
    );
    final stageProgress = tester.getRect(
      find.byKey(const ValueKey('monitor-widget-stageProgress')),
    );
    expect(recent.top, greaterThan(boards.top));
    expect(stageProgress.top, greaterThan(standings.top));
    expect(recent.top, lessThan(stageProgress.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('stage progress total includes unplayed future knockout slots', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final players = [
      for (var index = 1; index <= 8; index++)
        TournamentPlayer.generated(index),
    ];
    final tournament = _tournament()
      ..secondScreenActiveLayout = 'Fortschritt'
      ..secondScreenLayouts['Fortschritt'] = const [
        SecondScreenWidgetPlacement(
          widgetId: 'stageProgress',
          widthUnits: 2,
          columnIndex: 1,
        ),
      ];
    tournament.runStages
      ..clear()
      ..addAll([
        GroupTournamentRunStage(
          name: 'Gruppenphase',
          groupPlayType: 'round_robin',
          groups: [
            TournamentGroup(
              name: 'Gruppe A',
              playType: 'round_robin',
              players: players,
              matches: [
                for (var index = 0; index < 56; index++)
                  GroupMatch(
                    homePlayer: players[index % players.length],
                    awayPlayer: players[(index + 1) % players.length],
                    round: index + 1,
                    homeLegs: index < 4 ? 2 : null,
                    awayLegs: index < 4 ? 0 : null,
                  ),
              ],
            ),
          ],
          qualificationPlan: null,
          tieBreakers: const [],
        ),
        KnockoutTournamentRunStage(
          name: 'K.-o.-Runde',
          rounds: [
            [
              for (var index = 0; index < 4; index++)
                GroupMatch(
                  homePlayer: players[index * 2],
                  awayPlayer: players[index * 2 + 1],
                  round: 1,
                ),
            ],
            [for (var index = 0; index < 2; index++) GroupMatch(round: 2)],
            [GroupMatch(round: 3)],
          ],
        ),
      ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('4 von 63 Partien abgeschlossen'), findsOneWidget);
    expect(find.text('4 / 56 Partien'), findsOneWidget);
    expect(find.text('0 / 7 Partien'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kratzer life widget is only available for Kratzer tournaments', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final regularTournament = _tournament();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: regularTournament,
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Layout anpassen'));
    await tester.pump();
    await tester.tap(find.text('Widget hinzufügen'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text('Leben-Übersicht'),
      ),
      findsNothing,
    );
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    final players = _tournament().players;
    final kratzerTournament = CreatedTournament(
      name: 'Kratzer',
      players: players,
      stages: const [TournamentStage(name: 'Kratzer', type: 'single_knockout')],
      runStages: [
        KnockoutTournamentRunStage(
          name: 'Kratzer',
          rounds: [
            [
              GroupMatch(
                isKratzer: true,
                players: players,
                scratchEligiblePlayers: players,
                scratchedPlayer: players[1],
                kratzerBonusLives: [
                  KratzerBonusLife(
                    player: players[2],
                    type: KratzerBonusLifeType.score180,
                  ),
                ],
                round: 1,
              ),
            ],
          ],
          eliminationLossLimit: 2,
          isKratzer: true,
          kratzerHandicapsEnabled: true,
          kratzerHandicaps: const ['Wirf mit der linken Hand'],
          kratzerHandicapAssignments: const {1: 'Wirf mit der linken Hand'},
          participants: players,
        ),
      ],
    );
    final restoredKratzer = CreatedTournament.fromJson(
      kratzerTournament.toJson(),
    );
    final restoredStage =
        restoredKratzer.runStages.single as KnockoutTournamentRunStage;
    expect(restoredStage.kratzerHandicapsEnabled, isTrue);
    expect(restoredStage.kratzerHandicaps, ['Wirf mit der linken Hand']);
    expect(restoredStage.kratzerHandicapAssignments, {
      1: 'Wirf mit der linken Hand',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            key: const ValueKey('kratzer-monitor'),
            tournament: kratzerTournament,
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Layout anpassen'));
    await tester.pump();
    await tester.tap(find.text('Widget hinzufügen'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text('Leben-Übersicht'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Layout anwenden'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('kratzer-life-A')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('kratzer-life-B')),
        matching: find.text('1 Leben'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('kratzer-life-C')),
        matching: find.text('3 Leben'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Layout anpassen'));
    await tester.pump();
    await tester.tap(find.text('Widget hinzufügen'));
    await tester.pumpAndSettle();
    final handicapsOption = find.descendant(
      of: find.byType(SimpleDialog),
      matching: find.text('Handicaps'),
    );
    expect(handicapsOption, findsOneWidget);
    await tester.tap(handicapsOption);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Layout anwenden'));
    await tester.pumpAndSettle();
    expect(find.textContaining('B · Wirf mit der linken Hand'), findsOneWidget);
    expect(tester.takeException(), isNull);

    kratzerTournament
      ..secondScreenActiveLayout = 'Leben Test'
      ..secondScreenLayouts['Leben Test'] = const [
        SecondScreenWidgetPlacement(widgetId: 'kratzerLives', widthUnits: 1),
      ];
    for (final size in [
      const Size(360, 800),
      const Size(800, 600),
      const Size(1440, 900),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(2),
            ),
            child: Scaffold(
              body: TournamentSecondScreenView(
                key: ValueKey('kratzer-monitor-${size.width}'),
                tournament: kratzerTournament,
                isStandaloneWindow: true,
                storage: _MemoryTournamentStorage(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('kratzer-life-A')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('ranking widget can only be added for a ranked tournament', (
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
            storage: _MemoryTournamentStorage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Layout anpassen'));
    await tester.pump();
    await tester.tap(find.text('Widget hinzufügen'));
    await tester.pumpAndSettle();
    expect(find.text('Rangliste'), findsNothing);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Layout anwenden'));
    await tester.pumpAndSettle();

    final rankedTournament = _tournament()
      ..rankingIds = ['elo-ranking']
      ..countsForRanking = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: rankedTournament,
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Layout anpassen'));
    await tester.pump();
    await tester.tap(find.text('Widget hinzufügen'));
    await tester.pumpAndSettle();
    expect(find.text('Rangliste'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'next-stage preview widget is only available for multi-stage tournaments',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final singleStageTournament =
          CreatedTournament.fromJson(_tournament().toJson())
            ..stages.removeLast()
            ..runStages.removeLast();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TournamentSecondScreenView(
              key: const ValueKey('single-stage-monitor'),
              tournament: singleStageTournament,
              isStandaloneWindow: true,
              storage: _MemoryTournamentStorage(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Layout anpassen'));
      await tester.pump();
      await tester.tap(find.text('Widget hinzufügen'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text('Vorschau nächste Etappe'),
        ),
        findsNothing,
      );
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      final tournament = _tournament();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TournamentSecondScreenView(
              key: const ValueKey('multi-stage-monitor'),
              tournament: tournament,
              isStandaloneWindow: true,
              storage: _MemoryTournamentStorage(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Layout anpassen'));
      await tester.pump();
      await tester.tap(find.text('Widget hinzufügen'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text('Vorschau nächste Etappe'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Layout anwenden'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('monitor-next-stage-preview-button')),
        findsOneWidget,
      );
      final previewButton = find.byKey(
        const ValueKey('monitor-next-stage-preview-button'),
      );
      await tester.ensureVisible(previewButton);
      final previewButtonRect = tester.getRect(previewButton);
      expect(previewButtonRect.height, lessThanOrEqualTo(56));
      expect(previewButtonRect.width, lessThanOrEqualTo(240));
      await tester.tap(previewButton);
      await tester.pumpAndSettle();
      expect(find.text('KO · Turnierbaum-Vorschau'), findsOneWidget);
      expect(find.text('Zur Übersichtsansicht zurückkehren'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ranking widget shows selected ELO names and ratings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final alex = TournamentPlayer(
      profileId: 'player-alex',
      name: 'Alexander Schinko',
      isGenerated: false,
    );
    final robin = TournamentPlayer(
      profileId: 'player-robin',
      name: 'Robin Muster',
      isGenerated: false,
    );
    final tournament = CreatedTournament(
      name: 'ELO Test',
      players: [alex, robin],
      stages: const [
        TournamentStage(name: 'Gruppenphase', type: 'groups', groupSizes: [2]),
      ],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppenphase',
          groupPlayType: 'round_robin',
          groups: [
            TournamentGroup(
              name: 'Gruppe A',
              playType: 'round_robin',
              players: [alex, robin],
              matches: [
                GroupMatch(
                  homePlayer: alex,
                  awayPlayer: robin,
                  round: 1,
                  homeLegs: 3,
                  awayLegs: 1,
                ),
              ],
            ),
          ],
          qualificationPlan: null,
          tieBreakers: const [],
        ),
      ],
      countsForRanking: true,
      rankingIds: const ['selected-ranking'],
      secondScreenLayouts: const {
        'ELO': [SecondScreenWidgetPlacement(widgetId: 'ranking')],
      },
      secondScreenActiveLayout: 'ELO',
    );
    const ranking = LocalRanking(
      id: 'selected-ranking',
      name: 'Vereinsrangliste',
    );
    final storage = _MemoryTournamentStorage([tournament]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
            storage: storage,
            database: _RankingTestDatabase(ranking),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vereinsrangliste'), findsOneWidget);
    expect(find.textContaining('Alexander Schinko –'), findsOneWidget);
    expect(find.textContaining('Robin Muster –'), findsOneWidget);
    expect(find.textContaining('Dora Mitglied – 1000 Elo'), findsOneWidget);
    expect(find.textContaining(' Elo'), findsNWidgets(3));
    expect(
      find.byKey(const ValueKey('ranking-elo-delta-player-alex')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ranking-elo-delta-player-robin')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ranking-position-arrow-player-robin')),
      findsOneWidget,
    );
    expect(find.text('Platz 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ranking-participants-toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dora Mitglied –'), findsNothing);
    expect(find.textContaining('Alexander Schinko –'), findsOneWidget);
    expect(find.textContaining('Robin Muster –'), findsOneWidget);
    expect(find.textContaining('Siege'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('layout apply persists an edited intermediate height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final storage = _MemoryTournamentStorage();
    final tournament = _tournament();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
            storage: storage,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Layout anpassen'));
    await tester.pump();
    await tester.tap(find.byTooltip('Höhe verkleinern').first);
    await tester.pump();
    await tester.tap(find.text('Layout anwenden'));
    await tester.pump();

    expect(tournament.secondScreenLayouts['Standard']!.first.heightUnits, 1.5);
    expect(tournament.secondScreenActiveLayout, 'Standard');
    expect(find.text('Layout anwenden'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dropping on a widget lower edge starts a new layout row', (
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
            storage: _MemoryTournamentStorage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Layout anpassen'));
    await tester.pump();
    await tester.tap(find.byTooltip('Höhe verkleinern').first);
    await tester.pump();
    await tester.tap(find.byTooltip('Höhe verkleinern').first);
    await tester.pump();

    final source = find.byKey(const ValueKey('monitor-widget-drag-boards'));
    final sourceRect = tester.getRect(source);
    final target = find.byKey(
      const ValueKey('monitor-widget-drop-target-standings'),
    );
    final targetRect = tester.getRect(target);
    final start = sourceRect.topLeft + const Offset(80, 20);
    final end = Offset(targetRect.center.dx, targetRect.bottom - 8);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: start);
    await mouse.down(start);
    await mouse.moveTo(end);
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Layout anwenden'));
    await tester.pump();

    final placements = tournament.secondScreenLayouts['Standard']!;
    expect(placements.map((placement) => placement.widgetId).toList(), [
      'standings',
      'boards',
      'recent',
      'stageProgress',
    ]);
    expect(placements[1].startsNewRow, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dropping on the other half places a widget in that column', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tournament = _tournament()
      ..secondScreenActiveLayout = 'Standard'
      ..secondScreenLayouts['Standard'] = const [
        SecondScreenWidgetPlacement(
          widgetId: 'boards',
          widthUnits: 2,
          columnIndex: 0,
        ),
        SecondScreenWidgetPlacement(
          widgetId: 'standings',
          widthUnits: 2,
          columnIndex: 0,
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Layout anpassen'));
    await tester.pump();

    final source = find.byKey(const ValueKey('monitor-widget-drag-boards'));
    final sourceRect = tester.getRect(source);
    final target = find.byKey(
      const ValueKey('monitor-widget-drop-target-standings'),
    );
    final targetRect = tester.getRect(target);
    final start = sourceRect.topLeft + const Offset(80, 20);
    final firstEdge = Offset(targetRect.left + 8, targetRect.center.dy);
    final finalEdge = Offset(targetRect.right - 8, targetRect.center.dy);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: start);
    await mouse.down(start);
    await mouse.moveTo(firstEdge);
    await tester.pump();
    await mouse.moveTo(finalEdge);
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Layout anwenden'));
    await tester.pump();

    final placements = tournament.secondScreenLayouts['Standard']!;
    expect(
      placements
          .singleWhere((placement) => placement.widgetId == 'boards')
          .columnIndex,
      1,
    );
    expect(
      placements
          .singleWhere((placement) => placement.widgetId == 'standings')
          .columnIndex,
      0,
      reason: [
        for (final placement in placements)
          '${placement.widgetId}:${placement.columnIndex}',
      ].join(', '),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'layout editor remains usable on a narrow screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MaterialApp(
            home: Scaffold(
              body: TournamentSecondScreenView(
                tournament: _tournament(),
                isStandaloneWindow: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Layout anpassen'));
      await tester.pump();

      expect(find.text('Layout anwenden'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('loaded layout displays widget content without extra cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tournament = _tournament()
      ..secondScreenLayouts['Standard'] = const [
        SecondScreenWidgetPlacement(
          widgetId: 'boards',
          widthUnits: 2,
          columnIndex: 0,
        ),
        SecondScreenWidgetPlacement(
          widgetId: 'standings',
          widthUnits: 2,
          columnIndex: 1,
        ),
      ]
      ..secondScreenActiveLayout = 'Standard';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Tabellen & Zwischenstände'), findsOneWidget);
    expect(find.text('Nächste Partien · Vorschläge'), findsOneWidget);
    expect(find.text('Boards & nächste Begegnungen'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('monitor-widget-standings')),
        matching: find.byType(Card),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('quarter-width widgets fit side by side', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tournament = _tournament()
      ..secondScreenLayouts['Quarter'] = const [
        SecondScreenWidgetPlacement(widgetId: 'boards', widthUnits: 1),
        SecondScreenWidgetPlacement(widgetId: 'standings', widthUnits: 1),
      ]
      ..secondScreenActiveLayout = 'Quarter';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage(),
          ),
        ),
      ),
    );
    await tester.pump();

    final boards = tester.getRect(
      find.byKey(const ValueKey('monitor-widget-boards')),
    );
    final standings = tester.getRect(
      find.byKey(const ValueKey('monitor-widget-standings')),
    );
    expect(boards.center.dy, closeTo(standings.center.dy, 1));
    expect(boards.right, lessThanOrEqualTo(standings.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dragging quarter-width widgets keeps them side by side in a half column',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tournament = _tournament()
        ..secondScreenActiveLayout = 'Quarter'
        ..secondScreenLayouts['Quarter'] = const [
          SecondScreenWidgetPlacement(
            widgetId: 'boards',
            widthUnits: 2,
            columnIndex: 0,
          ),
          SecondScreenWidgetPlacement(
            widgetId: 'standings',
            widthUnits: 2,
            columnIndex: 1,
          ),
          SecondScreenWidgetPlacement(
            widgetId: 'recent',
            widthUnits: 1,
            columnIndex: 0,
          ),
          SecondScreenWidgetPlacement(
            widgetId: 'stageProgress',
            widthUnits: 1,
            columnIndex: 0,
          ),
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TournamentSecondScreenView(
              tournament: tournament,
              isStandaloneWindow: true,
              storage: _MemoryTournamentStorage(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Layout anpassen'));
      await tester.pump();

      final source = find.byKey(
        const ValueKey('monitor-widget-drag-stageProgress'),
      );
      final sourceRect = tester.getRect(source);
      final target = find.byKey(
        const ValueKey('monitor-widget-drop-target-recent'),
      );
      final targetRect = tester.getRect(target);
      final start = sourceRect.topLeft + const Offset(80, 20);
      final end = Offset(targetRect.center.dx, targetRect.bottom - 8);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: start);
      await mouse.down(start);
      await mouse.moveTo(end);
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Layout anwenden'));
      await tester.pumpAndSettle();

      final recent = tester.getRect(
        find.byKey(const ValueKey('monitor-widget-recent')),
      );
      final progress = tester.getRect(
        find.byKey(const ValueKey('monitor-widget-stageProgress')),
      );
      expect(recent.center.dy, closeTo(progress.center.dy, 1));
      expect(recent.right, lessThanOrEqualTo(progress.left));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inactive ranking widget is removed from saved monitor layouts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tournament = _tournament()
      ..countsForRanking = false
      ..rankingIds = ['ranking-id']
      ..secondScreenLayouts['Rangliste'] = const [
        SecondScreenWidgetPlacement(widgetId: 'ranking'),
      ]
      ..secondScreenActiveLayout = 'Rangliste';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('monitor-widget-ranking')), findsNothing);
    expect(tournament.secondScreenLayouts['Rangliste'], isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('standard layout cannot be deleted', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tournament = _tournament()
      ..secondScreenLayouts['Standard'] = const [
        SecondScreenWidgetPlacement(widgetId: 'boards'),
      ]
      ..secondScreenLayouts['Vereins-TV'] = const [
        SecondScreenWidgetPlacement(widgetId: 'standings'),
      ]
      ..secondScreenActiveLayout = 'Vereins-TV';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Layout laden'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byTooltip('Layout "Standard" löschen'), findsNothing);
    expect(find.byTooltip('Layout "Vereins-TV" löschen'), findsOneWidget);
    expect(tournament.secondScreenLayouts, contains('Standard'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('layout loading offers confirmed deletion', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final storage = _MemoryTournamentStorage();
    final tournament = _tournament()
      ..secondScreenLayouts['Vereins-TV'] = const [
        SecondScreenWidgetPlacement(widgetId: 'boards', heightUnits: 1.5),
      ]
      ..secondScreenActiveLayout = 'Vereins-TV';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
            storage: storage,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Layout laden'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Layout "Vereins-TV" löschen'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Löschen'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tournament.secondScreenLayouts, isEmpty);
    expect(tournament.secondScreenActiveLayout, isNull);
    expect(find.byTooltip('Layout "Vereins-TV" löschen'), findsNothing);
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
    final verticalPreview = find.byKey(
      const ValueKey('knockout-preview-vertical-scroll'),
    );
    final verticalScroll = tester.state<ScrollableState>(
      find
          .descendant(of: verticalPreview, matching: find.byType(Scrollable))
          .first,
    );
    expect(verticalScroll.position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('three groups show all eight projected KO qualifiers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: _threeGroupEightQualifierPreviewTournament(),
            isStandaloneWindow: true,
            showNextStagePreviewInitially: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Qualifikant offen').hitTestable(), findsNWidgets(8));
    expect(find.text('Gewinner Spiel 1'), findsNWidgets(2));
    expect(find.text('Gewinner Spiel 2'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows two group tables side by side on a wide monitor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: _threeGroupEightQualifierPreviewTournament(),
            isStandaloneWindow: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final groupATop = tester.getTopLeft(find.text('Gruppe A').last).dy;
    final groupBTop = tester.getTopLeft(find.text('Gruppe B').last).dy;
    final groupCTop = tester.getTopLeft(find.text('Gruppe C').last).dy;
    expect(groupATop, closeTo(groupBTop, 1));
    expect(groupCTop, greaterThan(groupATop));
    expect(find.text('Top 3 weiter'), findsNWidgets(2));
    expect(find.text('Top 2 weiter'), findsOneWidget);
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

CreatedTournament _threeGroupEightQualifierPreviewTournament() {
  final players = [
    for (var index = 1; index <= 18; index++)
      TournamentPlayer.generated(index).copyWith(name: 'Spieler $index'),
  ];
  final groups = [
    for (var groupIndex = 0; groupIndex < 3; groupIndex++)
      TournamentGroup(
        name: 'Gruppe ${String.fromCharCode(65 + groupIndex)}',
        playType: 'round_robin',
        players: players.skip(groupIndex * 6).take(6).toList(),
        matches: const [],
      ),
  ];
  return CreatedTournament(
    name: 'Drei Gruppen, acht Qualifikanten',
    players: players,
    stages: const [
      TournamentStage(
        name: 'Gruppenphase',
        type: 'groups',
        groupSizes: [6, 6, 6],
        qualifiedParticipantCount: 8,
      ),
      TournamentStage(
        name: 'KO',
        type: 'single_knockout',
        knockoutParticipantCount: 8,
      ),
    ],
    runStages: [
      GroupTournamentRunStage(
        name: 'Gruppenphase',
        groupPlayType: 'round_robin',
        groups: groups,
        qualificationPlan: const QualificationPlan(
          totalQualifiers: 8,
          fixedPerGroup: 2,
          extraCount: 2,
          extraRank: 3,
          eligibleGroupSize: null,
          extraGroups: [1, 2],
          fixedByGroup: [3, 3, 2],
        ),
        tieBreakers: defaultGroupTieBreakers,
      ),
      KnockoutTournamentRunStage(
        name: 'KO',
        rounds: [
          [for (var index = 0; index < 4; index++) GroupMatch(round: 1)],
          [for (var index = 0; index < 2; index++) GroupMatch(round: 2)],
          [GroupMatch(round: 3)],
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

CreatedTournament _tournamentWithPlayerInsights() {
  final marvin = TournamentPlayer.generated(1).copyWith(name: 'Marvin');
  final opponent = TournamentPlayer.generated(2).copyWith(name: 'Daniel');
  final nextOpponent = TournamentPlayer.generated(3).copyWith(name: 'Alex');
  final matches = [
    for (var index = 0; index < 3; index++)
      GroupMatch(
        homePlayer: marvin,
        awayPlayer: opponent,
        round: index + 1,
        homeLegs: 2,
        awayLegs: 0,
        finishedAt: DateTime.utc(2026, 3, index + 1),
      ),
    GroupMatch(homePlayer: marvin, awayPlayer: nextOpponent, round: 4),
  ];
  final date = DateTime.utc(2026, 3, 10);
  return CreatedTournament(
    id: 'player-insight-test',
    name: 'Player-Insights',
    createdAt: date,
    tournamentDate: date,
    players: [marvin, opponent, nextOpponent],
    stages: const [TournamentStage(name: 'Gruppe', type: 'groups')],
    runStages: [
      GroupTournamentRunStage(
        name: 'Gruppenphase',
        groupPlayType: 'round_robin',
        groups: [
          TournamentGroup(
            name: 'Gruppe A',
            playType: 'round_robin',
            players: [marvin, opponent, nextOpponent],
            matches: matches,
          ),
        ],
        qualificationPlan: null,
        tieBreakers: const [],
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

class _MemoryTournamentStorage extends TournamentStorage {
  _MemoryTournamentStorage([this.tournaments = const []]);

  final List<CreatedTournament> tournaments;

  @override
  Future<List<CreatedTournament>> loadTournaments() async => tournaments;

  @override
  Future<void> saveSecondScreenLayout({
    required CreatedTournament tournament,
    required String name,
    required List<SecondScreenWidgetPlacement>? placements,
    required bool activate,
  }) async {
    if (placements == null) {
      tournament.secondScreenLayouts.remove(name);
      if (tournament.secondScreenActiveLayout == name) {
        tournament.secondScreenActiveLayout = null;
      }
      return;
    }
    tournament.secondScreenLayouts[name] =
        List<SecondScreenWidgetPlacement>.from(placements);
    if (activate) tournament.secondScreenActiveLayout = name;
  }
}

class _PlayerInsightTestDatabase extends LocalAppDatabase {
  @override
  Future<List<LocalRanking>> loadLocalRankings() async => const [];

  @override
  Future<List<PlayerMonthlyPerformance>> loadPlayerMonthlyPerformanceForPlayers(
    Set<String> playerIds, {
    int? year,
  }) async => const [];
}

class _RankingTestDatabase extends LocalAppDatabase {
  _RankingTestDatabase(this.ranking);

  final LocalRanking ranking;

  @override
  Future<List<LocalRanking>> loadLocalRankings() async => [ranking];

  @override
  Future<List<String>> loadRankingPlayerIds(String rankingId) async => [
    'player-alex',
    'player-robin',
    'player-other',
  ];

  @override
  Future<List<PlayerProfile>> loadPlayerProfiles() async => [
    PlayerProfile(
      id: 'player-alex',
      displayName: 'Alexander Schinko',
      country: '',
      city: '',
      dartsSetupJson: '',
      createdAt: DateTime(2026),
      isActive: true,
    ),
    PlayerProfile(
      id: 'player-robin',
      displayName: 'Robin Muster',
      country: '',
      city: '',
      dartsSetupJson: '',
      createdAt: DateTime(2026),
      isActive: true,
    ),
    PlayerProfile(
      id: 'player-other',
      displayName: 'Dora Mitglied',
      country: '',
      city: '',
      dartsSetupJson: '',
      createdAt: DateTime(2026),
      isActive: true,
    ),
  ];
}
