import '../../tournaments/data/app_database.dart';
import '../../tournaments/data/tournament_storage.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../domain/elo_tier.dart';
import '../domain/local_ranking.dart';
import 'local_ranking_elo_service.dart';

class TournamentRankingPlayerChange {
  const TournamentRankingPlayerChange({
    required this.playerProfileId,
    required this.playerName,
    required this.delta,
    required this.ratingBefore,
    required this.ratingAfter,
    required this.tierBefore,
    required this.tierAfter,
    required this.enableTiers,
    required this.rankingName,
  });

  final String playerProfileId;
  final String playerName;
  final int delta;
  final int ratingBefore;
  final int ratingAfter;
  final EloTier tierBefore;
  final EloTier tierAfter;
  final bool enableTiers;
  final String rankingName;

  bool get hasTierChange => enableTiers && tierBefore != tierAfter;
  bool get isPromotion => hasTierChange && ratingAfter > ratingBefore;

  Map<String, Object?> toExportJson() => {
    'rankingName': rankingName,
    'playerName': playerName,
    'delta': delta,
    'ratingBefore': ratingBefore,
    'ratingAfter': ratingAfter,
    'tierChange': hasTierChange,
    if (hasTierChange) 'tierBefore': tierBefore.name,
    if (hasTierChange) 'tierAfter': tierAfter.name,
  };
}

class TournamentRankingChangesService {
  TournamentRankingChangesService({
    LocalAppDatabase? database,
    TournamentStorage? storage,
  }) : _database = database ?? LocalAppDatabase(),
       _storage = storage;

  final LocalAppDatabase _database;
  final TournamentStorage? _storage;

  Future<List<TournamentRankingPlayerChange>> calculate(
    CreatedTournament tournament,
  ) async {
    if (!tournament.countsForRanking || tournament.rankingIds.isEmpty) {
      return const [];
    }
    final rankings = await _database.loadLocalRankings();
    final selected = rankings.where(
      (ranking) =>
          tournament.countsForRanking &&
          ranking.type == RankingType.elo &&
          tournament.rankingIds.contains(ranking.id),
    );
    final result = <TournamentRankingPlayerChange>[];
    for (final ranking in selected) {
      final snapshot = await LocalRankingEloService(
        database: _database,
        tournamentStorage: _storage,
      ).calculate(ranking);
      for (final entry in snapshot.history.entries) {
        final items = entry.value
            .where((item) => item.tournamentName == tournament.name)
            .toList();
        if (items.isEmpty) continue;
        final delta = items.fold<int>(0, (sum, item) => sum + item.delta);
        final ratingBefore = items.first.ratingAfter - items.first.delta;
        final ratingAfter = items.last.ratingAfter;
        final playerName =
            snapshot.entries
                .where((player) => player.id == entry.key)
                .firstOrNull
                ?.name ??
            entry.key;
        result.add(
          TournamentRankingPlayerChange(
            playerProfileId: entry.key,
            playerName: playerName,
            delta: delta,
            ratingBefore: ratingBefore,
            ratingAfter: ratingAfter,
            tierBefore: EloTier.fromElo(ratingBefore),
            tierAfter: EloTier.fromElo(ratingAfter),
            enableTiers: ranking.enableTiers,
            rankingName: ranking.name,
          ),
        );
      }
    }
    return result;
  }
}
