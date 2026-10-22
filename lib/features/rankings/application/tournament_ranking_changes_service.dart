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
    required this.rankingPositionBefore,
    required this.rankingPositionAfter,
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
  final int? rankingPositionBefore;
  final int? rankingPositionAfter;

  bool get hasTierChange => enableTiers && tierBefore != tierAfter;
  bool get isPromotion => hasTierChange && ratingAfter > ratingBefore;
  int? get positionChange =>
      rankingPositionBefore == null || rankingPositionAfter == null
      ? null
      : rankingPositionBefore! - rankingPositionAfter!;

  Map<String, Object?> toExportJson() => {
    'rankingName': rankingName,
    'playerName': playerName,
    'delta': delta,
    'ratingBefore': ratingBefore,
    'ratingAfter': ratingAfter,
    'rankingPositionBefore': rankingPositionBefore,
    'rankingPositionAfter': rankingPositionAfter,
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
    final eloService = LocalRankingEloService(
      database: _database,
      tournamentStorage: _storage,
    );
    for (final ranking in selected) {
      final before = await eloService.calculateThroughTournament(
        ranking,
        tournament,
        includeTournament: false,
      );
      final after = await eloService.calculateThroughTournament(
        ranking,
        tournament,
        includeTournament: true,
      );
      final beforePositions = {
        for (var index = 0; index < before.entries.length; index++)
          before.entries[index].id: index + 1,
      };
      final afterPositions = {
        for (var index = 0; index < after.entries.length; index++)
          after.entries[index].id: index + 1,
      };
      for (final entry in after.history.entries) {
        final items = entry.value
            .where((item) => item.tournamentId == tournament.id)
            .toList();
        if (items.isEmpty) continue;
        final delta = items.fold<int>(0, (sum, item) => sum + item.delta);
        final ratingBefore = items.first.ratingAfter - items.first.delta;
        final ratingAfter = items.last.ratingAfter;
        final playerName =
            after.entries
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
            rankingPositionBefore: beforePositions[entry.key],
            rankingPositionAfter: afterPositions[entry.key],
          ),
        );
      }
    }
    return result;
  }
}
