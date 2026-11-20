import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:dart_tournament_manager/app/theme_controller.dart';
import 'package:dart_tournament_manager/features/league/application/league_board_runtime.dart';
import 'package:dart_tournament_manager/features/league/domain/league_match.dart';
import 'package:dart_tournament_manager/features/league/presentation/league_overview.dart';
import 'package:dart_tournament_manager/features/statistics/domain/best_performance.dart';
import 'package:dart_tournament_manager/features/tournaments/application/group_advancement_forecast_service.dart';
import 'package:dart_tournament_manager/features/tournaments/application/order_of_play/order_of_play_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_director_snapshot.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/engines/group_advancement_forecast_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/second_screen_dialog_requests.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/second_screen_widget_placement.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/statistics/domain/player_monthly_performance.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/tournament_second_screen_view.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/recommended_matches_table.dart';
import 'package:dart_tournament_manager/shared/theme/tournament_display_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  BoxDecoration badgeDecoration(WidgetTester tester, Finder badge) {
    final decorated = find.descendant(
      of: badge,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox && widget.decoration is BoxDecoration,
      ),
    );
    return tester.widget<DecoratedBox>(decorated.first).decoration
        as BoxDecoration;
  }

  testWidgets('recommended table splits two groups into four match columns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetDevicePixelRatio);

    final players = [
      for (var index = 1; index <= 8; index++)
        TournamentPlayer.generated(index).copyWith(name: 'Teilnehmer $index'),
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
        TournamentPlayer.generated(index).copyWith(name: 'Teilnehmer $index'),
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
    expect(find.text('Nächste Begegnungen'), findsOneWidget);
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

  testWidgets(
    'merge mode releases a board with no remaining assigned matches',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tournament = _tournament()
        ..directorModeEnabled = true
        ..directorSchedulingStrategy = 'group'
        ..directorPlayOrderMode = 'fixed_schedule'
        ..directorMultiBoardAssignmentBehavior = 'merge'
        ..directorGroupBoardAssignments['0:Gruppe A'] = [1, 2]
        ..boardCount = 2;
      const OrderOfPlayController().initializeFixedSchedule(tournament);
      final mergeSnapshot = TournamentDirectorSnapshot(tournament, 0);
      expect(mergeSnapshot.mergedGroupBoards(), isEmpty);

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

      expect(
        find.byKey(const ValueKey('second-screen-director-boards-1-2')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('second-screen-director-board-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('second-screen-director-board-2')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'merged board pair fills the first row above two half-width boards',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final groups = [
        for (var groupIndex = 0; groupIndex < 4; groupIndex++)
          () {
            final players = [
              for (var playerIndex = 0; playerIndex < 4; playerIndex++)
                TournamentPlayer.generated(
                  groupIndex * 4 + playerIndex + 1,
                ).copyWith(name: 'Spieler ${groupIndex * 4 + playerIndex + 1}'),
            ];
            return TournamentGroup(
              name: 'Gruppe ${String.fromCharCode(65 + groupIndex)}',
              playType: 'round_robin',
              players: players,
              matches: [
                for (var home = 0; home < players.length; home++)
                  for (var away = home + 1; away < players.length; away++)
                    GroupMatch(
                      homePlayer: players[home],
                      awayPlayer: players[away],
                      round: home + away + 1,
                    ),
              ],
            );
          }(),
      ];
      final tournament =
          CreatedTournament(
              name: 'Zusammengeführte Boards',
              players: groups.expand((group) => group.players).toList(),
              stages: const [
                TournamentStage(
                  name: 'Gruppenphase',
                  type: 'groups',
                  groupSizes: [4, 4, 4, 4],
                ),
              ],
              boardCount: 4,
              directorModeEnabled: true,
              directorSchedulingStrategy: 'group',
              directorPlayOrderMode: 'fixed_schedule',
              directorMultiBoardAssignmentBehavior: 'merge',
              runStages: [
                GroupTournamentRunStage(
                  name: 'Gruppenphase',
                  groupPlayType: 'round_robin',
                  groups: groups,
                  qualificationPlan: null,
                  tieBreakers: defaultGroupTieBreakers,
                ),
              ],
            )
            ..directorGroupBoardAssignments.addAll({
              '0:Gruppe A': [1, 2],
              '0:Gruppe B': [2],
              '0:Gruppe C': [3],
              '0:Gruppe D': [4],
            });
      const OrderOfPlayController().initializeFixedSchedule(tournament);

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

      final merged = find.byKey(
        const ValueKey('second-screen-director-boards-1-2'),
      );
      final boardThree = find.byKey(
        const ValueKey('second-screen-director-board-3'),
      );
      final boardFour = find.byKey(
        const ValueKey('second-screen-director-board-4'),
      );
      expect(merged, findsOneWidget);
      expect(boardThree, findsOneWidget);
      expect(boardFour, findsOneWidget);
      final mergedRect = tester.getRect(merged);
      final boardThreeRect = tester.getRect(boardThree);
      final boardFourRect = tester.getRect(boardFour);
      expect(mergedRect.width, closeTo(boardThreeRect.width * 2 + 6, 1));
      expect(boardThreeRect.top, greaterThan(mergedRect.bottom));
      expect(boardThreeRect.top, closeTo(boardFourRect.top, 1));
      expect(boardThreeRect.left, closeTo(mergedRect.left, 1));
      expect(boardFourRect.left, greaterThan(boardThreeRect.left));
      expect(boardThreeRect.width, closeTo(boardFourRect.width, 1));

      final firstSuggestion = tester.getTopLeft(
        find.descendant(of: merged, matching: find.text('1.')),
      );
      final fourthSuggestion = tester.getTopLeft(
        find.descendant(of: merged, matching: find.text('4.')),
      );
      expect(firstSuggestion.dx, lessThan(fourthSuggestion.dx));
      expect(
        find
            .descendant(
              of: merged,
              matching: find.textContaining('Empfohlene Partien'),
            )
            .evaluate(),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('four boards show three suggestions without scrolling at 1080p', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final groups = [
      for (var groupIndex = 0; groupIndex < 4; groupIndex++)
        () {
          final players = [
            for (var playerIndex = 0; playerIndex < 4; playerIndex++)
              TournamentPlayer.generated(
                groupIndex * 4 + playerIndex + 1,
              ).copyWith(name: 'Spieler ${groupIndex * 4 + playerIndex + 1}'),
          ];
          return TournamentGroup(
            name: 'Gruppe ${String.fromCharCode(65 + groupIndex)}',
            playType: 'round_robin',
            players: players,
            matches: [
              for (var home = 0; home < players.length; home++)
                for (var away = home + 1; away < players.length; away++)
                  GroupMatch(
                    homePlayer: players[home],
                    awayPlayer: players[away],
                    round: home + away + 1,
                  ),
            ],
          );
        }(),
    ];
    final tournament =
        CreatedTournament(
            name: 'Vier Boards mit Vorschlägen',
            players: groups.expand((group) => group.players).toList(),
            stages: const [
              TournamentStage(
                name: 'Gruppenphase',
                type: 'groups',
                groupSizes: [4, 4, 4, 4],
              ),
            ],
            boardCount: 4,
            directorModeEnabled: true,
            directorSchedulingStrategy: 'group',
            directorPlayOrderMode: 'fixed_schedule',
            runStages: [
              GroupTournamentRunStage(
                name: 'Gruppenphase',
                groupPlayType: 'round_robin',
                groups: groups,
                qualificationPlan: null,
                tieBreakers: defaultGroupTieBreakers,
              ),
            ],
          )
          ..directorGroupBoardAssignments.addAll({
            for (var groupIndex = 0; groupIndex < 4; groupIndex++)
              '0:Gruppe ${String.fromCharCode(65 + groupIndex)}': [
                groupIndex + 1,
              ],
          });
    const OrderOfPlayController().initializeFixedSchedule(tournament);
    final orderOfPlay = const OrderOfPlayController();
    for (var board = 1; board <= 4; board++) {
      final assignment = orderOfPlay
          .plan(tournament, 0)
          .planned
          .firstWhere((assignment) => assignment.board == board);
      expect(
        orderOfPlay.start(tournament, 0, assignment.entry.match, board),
        isTrue,
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
    await tester.pumpAndSettle();

    expect(find.text('LIVE'), findsNWidgets(4));
    for (final player in tournament.players) {
      expect(find.text(player.shortDisplayName), findsAtLeastNWidgets(1));
    }
    for (var board = 1; board <= 4; board++) {
      for (var suggestion = 0; suggestion < 3; suggestion++) {
        expect(
          find.byKey(
            ValueKey(
              'second-screen-director-recommendation-$board-$suggestion',
            ),
          ),
          findsOneWidget,
        );
      }
    }
    final activeTiles = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'second-screen-running-match-',
          ),
    );
    expect(activeTiles, findsNWidgets(4));
    expect(
      [
        for (final tile in tester.widgetList(activeTiles))
          tester.getRect(find.byWidget(tile)),
      ].every((rect) => rect.bottom <= 1080),
      isTrue,
    );
    final queueScroll = find.byKey(
      const ValueKey('second-screen-director-queue-scroll'),
    );
    final scrollable = find.descendant(
      of: queueScroll,
      matching: find.byType(Scrollable),
    );
    expect(
      tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
      0,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed tournament overview stays open with all placements', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final finished = DateTime.now();
    final tournament = _tournament()
      ..startedAt = finished.subtract(const Duration(hours: 2, minutes: 15))
      ..finishedAt = finished
      ..directorModeEnabled = true;
    var closeCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
            onClose: () => closeCount++,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Turnier abgeschlossen'), findsOneWidget);
    expect(find.textContaining('2 h 15 min'), findsOneWidget);
    expect(find.text('Platzierungen'), findsOneWidget);
    expect(find.text('Podium'), findsNothing);
    for (final playerName in ['A', 'B', 'C', 'D']) {
      expect(find.text(playerName), findsOneWidget);
    }
    expect(find.text('Ranglistenänderungen'), findsOneWidget);
    expect(find.text('Bestleistungen'), findsOneWidget);
    expect(
      find.textContaining('Keine Bestleistungen eingetragen.'),
      findsNothing,
    );
    expect(find.textContaining('A · 171+'), findsOneWidget);
    expect(closeCount, 0);
    await tester.pump(const Duration(seconds: 61));
    expect(closeCount, 0);
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pump();
    expect(closeCount, 1);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('league completion overview uses league categories at $size', (
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
              tournament: _completedLeagueTournament(),
              isStandaloneWindow: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Turnier abgeschlossen'), findsOneWidget);
      expect(find.text('Mannschaftsvergleich'), findsOneWidget);
      expect(find.text('Spielbilanz'), findsOneWidget);
      expect(find.text('Bestleistungen'), findsOneWidget);
      expect(find.text('Platzierungen'), findsNothing);
      expect(find.text('Ranglistenänderungen'), findsNothing);
      expect(
        find.textContaining('Heimmannschaft 1:1 Gastmannschaft'),
        findsOneWidget,
      );
      expect(find.text('Lena'), findsOneWidget);
      expect(find.text('Sp'), findsNWidgets(2));
      expect(find.textContaining('Lena · 180+'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'league combined widget shows the team comparison in the second monitor',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tournament = _completedLeagueTournament()
        ..finishedAt = null
        ..secondScreenLayouts['Standard'] = const [
          SecondScreenWidgetPlacement(widgetId: 'combined', widthUnits: 4),
        ]
        ..secondScreenActiveLayout = 'Standard';
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

      expect(
        find.text('Keine KO-Phase im aktuellen Turnier geplant.'),
        findsNothing,
      );
      await tester.tap(find.text('Mannschaftsvergleich').last);
      await tester.pumpAndSettle();

      expect(find.byType(LeagueOverview), findsWidgets);
      expect(find.text('Heimmannschaft'), findsWidgets);
      expect(find.text('Gastmannschaft'), findsWidgets);
      expect(
        find.text('Keine KO-Phase im aktuellen Turnier geplant.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('league substitutions appear in the monitor activity panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const message =
        'Heimmannschaft hat Lena gegen Jonas ausgewechselt. '
        'Übrige Auswechselungen: 1';
    final tournament = _completedLeagueTournament()
      ..finishedAt = null
      ..addActivity(
        'substitution',
        message,
        timestamp: DateTime(2026, 11, 17, 11, 30),
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

    expect(find.text('Aktuelles'), findsOneWidget);
    expect(find.text(message), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('running matches are clearly separated from suggestions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tournament = _tournament()
      ..directorModeEnabled = true
      ..boardCount = 4;
    final match = const OrderOfPlayController()
        .plan(tournament, 0)
        .planned
        .first
        .entry
        .match;
    match
      ..homePlayer = match.homePlayer!.copyWith(name: 'Alexanderson')
      ..awayPlayer = match.awayPlayer!.copyWith(name: 'Robinson');
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

    expect(find.text('Board Belegung & aktive Partien'), findsOneWidget);
    expect(find.text('BESETZT'), findsNothing);
    expect(find.textContaining('Empfohlene Partien'), findsNWidgets(4));
    expect(find.text('BELEGT'), findsNothing);
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.textContaining('Partie läuft seit '), findsNothing);
    final runningTile = find.byKey(
      ValueKey(
        'second-screen-running-match-${match.round}-'
        '${match.homePlayer?.profileId ?? match.homePlayer?.name}-'
        '${match.awayPlayer?.profileId ?? match.awayPlayer?.name}',
      ),
    );
    expect(runningTile, findsOneWidget);
    expect(tester.getSize(runningTile).height, lessThan(110));
    final freeTile = find.byKey(const ValueKey('second-screen-free-board-2'));
    expect(freeTile, findsOneWidget);
    expect(
      tester.getSize(freeTile).height,
      closeTo(tester.getSize(runningTile).height, 1),
    );
    for (final name in ['Alexanderson', 'Robinson']) {
      final nameText = tester.widget<Text>(
        find.descendant(of: runningTile, matching: find.text(name)),
      );
      expect(nameText.maxLines, 1);
      expect(nameText.style?.fontSize, 14);
    }
    expect(find.text('Nächste Begegnungen'), findsOneWidget);
    expect(find.textContaining('Empfohlene Partien'), findsWidgets);
    final nextHeading = find.text('Nächste Begegnungen');
    final recentHeading = find.text('Zuletzt beendete Matches');
    expect(recentHeading, findsOneWidget);
    expect(
      tester.getRect(recentHeading).top,
      greaterThan(tester.getRect(nextHeading).bottom),
    );
    expect(find.textContaining('EMPFOHLENE PARTIEN FÜR BOARD 1'), findsNothing);
    expect(find.textContaining('JETZT ZUWEISEN'), findsNothing);
    expect(find.textContaining('Empfohlene Partien · Gruppe A'), findsWidgets);
    final firstBoardQueueFinder = find.byKey(
      const ValueKey('second-screen-director-board-1'),
    );
    expect(
      find.descendant(
        of: firstBoardQueueFinder,
        matching: find.textContaining('JETZT ZUWEISEN'),
      ),
      findsNothing,
    );
    final firstBoardQueue = tester.widget<Container>(firstBoardQueueFinder);

    // Board status text was removed; border color still reflects status (tested below).
    final queueDecoration = firstBoardQueue.decoration! as BoxDecoration;
    expect(queueDecoration.border!.top.color, TournamentDisplayPalette.accent);
    expect(find.text('Aktuell: ${match.participantShortLabel}'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'assigning a match shows the preparing animation on the standalone TV',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tournament = _tournament()
        ..directorModeEnabled = true
        ..boardCount = 2;

      Widget buildView() => MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            key: const ValueKey('tv'),
            tournament: tournament,
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage([tournament]),
          ),
        ),
      );

      await tester.pumpWidget(buildView());
      await tester.pumpAndSettle();
      expect(find.text('In Vorbereitung'), findsNothing);

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
      await tester.pumpWidget(buildView());
      await tester.pump();

      expect(find.text('In Vorbereitung'), findsOneWidget);
      expect(find.text('LIVE'), findsNothing);
      expect(
        find.byKey(const ValueKey('second-screen-preparing-board-1')),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(find.text('In Vorbereitung'), findsNothing);
      expect(find.text('LIVE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a finished match keeps its green board animation for ten seconds',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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

      Widget buildView() => MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            key: const ValueKey('tv'),
            tournament: tournament,
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage([tournament]),
          ),
        ),
      );

      await tester.pumpWidget(buildView());
      await tester.pumpAndSettle();
      expect(find.text('LIVE'), findsOneWidget);

      match
        ..homeLegs = 2
        ..awayLegs = 0
        ..finishedAt = DateTime.now();
      await tester.pumpWidget(buildView());
      await tester.pump();

      expect(find.text('Partie beendet'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('second-screen-finished-board-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('second-screen-finished-badge-1')),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(find.text('Partie beendet'), findsNothing);
      expect(
        find.byKey(const ValueKey('second-screen-free-board-1')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'board status animation pulses only the border and keeps badge geometry',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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

      Widget buildView() => MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            key: const ValueKey('tv'),
            tournament: tournament,
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage([tournament]),
          ),
        ),
      );

      await tester.pumpWidget(buildView());
      await tester.pumpAndSettle();
      expect(find.text('LIVE'), findsOneWidget);

      match
        ..homeLegs = 2
        ..awayLegs = 0
        ..finishedAt = DateTime.now();
      await tester.pumpWidget(buildView());
      await tester.pump();
      final badge = find.byKey(
        const ValueKey('second-screen-finished-badge-1'),
      );
      expect(badge, findsOneWidget);

      final startRect = tester.getRect(badge);
      final startDecoration = badgeDecoration(tester, badge);
      await tester.pump(const Duration(milliseconds: 300));
      final laterDecoration = badgeDecoration(tester, badge);
      final laterRect = tester.getRect(badge);

      // Der animierte Badge hat exakt dieselbe feste Borderstärke wie der
      // ruhende Status-Badge, sonst wächst die Kachel und verschiebt Controls.
      expect(startDecoration.border!.top.width, 1);
      expect(startDecoration.boxShadow, isNull);
      expect(laterDecoration.boxShadow, isNull);
      expect(
        startDecoration.border!.top.color,
        isNot(laterDecoration.border!.top.color),
      );
      expect(startDecoration.color, isNot(laterDecoration.color));

      // Nach der halben Laufzeit ist der zweite Blink wieder auf dem hellen
      // Ausgangswert angekommen.
      await tester.pump(const Duration(milliseconds: 300));
      final secondBlinkDecoration = badgeDecoration(tester, badge);
      expect(
        secondBlinkDecoration.border!.top.color,
        startDecoration.border!.top.color,
      );
      expect(secondBlinkDecoration.color, startDecoration.color);

      expect(laterRect.width, closeTo(startRect.width, 0.5));
      expect(laterRect.height, closeTo(startRect.height, 0.5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a new best performance opens a confetti popup for three seconds',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tournament = _tournament()
        ..directorModeEnabled = true
        ..boardCount = 2;

      Widget buildView() => MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            key: const ValueKey('tv'),
            tournament: tournament,
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage([tournament]),
          ),
        ),
      );

      await tester.pumpWidget(buildView());
      await tester.pumpAndSettle();
      expect(find.text('180 von Robin'), findsNothing);

      final match = const OrderOfPlayController()
          .plan(tournament, 0)
          .planned
          .first
          .entry
          .match;
      match.bestPerformances = [
        ...match.bestPerformances,
        const BestPerformance(
          type: BestPerformanceType.score180,
          playerName: 'Robin',
        ),
      ];
      await tester.pumpWidget(buildView());
      await tester.pump();

      expect(find.text('180 von Robin'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'second-screen-best-performance-popup-',
              ),
        ),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('180 von Robin'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('four active matches use a two-column board layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final players = [
      for (var index = 1; index <= 8; index++)
        TournamentPlayer.generated(index).copyWith(name: 'Teilnehmer $index'),
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
    expect(find.text('LIVE'), findsNWidgets(4));
    for (final player in players) {
      expect(find.text(player.shortDisplayName), findsAtLeastNWidgets(1));
    }
    final boardRects = [
      for (final tile in tester.widgetList(tiles))
        tester.getRect(find.byWidget(tile)),
    ];
    expect(boardRects[0].top, closeTo(boardRects[1].top, 1));
    expect(boardRects[2].top, closeTo(boardRects[3].top, 1));
    expect(boardRects[2].top, greaterThan(boardRects[0].bottom));
    expect(boardRects[0].left, closeTo(boardRects[2].left, 1));
    expect(boardRects[1].left, closeTo(boardRects[3].left, 1));
    expect(boardRects[1].left, greaterThan(boardRects[0].left));
    expect(boardRects[0].width, closeTo(boardRects[1].width, 1));
    expect(boardRects[2].width, closeTo(boardRects[3].width, 1));
    expect(boardRects.every((rect) => rect.bottom <= 1080), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long active player names stack without changing board tile height',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final players = [
        TournamentPlayer.generated(
          1,
        ).copyWith(name: 'JohannesRothVeryLongName'),
        TournamentPlayer.generated(
          2,
        ).copyWith(name: 'MichaelSchneiderVeryLongName'),
        TournamentPlayer.generated(3).copyWith(name: 'Spieler 3'),
        TournamentPlayer.generated(4).copyWith(name: 'Spieler 4'),
      ];
      final matches = [
        for (var index = 0; index < 2; index++)
          GroupMatch(
            homePlayer: players[index * 2],
            awayPlayer: players[index * 2 + 1],
            round: 1,
          ),
      ];
      final tournament = CreatedTournament(
        name: 'Lange Namen',
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
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: Scaffold(
                body: TournamentSecondScreenView(
                  tournament: tournament,
                  isStandaloneWindow: true,
                  storage: _MemoryTournamentStorage([tournament]),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final firstTile = find.byKey(
        const ValueKey(
          'second-screen-running-match-1-JohannesRothVeryLongName-'
          'MichaelSchneiderVeryLongName',
        ),
      );
      final secondTile = find.byKey(
        const ValueKey('second-screen-running-match-1-Spieler 3-Spieler 4'),
      );
      expect(firstTile, findsOneWidget);
      expect(secondTile, findsOneWidget);
      final firstName = find.descendant(
        of: firstTile,
        matching: find.text('JohannesRothVeryLongName'),
      );
      final secondName = find.descendant(
        of: firstTile,
        matching: find.text('MichaelSchneiderVeryLongName'),
      );
      expect(
        tester.getTopLeft(firstName).dy,
        lessThan(tester.getTopLeft(secondName).dy),
      );
      expect(
        tester.getRect(firstTile).height,
        closeTo(tester.getRect(secondTile).height, 1),
      );
      expect(tester.takeException(), isNull);
    },
  );

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

    expect(find.text('Insights'), findsNothing);
    expect(
      find.byKey(const ValueKey('second-screen-player-insights')),
      findsNothing,
    );
    expect(find.text('Hot Streak'), findsOneWidget);
    expect(
      find.byTooltip('Marvin hat seine letzten 3 Matches in Folge gewonnen.'),
      findsOneWidget,
    );

    final runningMatch =
        (tournament.runStages.single as GroupTournamentRunStage)
            .groups
            .single
            .matches
            .last;
    expect(
      const OrderOfPlayController().start(tournament, 0, runningMatch, 1),
      isTrue,
    );
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
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message?.startsWith(
                  'Hot Streak: Marvin hat seine letzten 3 Matches in Folge gewonnen.',
                ) ??
                false),
      ),
      findsOneWidget,
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
    expect(
      find.byTooltip(
        'Hot Streak: Marvin hat seine letzten 3 Matches in Folge gewonnen.',
      ),
      findsNothing,
    );

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

  testWidgets('second screen shows a status tile for every configured board', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tournament = _tournament()
      ..boardCount = 4
      ..directorModeEnabled = true;
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

    for (var board = 1; board <= 4; board++) {
      expect(
        find.byKey(ValueKey('second-screen-director-board-$board')),
        findsOneWidget,
      );
    }
    for (var board = 2; board <= 4; board++) {
      final boardTile = find.byKey(
        ValueKey('second-screen-director-board-$board'),
      );
      final occupancyTile = find.byKey(
        ValueKey('second-screen-free-board-$board'),
      );
      expect(tester.getSize(occupancyTile).height, lessThan(74));
      expect(
        find.descendant(
          of: boardTile,
          matching: find.textContaining('Empfohlene Partien'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: occupancyTile,
          matching: find.text('JETZT PARTIE ZUWEISEN'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: boardTile,
          matching: find.textContaining('JETZT ZUWEISEN'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: occupancyTile,
          matching: find.text('Aktuell keine Partie'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: occupancyTile,
          matching: find.text('AKTUELL NICHT BESETZT'),
        ),
        findsNothing,
      );
    }
    await tester.pump(const Duration(seconds: 20));
    final boardTwoOccupancy = find.byKey(
      const ValueKey('second-screen-free-board-2'),
    );
    expect(
      find.descendant(
        of: boardTwoOccupancy,
        matching: find.text('JETZT PARTIE ZUWEISEN'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('second-screen-director-board-2')),
        matching: find.textContaining('JETZT ZUWEISEN'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Christmas standings widgets use translucent cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final styleNotifier = AppThemeController.instance.themeStyleNotifier;
    addTearDown(() => styleNotifier.value = AppThemeStyle.club);
    styleNotifier.value = AppThemeStyle.christmas;

    final tournament = _tournament()
      ..secondScreenLayouts['Christmas'] = const [
        SecondScreenWidgetPlacement(widgetId: 'standings', widthUnits: 2),
      ]
      ..secondScreenActiveLayout = 'Christmas';
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
    await tester.pump();

    final standingsCard = tester.widget<Container>(
      find.byKey(const ValueKey('second-screen-standings-group-1')),
    );
    expect(
      (standingsCard.decoration! as BoxDecoration).color,
      const Color(0xFF14202B).withValues(alpha: .84),
    );
    expect(tester.takeException(), isNull);
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
          name: 'Teilnehmername mit außergewöhnlicher Länge Nummer $index',
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
                  'Teilnehmername mit außergewöhnlicher Länge',
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

  testWidgets('a taller recent tile shows more than two results at once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tournament = _tournament();
    final group =
        (tournament.runStages.first as GroupTournamentRunStage).groups.first;
    for (var index = 0; index < 6; index++) {
      group.matches.add(
        GroupMatch(
          homePlayer: group.players[index % group.players.length],
          awayPlayer: group.players[(index + 1) % group.players.length],
          round: 10 + index,
          homeLegs: 2,
          awayLegs: 0,
          finishedAt: DateTime(2026, 11, 20, 10, index),
        ),
      );
    }
    tournament
      ..secondScreenActiveLayout = 'Tall'
      ..secondScreenLayouts['Tall'] = const [
        SecondScreenWidgetPlacement(
          widgetId: 'recent',
          widthUnits: 2,
          heightUnits: 3,
        ),
      ];

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

    final viewport = tester.getRect(
      find.byKey(const ValueKey('recent-results-scroll')),
    );
    expect(viewport.height, greaterThan(2 * 66));
    final rows = find.byWidgetPredicate(
      (widget) => widget.key?.toString().contains('recent-result-') ?? false,
    );
    expect(rows, findsAtLeastNWidgets(3));
    final rowRects = [
      'recent-result-15-B-C',
      'recent-result-14-A-B',
      'recent-result-13-D-A',
    ].map((key) => tester.getRect(find.byKey(ValueKey(key)))).toList();
    expect(
      rowRects.where(
        (rect) => rect.top >= viewport.top && rect.bottom <= viewport.bottom,
      ),
      hasLength(3),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('unassigned manual groups show a notice and success feedback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    CreatedTournament withManualGroups({required bool assigned}) {
      final source = _tournament();
      return CreatedTournament(
        name: source.name,
        players: source.players,
        stages: [
          source.stages[0].copyWith(
            groupAssignmentMode: 'manual',
            groupSlotOrder: assigned ? const [1, 2, 3, 4] : const [],
            groupDrawCompleted: assigned,
          ),
          source.stages[1],
        ],
        runStages: source.runStages,
        boardCount: source.boardCount,
      );
    }

    CreatedTournament current = withManualGroups(assigned: false);
    StateSetter? refresh;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setBuilderState) {
            refresh = setBuilderState;
            return Scaffold(
              body: TournamentSecondScreenView(
                tournament: current,
                isStandaloneWindow: true,
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Zuweisung der Gruppen noch nicht erfolgt! Die Gruppen sind aktuell nur alphabetisch und vorläufig für die Darstellung sortiert.',
      ),
      findsOneWidget,
    );

    current = withManualGroups(assigned: true);
    refresh!(() {});
    await tester.pump();

    expect(
      find.text(
        'Zuweisung der Gruppen noch nicht erfolgt! Die Gruppen sind aktuell nur alphabetisch und vorläufig für die Darstellung sortiert.',
      ),
      findsNothing,
    );
    expect(find.text('Gruppen erfolgreich zugewiesen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('next-stage preview shows the optional third-place match', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tournament = _tournament();
    final ko = tournament.runStages[1] as KnockoutTournamentRunStage;
    tournament.runStages[1] = KnockoutTournamentRunStage(
      name: ko.name,
      rounds: ko.rounds,
      placementMatches: [
        GroupMatch(
          round: 101,
          placementKey: 'ko/0',
          placementRank: 3,
          label: 'Spiel um Platz 3',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
            showNextStagePreviewInitially: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('KO · Turnierbaum-Vorschau'), findsOneWidget);
    expect(find.text('Finale / Spiel um Platz 3'), findsOneWidget);
    expect(find.text('Begegnung um Platz 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

      expect(find.text('Vorschau nächste Phase'), findsOneWidget);
      await tester.tap(find.text('Vorschau nächste Phase'));
      await tester.pumpAndSettle();

      expect(find.text('KO · Turnierbaum-Vorschau'), findsOneWidget);
      expect(find.textContaining('A · gesetzt'), findsOneWidget);
      expect(find.textContaining('· vorläufig'), findsOneWidget);
      expect(find.text('Zur Übersichtsansicht zurückkehren'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Zur Übersichtsansicht zurückkehren'));
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
      expect(find.text('6/33 gespielt'), findsNothing);
      expect(find.text('KO: 0/3'), findsOneWidget);
      expect(find.text('Keine KO-Phase als Nächstes geplant.'), findsNothing);
      expect(find.text('Teilnehmer offen'), findsNothing);
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
    await tester.tap(find.text('Vorschau nächste Phase'));
    await tester.pump();

    expect(find.textContaining('A · gesetzt'), findsOneWidget);
    expect(find.textContaining('B · gesetzt'), findsOneWidget);
    expect(find.text('Die Setzplätze der Phase stehen fest.'), findsOneWidget);
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

    expect(find.text('Siegprognose & Weiterkommen'), findsNWidgets(2));
    expect(find.text('73%'), findsAtLeastNWidgets(1));
    expect(find.text('88%'), findsAtLeastNWidgets(1));
    expect(forecastService.calls, 1);
    await tester.tap(find.text('Tabellen & Zwischenstände'));
    await tester.pumpAndSettle();
    expect(find.text('Tabellen & Zwischenstände'), findsAtLeastNWidgets(1));
    expect(find.text('Kombiniert'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forecast tab places two groups side by side on a wide monitor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: _twoGroupPreviewTournament(),
            isStandaloneWindow: true,
            forecastService: _FixedForecastService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Siegprognose & Weiterkommen'));
    await tester.pumpAndSettle();

    final groupA = find.byKey(const ValueKey('second-screen-forecast-group-1'));
    final groupB = find.byKey(const ValueKey('second-screen-forecast-group-2'));
    expect(groupA, findsOneWidget);
    expect(groupB, findsOneWidget);
    expect(
      tester.getTopLeft(groupA).dy,
      closeTo(tester.getTopLeft(groupB).dy, 1),
    );
    expect(tester.getCenter(groupA).dx, lessThan(tester.getCenter(groupB).dx));
    expect(find.text('% Sieg'), findsNWidgets(2));
    expect(find.text('% Weiter'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Christmas forecast tables use translucent cards', (
    tester,
  ) async {
    final styleNotifier = AppThemeController.instance.themeStyleNotifier;
    addTearDown(() => styleNotifier.value = AppThemeStyle.club);
    styleNotifier.value = AppThemeStyle.christmas;
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: _tournament(),
            isStandaloneWindow: true,
            forecastService: _FixedForecastService(),
          ),
        ),
      ),
    );
    // Snowfall animates forever, so pump explicitly instead of settling.
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Siegprognose & Weiterkommen'));
    await tester.pump();
    await tester.pump();

    final table = tester.widget<Container>(
      find.byKey(const ValueKey('second-screen-forecast-group-1')),
    );
    expect(
      (table.decoration! as BoxDecoration).color,
      const Color(0xFF14202B).withValues(alpha: .84),
    );
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
            tournament:
                CreatedTournament(
                    name: 'Widget-Auswahl',
                    players: const [],
                    stages: const [],
                    runStages: const [],
                  )
                  ..secondScreenActiveLayout = 'Ohne Prognose'
                  ..secondScreenLayouts['Ohne Prognose'] = const [
                    SecondScreenWidgetPlacement(widgetId: 'boards'),
                  ],
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
    expect(
      find.descendant(of: picker, matching: find.text('Live Board')),
      findsNothing,
    );
    expect(
      find.descendant(of: picker, matching: find.text('Nächste Phase')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('KO layouts can add a full-width tournament bracket widget', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tournament = _tournament()
      ..activeStageIndex = 1
      ..secondScreenActiveLayout = 'KO-Layout'
      ..secondScreenLayouts['KO-Layout'] = const [
        SecondScreenWidgetPlacement(widgetId: 'boards'),
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
    await tester.pumpAndSettle();
    await tester.tap(find.text('Layout anpassen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Widget hinzufügen'));
    await tester.pumpAndSettle();

    final picker = find.byType(SimpleDialog);
    expect(
      find.descendant(of: picker, matching: find.text('KO-Turnierbaum')),
      findsOneWidget,
    );
    await tester.tap(find.text('KO-Turnierbaum'));
    await tester.pumpAndSettle();

    final bracketWidget = find.byKey(
      const ValueKey('monitor-widget-knockoutBracket'),
    );
    expect(bracketWidget, findsOneWidget);
    expect(
      tester.getSize(bracketWidget).width,
      greaterThan(tester.view.physicalSize.width * 0.9),
    );
    expect(find.byKey(const ValueKey('knockout-match-card-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy layouts hide retired second-screen widgets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tournament = _tournament()
      ..secondScreenActiveLayout = 'Alt'
      ..secondScreenLayouts['Alt'] = const [
        SecondScreenWidgetPlacement(widgetId: 'liveBoard'),
        SecondScreenWidgetPlacement(widgetId: 'nextStagePreview'),
        SecondScreenWidgetPlacement(widgetId: 'standings'),
        SecondScreenWidgetPlacement(widgetId: 'forecast'),
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

    expect(
      find.byKey(const ValueKey('monitor-widget-liveBoard')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('monitor-widget-nextStagePreview')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('monitor-widget-combined')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not show stage progress counts or progress bars', (
    tester,
  ) async {
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

    expect(find.text('3/9 gespielt'), findsNothing);
    expect(find.text('Gesamt'), findsNothing);
    expect(find.text('Fortschritt nach Phasen'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

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

    expect(find.textContaining('Kommt sicher weiter'), findsAtLeastNWidgets(1));
    expect(
      find.textContaining('Scheidet nach aktuellem Stand aus'),
      findsAtLeastNWidgets(1),
    );
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
        matching: find.textContaining('Scheidet nach aktuellem Stand aus'),
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

  testWidgets('next-stage preview can be expanded and returned from', (
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
    final previewButton = find.text('Vorschau nächste Phase');
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
    expect(
      find.text('Zur Übersichtsansicht zurückkehren'),
      findsAtLeastNWidgets(1),
    );
    await tester.tap(find.text('Zur Übersichtsansicht zurückkehren').last);
    await tester.pumpAndSettle();
    expect(find.text('KO · Turnierbaum-Vorschau'), findsOneWidget);
    await tester.tap(find.text('Zur Übersichtsansicht zurückkehren').first);
    await tester.pumpAndSettle();
    expect(find.text('Nächste Partien · Vorschläge'), findsOneWidget);
    expect(find.text('KO · Turnierbaum-Vorschau'), findsNothing);
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
      find.byKey(const ValueKey('monitor-widget-combined')),
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

  testWidgets(
    'top eight tournament counts all 43 scheduled matches from the start',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final players = [
        for (var index = 1; index <= 16; index++)
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
                name: 'Gruppen',
                playType: 'round_robin',
                players: players,
                matches: [
                  for (var index = 0; index < 35; index++)
                    GroupMatch(
                      homePlayer: players[index % players.length],
                      awayPlayer: players[(index + 1) % players.length],
                      round: index + 1,
                    ),
                ],
              ),
            ],
            qualificationPlan: null,
            tieBreakers: const [],
          ),
          KnockoutTournamentRunStage(
            name: 'Top 8',
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
            placementMatches: [
              GroupMatch(
                round: 101,
                placementKey: 'ko/0',
                placementRank: 3,
                label: 'Spiel um Platz 3',
              ),
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

      expect(find.text('0 von 43 Partien abgeschlossen'), findsOneWidget);
      expect(find.text('0 / 35 Partien'), findsOneWidget);
      expect(find.text('0 / 8 Partien'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('recent results height can be increased and fitted to content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final storage = _MemoryTournamentStorage();
    final base = _tournament();
    final group = base.runStages.first as GroupTournamentRunStage;
    final groupPlayers = group.groups.first.players;
    for (var index = 0; index < 6; index++) {
      group.groups.first.matches.add(
        GroupMatch(
          homePlayer: groupPlayers[index % groupPlayers.length],
          awayPlayer: groupPlayers[(index + 1) % groupPlayers.length],
          round: 10 + index,
          homeLegs: 2,
          awayLegs: 0,
        ),
      );
    }
    final tournament = base
      ..secondScreenActiveLayout = 'Standard'
      ..secondScreenLayouts['Standard'] = const [
        SecondScreenWidgetPlacement(
          widgetId: 'recent',
          widthUnits: 2,
          heightUnits: 1,
          columnIndex: 0,
        ),
      ];
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

    final recentTile = find.byKey(const ValueKey('monitor-widget-recent'));
    await tester.tap(
      find.descendant(of: recentTile, matching: find.byTooltip('Höhe erhöhen')),
    );
    await tester.pump();
    await tester.tap(find.text('Layout anwenden'));
    await tester.pump();
    expect(tournament.secondScreenLayouts['Standard']!.first.heightUnits, 1.5);

    await tester.tap(find.text('Layout anpassen'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: recentTile,
        matching: find.byTooltip('Höhe an Inhalt anpassen'),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Layout anwenden'));
    await tester.pump();

    expect(
      tournament.secondScreenLayouts['Standard']!.first.heightUnits,
      greaterThan(1.5),
    );
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

  testWidgets('next-stage preview is a header action only when available', (
    tester,
  ) async {
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
            tournament: singleStageTournament,
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('monitor-next-stage-preview-header-button')),
      findsNothing,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: _tournament(),
            isStandaloneWindow: true,
            storage: _MemoryTournamentStorage(),
          ),
        ),
      ),
    );
    await tester.pump();

    final previewButton = find.byKey(
      const ValueKey('monitor-next-stage-preview-header-button'),
    );
    expect(previewButton, findsOneWidget);
    final previewRect = tester.getRect(previewButton);
    final layoutRect = tester.getRect(find.text('Layout anpassen'));
    expect(previewRect.right, lessThan(layoutRect.left));

    await tester.tap(previewButton);
    await tester.pumpAndSettle();
    expect(find.text('KO · Turnierbaum-Vorschau'), findsOneWidget);
    expect(find.text('Zur Übersichtsansicht zurückkehren'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('widget tiles shrink to content so the next heading sits close', (
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
          heightUnits: 2,
          columnIndex: 0,
        ),
        SecondScreenWidgetPlacement(
          widgetId: 'recent',
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

    final boards = tester.getRect(
      find.byKey(const ValueKey('monitor-widget-boards')),
    );
    final recent = tester.getRect(
      find.byKey(const ValueKey('monitor-widget-recent')),
    );
    expect(recent.top, greaterThan(boards.top));
    expect(recent.top - boards.bottom, lessThan(60));
    final heading = find.text('Zuletzt beendete Matches');
    expect(heading, findsOneWidget);
    expect(tester.getRect(heading).top - recent.top, lessThan(60));
    expect(tester.takeException(), isNull);
  });

  testWidgets('snap height button fits a widget height to its content', (
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

    final boardsSnap = find.descendant(
      of: find.byKey(const ValueKey('monitor-widget-boards')),
      matching: find.byTooltip('Höhe an Inhalt anpassen'),
    );
    expect(boardsSnap, findsOneWidget);
    await tester.tap(boardsSnap);
    await tester.pump();
    await tester.tap(find.text('Layout anwenden'));
    await tester.pump();

    final saved = tournament.secondScreenLayouts['Standard']!;
    final boards = saved.firstWhere(
      (placement) => placement.widgetId == 'boards',
    );
    expect(boards.heightUnits, lessThan(2));
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
      const ValueKey('monitor-widget-drop-target-combined'),
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
      'combined',
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
      const ValueKey('monitor-widget-drop-target-combined'),
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
          .singleWhere((placement) => placement.widgetId == 'combined')
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

    // Der doppelte Format-/Tie-Breaker-Kopf wurde entfernt: nur noch der
    // obere Block bleibt sichtbar.
    expect(find.text('Tabellen & Zwischenstände'), findsOneWidget);
    expect(find.text('Nächste Partien · Vorschläge'), findsOneWidget);
    expect(find.text('Nächste Begegnungen'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('monitor-widget-combined')),
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
      find.byKey(const ValueKey('monitor-widget-combined')),
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
      expect(recent.top, lessThan(progress.bottom));
      expect(progress.top, lessThan(recent.bottom));
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
    expect(
      find.textContaining(RegExp(r'· (vorläufig|gesetzt)')),
      findsNWidgets(16),
    );
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

    expect(
      find.textContaining(RegExp(r'· (vorläufig|gesetzt)')),
      findsNWidgets(8),
    );
    expect(find.text('Gewinner Begegnung 1'), findsOneWidget);
    expect(find.text('Gewinner Begegnung 2'), findsOneWidget);
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
    expect(
      find.text('Top 3 & 2 beste 3. Plätze (größere Gruppe)'),
      findsNWidgets(2),
    );
    expect(find.text('Top 2 weiter'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('standings header shows format and tie breaker help', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
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

    final hint = find.byKey(const ValueKey('standings-format-hint'));
    expect(hint, findsOneWidget);
    final hintText = tester.widget<Text>(hint).data ?? '';
    expect(hintText, contains('Bo3 Legs'));
    expect(hintText, contains('2 weiter'));

    final help = find.byKey(const ValueKey('standings-tie-breaker-help'));
    expect(help, findsOneWidget);
    expect(
      find.byTooltip(
        'Tie-Breaker: Matchpunkte > Leg-Differenz > Gewonnene Legs',
      ),
      findsOneWidget,
    );
    expect(tester.getRect(help).width, 48);
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

  testWidgets(
    'group assignment dialog shows mode and groups and confirm only closes',
    (tester) async {
      final request = SecondScreenGroupAssignmentRequest.create(
        modeLabel: 'Nach Spielstärke gruppieren',
        groups: const [
          SecondScreenAssignmentGroup(name: 'Gruppe A', members: ['A', 'B']),
          SecondScreenAssignmentGroup(name: 'Gruppe B', members: ['C', 'D']),
        ],
      );
      final tournament = _tournament()..secondScreenGroupAssignment = request;
      final before = jsonEncode(request.toJson());

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

      final title = find.byKey(const ValueKey('group-assignment-dialog-title'));
      expect(title, findsOneWidget);
      expect(
        tester.widget<Text>(title).data,
        'Gruppenzuweisung beendet: ausgewählter modus - '
        'Nach Spielstärke gruppieren',
      );
      final dialog = find
          .ancestor(of: title, matching: find.byType(Dialog))
          .first;
      expect(
        find.descendant(of: dialog, matching: find.text('Gruppe A')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('Gruppe B')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('A')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('D')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('group-assignment-dialog-confirm')),
      );
      await tester.pumpAndSettle();
      expect(title, findsNothing);
      expect(jsonEncode(request.toJson()), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tournament info dialog close hides its request', (tester) async {
    final request = SecondScreenTournamentInfoRequest.show();
    final tournament = _tournament()..secondScreenTournamentInfo = request;

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

    final title = find.byKey(const ValueKey('tournament-info-dialog-title'));
    expect(title, findsOneWidget);
    expect(
      find.ancestor(of: title, matching: find.byType(Dialog)),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('tournament-info-dialog-close')),
    );
    await tester.pumpAndSettle();

    expect(title, findsNothing);
    expect(tournament.secondScreenTournamentInfo, isNotNull);
    expect(tournament.secondScreenTournamentInfo!.id, request.id);
    expect(tournament.secondScreenTournamentInfo!.visible, isFalse);
    expect(tester.takeException(), isNull);
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
      TournamentPlayer.generated(index).copyWith(name: 'Teilnehmer $index'),
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
      TournamentPlayer.generated(index).copyWith(name: 'Teilnehmer $index'),
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
    name: 'Drei Gruppen, acht Teilnehmer',
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

CreatedTournament _completedLeagueTournament() {
  final players = [
    TournamentPlayer.generated(1).copyWith(name: 'Lena'),
    TournamentPlayer.generated(2).copyWith(name: 'Lars'),
    TournamentPlayer.generated(3).copyWith(name: 'Mira'),
    TournamentPlayer.generated(4).copyWith(name: 'Mattes'),
  ];
  final league = LeagueMatch.adjusted(
    homeTeam: 'Heimmannschaft',
    awayTeam: 'Gastmannschaft',
    homePlayers: const ['Lena', 'Lars'],
    awayPlayers: const ['Mira', 'Mattes'],
    singlesPerPlayer: 1,
    doublesCount: 0,
    gameFormat: const TournamentGameFormat(bestOfLegs: 3),
  );
  final tournament = CreatedTournament(
    id: 'league-completion',
    name: 'Freundschaftsspiel',
    players: players,
    stages: const [],
    runStages: const [],
    leagueMatch: league,
    boardCount: 2,
    startedAt: DateTime(2026, 11, 17, 10),
  );
  league.games[0].score(2, 0, format: league.gameFormat);
  league.games[1].score(0, 2, format: league.gameFormat);
  final runtime = LeagueBoardRuntime(tournament);
  runtime.matches.first.bestPerformances = const [
    BestPerformance(type: BestPerformanceType.score180, playerName: 'Lena'),
  ];
  runtime.writeTo(tournament);
  return tournament
    ..finishedAt = DateTime(2026, 11, 17, 12)
    ..updatedAt = DateTime(2026, 11, 17, 12);
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
          tournamentWinProbability: 73,
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
  Future<List<CreatedTournament>> loadTournamentsForRanking(
    String rankingId, {
    DateTime? from,
    DateTime? through,
  }) async => [
    for (final tournament in tournaments)
      if (tournament.rankingIds.contains(rankingId)) tournament,
  ];

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
