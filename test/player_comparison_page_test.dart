import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/statistics/presentation/player_comparison_page.dart';
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
}

class _FakeTournamentStorage extends TournamentStorage {
  @override
  Future<List<CreatedTournament>> loadTournaments() async => const [];
}

void main() {
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
        if (find.textContaining('Spielervergleich').evaluate().isNotEmpty) {
          break;
        }
      }

      expect(find.text('Spieler vergleichen'), findsOneWidget);
      expect(find.text('Spieler Links'), findsOneWidget);
      expect(find.text('Spieler Rechts'), findsOneWidget);
      expect(find.textContaining('Spielervergleich'), findsOneWidget);
      expect(find.text('Kategorie'), findsOneWidget);
      expect(find.text('Spiele'), findsOneWidget);
      expect(find.text('Legquote'), findsOneWidget);
      expect(find.textContaining('Elo-Verlauf'), findsNothing);
      final comparisonTable = tester.widget<DataTable>(find.byType(DataTable));
      expect(comparisonTable.border?.verticalInside, isNotNull);
      expect(
        tester.widget<Text>(find.text('Spiele')).textAlign,
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
}
