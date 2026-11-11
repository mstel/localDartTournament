import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/pages/challonge_archive_page.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/pages/tournament_results_page.dart';
import 'package:dart_tournament_manager/features/challonge/application/challonge_native_import.dart';
import 'package:dart_tournament_manager/features/challonge/domain/challonge_tournament.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show ProductionTournamentRuntime;

Map<String, dynamic> fixture(
  String mode,
  List<List<int>> games, {
  List<int> ranks = const [1, 2],
}) => {
  'id': 901,
  'name': 'Native Prüfung',
  'state': 'complete',
  'tournament_type': mode,
  'created_at': '2020-01-01T12:00:00Z',
  'completed_at': '2020-01-01T18:00:00Z',
  'participants': [
    for (var i = 0; i < ranks.length; i++)
      {'id': i + 1, 'name': 'Teilnehmer ${i + 1}', 'final_rank': ranks[i]},
  ],
  'matches': [
    for (final e in games.indexed)
      {
        'id': e.$1 + 1,
        'state': 'complete',
        'round': e.$2[0],
        'player1_id': e.$2[1],
        'player2_id': e.$2[2],
        'scores_csv': '${e.$2[3]}-${e.$2[4]}',
        'winner_id': e.$2[3] == e.$2[4]
            ? null
            : e.$2[e.$2[3] > e.$2[4] ? 1 : 2],
      },
  ],
};
CreatedTournament native(Map<String, dynamic> data) {
  final source = ChallongeTournament(data);
  return ChallongeNativeImport.convert(
    source.convert({
      for (final p in source.participants) '${p['id']}': 'p${p['id']}',
    }),
  );
}

class ChallongeNativeComparisonPreview extends StatelessWidget {
  const ChallongeNativeComparisonPreview({super.key});
  @override
  Widget build(BuildContext context) => ChallongeArchivePage(
    tournament: native(
      fixture(
        'round robin',
        [
          [1, 1, 2, 3, 0],
          [2, 1, 3, 3, 1],
          [3, 2, 3, 3, 2],
        ],
        ranks: [2, 1, 3],
      ),
    ),
  );
}

void main() {
  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('native results and comparison at $size with large text', (
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
          home: TournamentResultsPage(
            tournament: native(
              fixture('single elimination', [
                [1, 1, 2, 3, 1],
              ]),
            ),
            database: _EmptyRankingDatabase(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Turnierergebnisse'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Mit Challonge vergleichen'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Prüfung mit eigener Turnierlogik'),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Prüfung mit eigener Turnierlogik'), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  test('round robin calculates standings and exposes source discrepancies', () {
    final result = native(
      fixture(
        'round robin',
        [
          [1, 1, 2, 3, 0],
          [2, 1, 3, 3, 1],
          [3, 2, 3, 3, 2],
        ],
        ranks: [2, 1, 3],
      ),
    );
    expect(result.runStages.single, isA<GroupTournamentRunStage>());
    expect(result.importedArchive!.nativeValidation!['status'], 'differences');
    expect(result.importedArchive!.nativeValidation!['issues'], hasLength(2));
  });
  test('Swiss historical rounds remain native and accept draws', () {
    final result = native(
      fixture(
        'swiss',
        [
          [1, 1, 2, 2, 2],
        ],
        ranks: [1, 1],
      ),
    );
    final group =
        (result.runStages.single as GroupTournamentRunStage).groups.single;
    expect(group.playType, 'swiss');
    expect(group.matches.single.hasResult, isTrue);
    expect(group.matches.single.winner, isNull);
  });
  test(
    'double elimination replays grand final and reset using production runtime',
    () {
      final result = native(
        fixture('double elimination', [
          [1, 1, 2, 3, 0],
          [2, 1, 2, 1, 3],
          [3, 1, 2, 3, 2],
        ]),
      );
      final ko = result.runStages.single as KnockoutTournamentRunStage;
      expect(ko.eliminationLossLimit, 2);
      expect(
        ko.rounds.expand((r) => r).where((m) => m.hasResult),
        hasLength(3),
      );
      expect(result.importedArchive!.nativeValidation!['issues'], isEmpty);
    },
  );
  test(
    'double elimination imports the complete eight-player bracket from tournament 25',
    () {
      const names = [
        'Tobi_B',
        'David',
        'Marvin_S',
        'Jan_Wa',
        'Timo_S',
        'Andre_Wi',
        'Max_Re',
        'Markus_D',
      ];
      const games = [
        [1, 1, 2, 2, 0],
        [1, 3, 4, 1, 2],
        [1, 5, 6, 2, 0],
        [1, 7, 8, 2, 0],
        [2, 1, 4, 0, 2],
        [2, 5, 7, 1, 2],
        [3, 4, 7, 0, 2],
        [4, 7, 5, 2, 0],
        [-1, 2, 3, 2, 1],
        [-1, 6, 8, 2, 1],
        [-2, 5, 2, 2, 1],
        [-2, 1, 6, 2, 1],
        [-3, 5, 1, 2, 1],
        [-4, 4, 5, 0, 1],
      ];
      final data =
          fixture('double elimination', games, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
            ..['participants'] = [
              for (var i = 0; i < names.length; i++)
                {'id': i + 1, 'name': names[i], 'final_rank': i + 1},
            ];

      final result = native(data);
      final bracket = result.runStages.single as KnockoutTournamentRunStage;

      expect(
        bracket.rounds.expand((round) => round).where((m) => m.hasResult),
        hasLength(14),
      );
      expect(bracket.eliminationLossLimit, 2);
      expect(
        bracket.rounds
            .expand((round) => round)
            .singleWhere(
              (m) =>
                  m.homePlayer?.name == 'Max_Re' &&
                  m.awayPlayer?.name == 'Timo_S',
            )
            .winner
            ?.name,
        'Max_Re',
      );
      expect(result.importedArchive!.nativeValidation!['checkedMatches'], 14);

      final restored = CreatedTournament.fromJson(result.toJson());
      final runtime = ProductionTournamentRuntime(restored)..advance();
      final restoredBracket =
          restored.runStages.single as KnockoutTournamentRunStage;
      expect(
        runtime.matches(restoredBracket).where((match) => match.hasResult),
        hasLength(14),
      );
    },
  );
}

class _EmptyRankingDatabase extends LocalAppDatabase {
  @override
  Future<List<LocalRanking>> loadLocalRankings() async => const [];
}
