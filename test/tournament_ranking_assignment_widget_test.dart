import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/results/tournament_ranking_assignment_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('normal tournament assignment fits $size with large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _assignRanking(tester);
    });
  }
}

Future<void> _assignRanking(WidgetTester tester) async {
  final database = _FakeRankingDatabase();
  final storage = _FakeTournamentStorage();
  final tournament = CreatedTournament(
    id: 'normal-cup',
    name: 'Normal Cup',
    players: const [],
    stages: const [],
    runStages: const [],
    countsForRanking: false,
  );

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: TournamentRankingAssignmentSection(
            tournament: tournament,
            database: database,
            storage: storage,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Rangliste zuweisen'), findsOneWidget);
  await tester.ensureVisible(find.text('Rangliste zuweisen'));
  await tester.tap(find.text('Rangliste zuweisen'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Club Elo'));
  await tester.pump();
  await tester.tap(find.text('Zuweisen'));
  await tester.pumpAndSettle();

  expect(tournament.countsForRanking, isTrue);
  expect(tournament.rankingIds, ['club-elo']);
  expect(storage.savedCountsForRanking, isTrue);
  expect(storage.savedRankingIds, ['club-elo']);
  expect(tester.takeException(), isNull);
}

class _FakeRankingDatabase extends LocalAppDatabase {
  @override
  Future<List<LocalRanking>> loadLocalRankings() async => const [
    LocalRanking(id: 'club-elo', name: 'Club Elo'),
  ];
}

class _FakeTournamentStorage extends TournamentStorage {
  bool? savedCountsForRanking;
  List<String> savedRankingIds = const [];

  @override
  Future<void> saveTournament(CreatedTournament tournament) async {
    savedCountsForRanking = tournament.countsForRanking;
    savedRankingIds = List<String>.from(tournament.rankingIds);
  }
}
