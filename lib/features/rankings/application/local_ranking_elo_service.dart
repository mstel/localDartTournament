import 'package:flutter/foundation.dart';

import '../domain/local_elo_calculator.dart';
import '../../tournaments/data/app_database.dart';
import '../../tournaments/data/tournament_storage.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../domain/local_ranking.dart';

class _LocalEloCacheEntry {
  _LocalEloCacheEntry({required this.signature, required this.snapshot});

  final String signature;
  final LocalEloSnapshot snapshot;
}

class LocalRankingEloService {
  const LocalRankingEloService({
    required LocalAppDatabase database,
    TournamentStorage? tournamentStorage,
  }) : _database = database,
       _tournamentStorage = tournamentStorage;

  final LocalAppDatabase _database;
  final TournamentStorage? _tournamentStorage;

  static final Map<String, _LocalEloCacheEntry> _snapshotCache = {};

  @visibleForTesting
  static void clearCache() => _snapshotCache.clear();

  Future<LocalEloSnapshot> calculate(
    LocalRanking ranking, {
    Iterable<CreatedTournament>? tournaments,
  }) async {
    final source =
        tournaments ??
        await (_tournamentStorage ?? TournamentStorage())
            .loadTournamentsForRanking(
              ranking.id,
              from: _rankingFromDate(ranking),
              through: _rankingThroughDate(ranking),
            );
    return _calculate(ranking, source);
  }

  Future<LocalEloSnapshot> calculateThroughTournament(
    LocalRanking ranking,
    CreatedTournament target, {
    required bool includeTournament,
  }) async {
    final tournaments = await (_tournamentStorage ?? TournamentStorage())
        .loadTournamentsForRanking(
          ranking.id,
          from: _rankingFromDate(ranking),
          through: _rankingThroughDate(ranking),
        );
    final targetDate =
        target.tournamentDate ?? target.startedAt ?? target.createdAt;
    final relevant = tournaments.where((tournament) {
      final date =
          tournament.tournamentDate ??
          tournament.startedAt ??
          tournament.createdAt;
      final comparison = date.compareTo(targetDate);
      final orderComparison = comparison == 0
          ? tournament.id.compareTo(target.id)
          : comparison;
      return includeTournament ? orderComparison <= 0 : orderComparison < 0;
    });
    return _calculate(ranking, relevant.toList());
  }

  static String _computeSignature(
    LocalRanking ranking,
    Map<String, String> players,
    List<CreatedTournament> tournaments,
  ) {
    final buffer = StringBuffer()
      ..write(ranking.id)
      ..write('|')
      ..write(ranking.startRating)
      ..write('|')
      ..write(ranking.newPlayerK)
      ..write('|')
      ..write(ranking.normalPlayerK)
      ..write('|')
      ..write(ranking.proPlayerK)
      ..write('|')
      ..write(ranking.matchesBeforeNormal)
      ..write('|')
      ..write(ranking.proRatingThreshold)
      ..write('|')
      ..write(ranking.requireMinimumParticipations)
      ..write('|')
      ..write(ranking.minimumParticipations)
      ..write('|')
      ..write(ranking.allowDecayBelowStartRating)
      ..write('|')
      ..write(ranking.absenceDecayEnabled)
      ..write('|')
      ..write(ranking.absenceDecayPoints)
      ..write('|')
      ..write(ranking.inactivityDecayEnabled)
      ..write('|')
      ..write(ranking.inactivityGraceTournaments)
      ..write('|')
      ..write(ranking.inactivityDecayPoints)
      ..write('|')
      ..write(ranking.countUnassignedPlayers)
      ..write('|')
      ..write(ranking.validFromYear)
      ..write('|')
      ..write(ranking.validToYear)
      ..write('|')
      ..write(ranking.validFromDate?.millisecondsSinceEpoch)
      ..write('|')
      ..write(ranking.validToDate?.millisecondsSinceEpoch)
      ..write('##');
    for (final entry in players.entries) {
      buffer
        ..write(entry.key)
        ..write(':')
        ..write(entry.value)
        ..write(',');
    }
    buffer.write('##');
    for (final tournament in tournaments) {
      buffer
        ..write(tournament.id)
        ..write(':')
        ..write(tournament.updatedAt.millisecondsSinceEpoch)
        ..write(',');
    }
    return buffer.toString();
  }

  Future<LocalEloSnapshot> _calculate(
    LocalRanking ranking,
    Iterable<CreatedTournament> tournaments,
  ) async {
    if (ranking.type != RankingType.elo) {
      throw ArgumentError.value(
        ranking.type,
        'ranking.type',
        'Not an Elo ranking',
      );
    }
    final ids = await _database.loadRankingPlayerIds(ranking.id);
    final profiles = await _database.loadPlayerProfiles();
    final byId = {for (final profile in profiles) profile.id: profile};
    final players = {
      for (final id in ids)
        if (byId[id] case final profile?) profile.id: profile.displayName,
    };
    final tournamentList = tournaments.toList();
    final signature = _computeSignature(ranking, players, tournamentList);
    final cached = _snapshotCache[ranking.id];
    if (cached != null && cached.signature == signature) {
      return cached.snapshot;
    }
    final calculated = LocalEloCalculator().calculate(
      players: players,
      tournaments: tournamentList,
      rankingId: ranking.id,
      startRating: ranking.startRating,
      newPlayerK: ranking.newPlayerK,
      normalPlayerK: ranking.normalPlayerK,
      proPlayerK: ranking.proPlayerK,
      matchesBeforeNormal: ranking.matchesBeforeNormal,
      proRatingThreshold: ranking.proRatingThreshold,
      minimumParticipationTournaments: ranking.requireMinimumParticipations
          ? ranking.minimumParticipations
          : 0,
      allowDecayBelowStartRating: ranking.allowDecayBelowStartRating,
      absenceDecayEnabled: ranking.absenceDecayEnabled,
      absenceDecayPoints: ranking.absenceDecayPoints,
      inactivityDecayEnabled: ranking.inactivityDecayEnabled,
      inactivityGraceTournaments: ranking.inactivityGraceTournaments,
      inactivityDecayPoints: ranking.inactivityDecayPoints,
      countUnassignedPlayers: ranking.countUnassignedPlayers,
      validFromYear: ranking.validFromYear,
      validToYear: ranking.validToYear,
      validFromDate: ranking.validFromDate,
      validToDate: ranking.validToDate,
    );
    _snapshotCache[ranking.id] = _LocalEloCacheEntry(
      signature: signature,
      snapshot: calculated,
    );
    return calculated;
  }
}

DateTime? _rankingFromDate(LocalRanking ranking) =>
    ranking.validFromDate ??
    (ranking.validFromYear == null
        ? null
        : DateTime(ranking.validFromYear!, 1, 1));

DateTime? _rankingThroughDate(LocalRanking ranking) =>
    ranking.validToDate ??
    (ranking.validToYear == null
        ? null
        : DateTime(ranking.validToYear!, 12, 31));
