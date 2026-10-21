import 'dart:io';

import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/rankings/application/tournament_match_elo_service.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/pages/tournament_results_page.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/results/tournament_ranking_assignment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late _RankingDatabase rankingDatabase;
  late _ImmediateTournamentStorage immediateStorage;
  late TournamentStorage storage;
  late CreatedTournament tournament;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'tournament_results_parity_',
    );
    storage = TournamentStorage(
      file: File('${directory.path}${Platform.pathSeparator}tournaments.json'),
    );
    immediateStorage = _ImmediateTournamentStorage();
    const first = TournamentPlayer(
      profileId: 'profile-first',
      name: 'Erste Person',
      isGenerated: false,
    );
    const second = TournamentPlayer(
      profileId: 'profile-second',
      name: 'Zweite Person',
      isGenerated: false,
    );
    tournament = CreatedTournament(
      id: 'finished-tournament',
      name: 'Abgeschlossenes Turnier',
      players: const [first, second],
      stages: const [],
      runStages: [
        KnockoutTournamentRunStage(
          name: 'Finale',
          rounds: [
            [
              GroupMatch(
                homePlayer: first,
                awayPlayer: second,
                round: 1,
                homeLegs: 3,
                awayLegs: 1,
              ),
            ],
          ],
        ),
      ],
      completedStageIndexes: {0},
      finishedAt: DateTime.utc(2026, 1, 1),
      countsForRanking: false,
    );
    await storage.saveTournament(tournament);
    rankingDatabase = _RankingDatabase(
      baseDirectory: Directory(
        '${directory.path}${Platform.pathSeparator}test-db',
      ),
      rankings: const [
        LocalRanking(id: 'ranking-2026', name: 'Vereinsrangliste 2026'),
      ],
    );
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  testWidgets('results show explicit persisted ranking assignment only', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TournamentResultsPage(
          tournament: tournament,
          database: rankingDatabase,
          storage: storage,
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byType(TournamentRankingAssignment),
      500,
    );
    await tester.pumpAndSettle();

    final completionCard = tester.widget<Card>(
      find.ancestor(
        of: find.text('Turnier abgeschlossen'),
        matching: find.byType(Card),
      ),
    );
    final completionGradient = completionCard.child! as Container;
    expect(completionGradient.decoration, isA<BoxDecoration>());
    expect(
      (completionGradient.decoration! as BoxDecoration).gradient,
      isA<LinearGradient>(),
    );
    expect(find.byIcon(Icons.emoji_events), findsNothing);

    expect(find.text('Ranglisten-Zuweisung'), findsOneWidget);
    expect(find.text('Gesamtwertung'), findsNothing);
    expect(find.text('Turnierstatistik'), findsNothing);
    expect(find.text('Spielerstatistiken'), findsNothing);
    expect(find.text('Vereinsrangliste 2026'), findsOneWidget);
    final scrollable = find.byType(Scrollable).first;
    final assignmentScrollOffset = tester
        .state<ScrollableState>(scrollable)
        .position
        .pixels;
    final exportButton = find.text('Turnier exportieren');
    await tester.scrollUntilVisible(exportButton, 500, scrollable: scrollable);
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      greaterThan(assignmentScrollOffset),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ranking assignment is not applied until saved and survives reload',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TournamentRankingAssignment(
              tournament: tournament,
              database: rankingDatabase,
              storage: immediateStorage,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rankingCheckbox = find.byType(CheckboxListTile);
      expect(rankingCheckbox, findsOneWidget);
      await tester.tap(rankingCheckbox);
      await tester.pumpAndSettle();

      expect(tournament.countsForRanking, isFalse);
      expect(tournament.rankingIds, isEmpty);

      await tester.tap(find.text('Zuweisung speichern'));
      await tester.pumpAndSettle();

      expect(tournament.countsForRanking, isTrue);
      expect(tournament.rankingIds, ['ranking-2026']);
      expect(immediateStorage.lastSaved?.countsForRanking, isTrue);
      expect(immediateStorage.lastSaved?.rankingIds, ['ranking-2026']);
      expect(tester.takeException(), isNull);
    },
  );

  test('explicit assignment roundtrips through tournament storage', () async {
    tournament
      ..countsForRanking = true
      ..rankingIds = ['ranking-2026'];

    await storage.saveTournament(tournament);

    final reloaded = (await storage.loadTournaments()).single;
    expect(reloaded.countsForRanking, isTrue);
    expect(reloaded.rankingIds, ['ranking-2026']);
  });

  test(
    'live Elo changes include only assigned rankings and clear on removal',
    () async {
      tournament
        ..countsForRanking = true
        ..rankingIds = ['ranking-2026', 'ranking-2025'];
      await storage.saveTournament(tournament);

      final database = _RankingDatabase(
        baseDirectory: Directory(
          '${directory.path}${Platform.pathSeparator}elo-db',
        ),
        rankings: const [
          LocalRanking(id: 'ranking-2026', name: 'Rangliste 2026'),
          LocalRanking(id: 'ranking-2025', name: 'Rangliste 2025'),
          LocalRanking(id: 'unassigned', name: 'Nicht zugewiesen'),
        ],
        playerIds: const ['profile-first', 'profile-second'],
        profiles: [
          for (final player in tournament.players)
            PlayerProfile(
              id: player.profileId!,
              displayName: player.name,
              country: '',
              city: '',
              dartsSetupJson: '',
              createdAt: DateTime.utc(2020),
              isActive: true,
            ),
        ],
      );
      final service = TournamentMatchEloService(
        database: database,
        tournamentStorage: storage,
      );

      var changes = await service.calculate(tournament);
      expect(changes, hasLength(1));
      expect(
        changes.values.single.map((change) => change.rankingName).toSet(),
        {'Rangliste 2026', 'Rangliste 2025'},
      );

      tournament.rankingIds.remove('ranking-2025');
      await storage.saveTournament(tournament);
      changes = await service.calculate(tournament);
      expect(changes.values.single.map((change) => change.rankingName), [
        'Rangliste 2026',
      ]);

      tournament.countsForRanking = false;
      expect(await service.calculate(tournament), isEmpty);
    },
  );
}

class _RankingDatabase extends LocalAppDatabase {
  _RankingDatabase({
    required super.baseDirectory,
    required this.rankings,
    this.playerIds = const [],
    this.profiles = const [],
  });

  final List<LocalRanking> rankings;
  final List<String> playerIds;
  final List<PlayerProfile> profiles;

  @override
  Future<List<LocalRanking>> loadLocalRankings() async => rankings;

  @override
  Future<List<String>> loadRankingPlayerIds(String rankingId) async =>
      playerIds;

  @override
  Future<List<PlayerProfile>> loadPlayerProfiles() async => profiles;
}

class _ImmediateTournamentStorage extends TournamentStorage {
  CreatedTournament? lastSaved;

  @override
  Future<void> saveTournament(CreatedTournament tournament) async {
    lastSaved = tournament;
  }
}
