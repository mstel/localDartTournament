import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/engines/limited_round_robin_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/engines/tournament_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show ProductionTournamentRuntime;
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/creation/group_game_limit_setup.dart';

class LimitedGroupSetupPreview extends StatefulWidget {
  const LimitedGroupSetupPreview({super.key, this.initialLimit});
  final int? initialLimit;
  @override
  State<LimitedGroupSetupPreview> createState() =>
      _LimitedGroupSetupPreviewState();
}

class _LimitedGroupSetupPreviewState extends State<LimitedGroupSetupPreview> {
  int? limit;
  String strategy = 'elo';
  @override
  void initState() {
    super.initState();
    limit = widget.initialLimit;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GroupGameLimitSetup(
            groupSizes: const [13],
            playTypes: const ['round_robin'],
            repeats: const [1],
            limits: [limit],
            onChanged: (_, value) => setState(() => limit = value),
            strategies: [strategy],
            onStrategyChanged: (_, value) =>
                setState(() => strategy = value),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test(
    'limited schedules maximize games and balance players, repetitions and rounds',
    () {
      for (var n = 2; n <= 25; n++) {
        final players = [
          for (var i = 0; i < n; i++) TournamentPlayer.generated(i + 1),
        ];
        for (final repeats in [1, 2, 3]) {
          for (var cap = 1; cap <= (n - 1) * repeats + 2; cap++) {
            final matches = tournamentEngine.buildRoundRobinMatches(
              players,
              repeatCount: repeats,
              maxGamesPerPlayer: cap,
            );
            final available = (n - 1) * repeats;
            final effective = cap < available ? cap : available;
            expect(
              matches.length,
              n * effective ~/ 2,
              reason: '$n/$repeats/$cap',
            );
            expect(
              tournamentEngine.roundRobinMatchCount(
                n,
                repeats,
                maxGamesPerPlayer: cap,
              ),
              matches.length,
            );
            final counts = [
              for (final p in players)
                matches
                    .where((m) => m.homePlayer == p || m.awayPlayer == p)
                    .length,
            ]..sort();
            expect(counts.last, lessThanOrEqualTo(cap));
            expect(counts.last - counts.first, lessThanOrEqualTo(1));
            final pairs = <String, int>{};
            for (final m in matches) {
              expect(m.homePlayer, isNot(m.awayPlayer));
              final key = ([
                m.homePlayer!.name,
                m.awayPlayer!.name,
              ]..sort()).join('/');
              pairs[key] = (pairs[key] ?? 0) + 1;
            }
            expect(pairs.values.every((count) => count <= repeats), isTrue);
            for (final round in matches.map((m) => m.round).toSet()) {
              final playing = matches
                  .where((m) => m.round == round)
                  .expand((m) => [m.homePlayer, m.awayPlayer])
                  .toList();
              expect(playing.toSet().length, playing.length);
            }
          }
        }
      }
    },
  );
  test(
    'production group builder and legacy storage migration preserve cap',
    () async {
      final setup = TournamentStage(
        name: 'Begrenzt',
        type: 'groups',
        groupCount: 1,
        groupSizes: const [13],
        groupMaxGamesPerPlayer: const [5],
      );
      final tournament = CreatedTournament(
        id: 'limited',
        name: 'Begrenzt',
        players: [for (var i = 1; i <= 13; i++) TournamentPlayer.generated(i)],
        stages: [setup],
        runStages: [],
        createdAt: DateTime(2026),
      );
      final runtime = ProductionTournamentRuntime(tournament);
      tournament.runStages.add(runtime.build(setup, tournament.players));
      final group = (tournament.runStages.single as GroupTournamentRunStage)
          .groups
          .single;
      expect(group.matches, hasLength(32));
      final dir = await Directory.systemTemp.createTemp('limited-group-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/tournaments.json');
      await file.writeAsString(
        jsonEncode({'schemaVersion': 21, 'tournaments': []}),
      );
      final storage = TournamentStorage(file: file);
      await storage.saveTournament(tournament);
      expect(
        (await storage.loadTournaments())
            .single
            .stages
            .single
            .groupMaxGamesPerPlayer,
        [5],
      );
      expect(await File('${file.path}.v21.bak').exists(), isTrue);
      expect(jsonDecode(await file.readAsString())['schemaVersion'], 46);
      expect(
        TournamentStage.fromJson({
          'name': 'Alt',
          'type': 'groups',
        }).maxGamesForGroup(0),
        isNull,
      );
    },
  );
  test('limited round robin strategies create distinct deterministic schedules', () {
    final players = [
      for (var index = 1; index <= 8; index++)
        TournamentPlayer(
          profileId: 'p$index',
          name: 'P$index',
          isGenerated: true,
        ),
    ];
    final ratings = {
      for (var index = 1; index <= 8; index++) 'p$index': 2000 - index * 100,
    };
    List<String> pairsFor(String strategy, {int? seed}) {
      final matches = LimitedRoundRobinEngine.build(
        players,
        maxGamesPerPlayer: 3,
        matchmakingStrategy: strategy,
        ratings: ratings,
        seed: seed,
      );
      return matches
          .map(
            (match) =>
                ([match.homePlayer!.profileId!, match.awayPlayer!.profileId!]
                      ..sort())
                    .join('/'),
          )
          .toList()
        ..sort();
    }

    expect(limitedRoundRobinMatchmakingLabel('elo'), 'Nach Elo');
    expect(limitedRoundRobinMatchmakingLabel('random'), 'Zufällig');
    expect(limitedRoundRobinMatchmakingLabel('similar'), 'Etwa gleichstarke Gegner');
    expect(
      limitedRoundRobinMatchmakingLabel('mixed'),
      'Ausgewogene Mischung aus starken und schwachen Gegnern',
    );

    final elo = pairsFor('elo');
    final similar = pairsFor('similar');
    final mixed = pairsFor('mixed');
    final random = pairsFor('random', seed: 7);
    expect(random, pairsFor('random', seed: 7));
    expect({elo.join(','), similar.join(','), mixed.join(','), random.join(',')}.length, 4);

    final mixedMatches = LimitedRoundRobinEngine.build(
      players,
      maxGamesPerPlayer: 3,
      matchmakingStrategy: 'mixed',
      ratings: ratings,
    );
    expect(mixedMatches.first.homePlayer!.profileId, 'p1');
    expect(mixedMatches.first.awayPlayer!.profileId, 'p8');
  });

  test('stage JSON persists matchmaking strategies and ratings', () {
    final stage = TournamentStage(
      name: 'Gruppen',
      type: 'groups',
      groupSizes: const [4, 4],
      groupMaxGamesPerPlayer: const [3, 3],
      groupMatchmakingStrategies: const ['random', 'mixed'],
      groupMatchmakingRatings: const {'p1': 1700, 'p2': 1500},
    );
    final restored = TournamentStage.fromJson(stage.toJson());
    expect(restored.groupMatchmakingStrategies, ['random', 'mixed']);
    expect(restored.groupMatchmakingRatings, {'p1': 1700, 'p2': 1500});
    expect(restored.matchmakingStrategyForGroup(0), 'random');
    expect(restored.matchmakingStrategyForGroup(1), 'mixed');
    expect(
      TournamentStage.fromJson({'name': 'Alt', 'type': 'groups'})
          .groupMatchmakingRatings,
      isEmpty,
    );
  });

  testWidgets('matchmaking strategy can be selected for limited groups', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: LimitedGroupSetupPreview()),
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final dropdown = find.byKey(const ValueKey('group-matchmaking-strategy-1'));
    expect(dropdown, findsOneWidget);
    expect(find.text('Nach Elo'), findsOneWidget);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zufällig').last);
    await tester.pumpAndSettle();
    expect(find.text('Zufällig'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('game cap selection survives resize at $size with large text', (
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
          home: const LimitedGroupSetupPreview(),
        ),
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      expect(find.text('5 Begegnungen'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4 Begegnungen').last);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpAndSettle();
      expect(find.text('4 Begegnungen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
