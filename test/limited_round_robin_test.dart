import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
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
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('limited schedules maximize games and balance players, repetitions and rounds', () {
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
  });
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
      expect(jsonDecode(await file.readAsString())['schemaVersion'], 28);
      expect(
        TournamentStage.fromJson({'name': 'Alt', 'type': 'groups'})
            .maxGamesForGroup(0),
        isNull,
      );
    },
  );
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
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const LimitedGroupSetupPreview(),
        ),
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      expect(find.text('5 Spiele'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4 Spiele').last);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpAndSettle();
      expect(find.text('4 Spiele'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
