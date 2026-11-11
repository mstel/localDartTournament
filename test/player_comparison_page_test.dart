import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/statistics/domain/monthly_player_performance.dart';
import 'package:dart_tournament_manager/features/statistics/presentation/player_comparison_page.dart';
import 'package:dart_tournament_manager/features/statistics/domain/player_monthly_performance.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDatabase extends LocalAppDatabase {
  static final profiles = [
    for (final (id, name) in [('left', 'Anna Lang'), ('right', 'Ben Kurz')])
      PlayerProfile(
        id: id,
        displayName: name,
        country: '',
        city: '',
        dartsSetupJson: '',
        createdAt: DateTime.utc(2026),
        isActive: true,
      ),
  ];

  @override
  Future<List<PlayerProfile>> loadPlayerProfiles() async => profiles;

  @override
  Future<List<LocalRanking>> loadLocalRankings() async => const [
    LocalRanking(id: 'elo', name: 'Vereinswertung'),
  ];

  @override
  Future<List<String>> loadRankingPlayerIds(String rankingId) async => [
    'left',
    'right',
  ];

  @override
  Future<List<MonthlyPlayerPerformance>> loadMonthlyPlayerPerformances(
    Set<String> playerProfileIds, {
    int? year,
  }) async => const [];

  @override
  Future<List<PlayerMonthlyPerformance>> loadPlayerMonthlyPerformance(
    String playerId, {
    int? year,
  }) async => const [];
}

class _AchievementFakeDatabase extends _FakeDatabase {
  @override
  Future<List<LocalRanking>> loadLocalRankings() async => const [
    LocalRanking(
      id: 'elo-achievements',
      name: 'Saisonwertung',
      achievementsEnabled: true,
    ),
  ];

  @override
  Future<Map<String, Map<String, Object?>>> loadRankingAchievementProgress(
    String rankingId,
    String playerProfileId,
  ) async => {
    'first_tournament_win': {
      'achievement_id': 'first_tournament_win',
      'current_value': playerProfileId == 'left' ? 1 : 0,
      'target_value': 1,
      'status': playerProfileId == 'left' ? 'completed' : 'locked',
      'unlocked_at': playerProfileId == 'left'
          ? '2026-01-01T00:00:00.000Z'
          : null,
    },
  };
}

class _FakeTournamentStorage extends TournamentStorage {
  _FakeTournamentStorage([this.tournaments = const []]);

  final List<CreatedTournament> tournaments;

  @override
  Future<List<CreatedTournament>> loadTournaments() async => tournaments;
}

void main() {
  testWidgets('month filter limits all comparison match categories', (
    tester,
  ) async {
    final tournaments = [
      _playedTournament('Jan', DateTime(2026, 1, 12), 3, 1),
      _playedTournament('Feb', DateTime(2026, 2, 12), 3, 0),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerComparisonPage(
          database: _FakeDatabase(),
          tournamentStorage: _FakeTournamentStorage(tournaments),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('player-comparison-year')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('player-comparison-left-Begegnungen')),
          )
          .data,
      '2',
    );

    await tester.tap(find.byKey(const ValueKey('player-comparison-month')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Januar').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Im ausgewählten Zeitraum keine direkten Begegnungen.'),
      findsNothing,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('player-comparison-left-Begegnungen')),
          )
          .data,
      '1',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('player-comparison-right-Begegnungen')),
          )
          .data,
      '1',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('player comparison stays usable at compact and wide sizes', (
    tester,
  ) async {
    final database = _FakeDatabase();
    final storage = _FakeTournamentStorage();

    for (final size in [
      const Size(360, 800),
      const Size(800, 600),
      const Size(1440, 900),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: const TextScaler.linear(2),
          ),
          child: MaterialApp(
            home: PlayerComparisonPage(
              database: database,
              tournamentStorage: storage,
            ),
          ),
        ),
      );
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.textContaining('Teilnehmervergleich').evaluate().isNotEmpty) {
          break;
        }
      }

      expect(find.text('Teilnehmer vergleichen'), findsOneWidget);
      expect(find.text('Teilnehmer Links'), findsOneWidget);
      expect(find.text('Teilnehmer Rechts'), findsOneWidget);
      expect(find.textContaining('Teilnehmervergleich'), findsOneWidget);
      expect(find.text('Kategorie'), findsOneWidget);
      expect(find.text('Begegnungen'), findsOneWidget);
      expect(find.text('Legquote'), findsOneWidget);
      expect(find.text('Direkte Begegnungen'), findsOneWidget);
      expect(
        find.text('Im ausgewählten Zeitraum keine direkten Begegnungen.'),
        findsOneWidget,
      );
      expect(find.textContaining('Elo-Verlauf'), findsNothing);
      final comparisonTable = tester.widget<DataTable>(find.byType(DataTable));
      expect(comparisonTable.border?.verticalInside, isNotNull);
      expect(
        tester.widget<Text>(find.text('Begegnungen')).textAlign,
        TextAlign.center,
      );
      final left = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('player-comparison-Links')),
      );
      final right = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('player-comparison-Rechts')),
      );
      expect(left.initialValue, isNot(right.initialValue));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('achievement comparison is grouped by enabled ranking', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerComparisonPage(
          database: _AchievementFakeDatabase(),
          tournamentStorage: _FakeTournamentStorage(),
        ),
      ),
    );
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Errungenschaften-Vergleich').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text('Errungenschaften-Vergleich'), findsOneWidget);
    expect(find.text('Saisonwertung'), findsOneWidget);
    expect(find.text('Anna Lang'), findsAtLeastNWidgets(2));
    expect(find.text('Ben Kurz'), findsAtLeastNWidgets(2));
    expect(find.textContaining('freigeschaltet'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

CreatedTournament _playedTournament(
  String name,
  DateTime finishedAt,
  int homeLegs,
  int awayLegs,
) {
  final left = TournamentPlayer(
    profileId: 'left',
    name: 'Anna Lang',
    isGenerated: false,
  );
  final right = TournamentPlayer(
    profileId: 'right',
    name: 'Ben Kurz',
    isGenerated: false,
  );
  return CreatedTournament(
    name: name,
    players: [left, right],
    stages: const [TournamentStage(name: 'Gruppenphase', type: 'groups')],
    runStages: [
      GroupTournamentRunStage(
        name: 'Gruppenphase',
        groupPlayType: 'round_robin',
        groups: [
          TournamentGroup(
            name: 'Gruppe A',
            playType: 'round_robin',
            players: [left, right],
            matches: [
              GroupMatch(
                homePlayer: left,
                awayPlayer: right,
                round: 1,
                homeLegs: homeLegs,
                awayLegs: awayLegs,
              ),
            ],
          ),
        ],
        qualificationPlan: null,
        tieBreakers: const [],
      ),
    ],
  )..finishedAt = finishedAt;
}
