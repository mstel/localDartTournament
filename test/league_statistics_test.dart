import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/league/domain/league_match.dart';
import 'package:dart_tournament_manager/features/league/domain/league_player_record.dart';
import 'package:dart_tournament_manager/features/league/presentation/league_match_page.dart';
import 'package:dart_tournament_manager/features/statistics/domain/tournament_player_statistics.dart';
import 'package:dart_tournament_manager/features/statistics/domain/statistics_period.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

CreatedTournament fixture() => CreatedTournament(
  id: 'league',
  name: 'Liga',
  createdAt: DateTime(2026, 10, 2),
  players: [],
  stages: [],
  runStages: [],
  leagueMatch: LeagueMatch.rhl(
    homeTeam: 'Heim',
    awayTeam: 'Gast',
    homePlayers: [
      'Alex',
      'Ein sehr langer Name des zweiten Doppelpartners',
      'C',
      'D',
    ],
    awayPlayers: ['Alex', 'B', 'C', 'D'],
  ),
);

void main() {
  const calculator = TournamentStatisticsCalculator();
  test('doubles count for each partner without merging equal names', () {
    final tournament = fixture();
    tournament.leagueMatch!.games[16].score(3, 1);
    final rows = calculator.calculate([tournament, tournament]);
    expect(rows.length, 4);
    expect(rows.where((r) => r.name == 'Alex').length, 2);
    expect(rows.where((r) => r.wins == 1).length, 2);
    expect(rows.where((r) => r.losses == 1).length, 2);
    for (final row in rows) {
      expect(row.matches, 1);
      expect(row.legsFor, row.wins == 1 ? 3 : 1);
      expect(row.legsAgainst, row.wins == 1 ? 1 : 3);
    }
  });
  test('league player records count doubles once per partner', () {
    final league = LeagueMatch.adjusted(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: const ['H1', 'H2'],
      awayPlayers: const ['G1', 'G2'],
      singlesPerPlayer: 1,
      doublesCount: 1,
      gameFormat: const TournamentGameFormat(bestOfLegs: 3),
    );
    for (final game in league.games) {
      game.score(2, 0, format: league.gameFormat);
    }

    final records = leaguePlayerRecords(league);

    expect(records, hasLength(4));
    for (final record in records.where((item) => item.teamSide == 0)) {
      expect(record.matches, 2);
      expect(record.wins, 2);
      expect(record.losses, 0);
    }
    for (final record in records.where((item) => item.teamSide == 1)) {
      expect(record.matches, 2);
      expect(record.wins, 0);
      expect(record.losses, 2);
    }
  });
  test(
    'singles, corrections, clearing and persisted results are recomputed',
    () {
      final tournament = fixture();
      final league = tournament.leagueMatch!;
      league.games[0].score(3, 0);
      league.games[16].score(3, 1);
      var row = calculator
          .calculate([CreatedTournament.fromJson(tournament.toJson())])
          .firstWhere((r) => r.id == 'league:league:0:0');
      expect(row.matches, 2);
      expect(row.wins, 2);
      expect(row.matches, 2);
      expect(row.legsFor, 6);
      league.games[16].score(1, 3);
      row = calculator
          .calculate([tournament])
          .firstWhere((r) => r.id == 'league:league:0:0');
      expect(row.wins, 1);
      expect(row.losses, 1);
      league.games[16].score(null, null);
      expect(
        calculator.calculate([tournament]).every((r) => r.matches == 1),
        isTrue,
      );
      expect(
        calculator.calculate([
          tournament,
        ], period: StatisticsPeriod(DateTime(2026, 9), DateTime(2026, 9, 30))),
        isEmpty,
      );
    },
  );
  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('league statistics accessible at $size with large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tournament = fixture();
      tournament.leagueMatch!.games[16].score(3, 1);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: LeagueMatchPage(tournament: tournament),
        ),
      );
      await tester.scrollUntilVisible(find.text('Statistik'), 150, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Statistik'));
      await tester.pumpAndSettle();
      expect(find.text('Ligastatistik'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Alex').hitTestable(), 150);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -350));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
