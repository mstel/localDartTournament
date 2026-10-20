import 'dart:math';

import '../../tournaments/application/player_withdrawal_service.dart';
import '../../tournaments/domain/tournament_models.dart';

const int defaultEloRating = 1000;
const int defaultNewPlayerK = 25;
const int defaultNormalPlayerK = 15;
const int defaultMatchesBeforeNormal = 10;
const int defaultProRatingThreshold = 2400;

int eloDelta(
  int rating,
  int opponentRating,
  double score, {
  int kFactor = 15,
}) => (kFactor * (score - eloExpectedScore(rating, opponentRating))).round();

double eloExpectedScore(int rating, int opponentRating) =>
    1 / (1 + pow(10, (opponentRating - rating) / 400));

int eloKFactorForMatches(
  int matches, {
  int rating = defaultEloRating,
  int newPlayerK = defaultNewPlayerK,
  int normalPlayerK = defaultNormalPlayerK,
  int proPlayerK = defaultNormalPlayerK,
  int matchesBeforeNormal = defaultMatchesBeforeNormal,
  int proRatingThreshold = defaultProRatingThreshold,
}) => rating >= proRatingThreshold
    ? proPlayerK
    : matches < matchesBeforeNormal
    ? newPlayerK
    : normalPlayerK;

class LocalEloPlayer {
  LocalEloPlayer({
    required this.id,
    required this.name,
    this.rating = defaultEloRating,
  });
  final String id;
  final String name;
  int rating;
  int matches = 0, wins = 0, losses = 0, draws = 0;
}

class LocalEloHistoryItem {
  const LocalEloHistoryItem({
    required this.tournamentId,
    required this.matchIndex,
    required this.playedAt,
    required this.tournamentName,
    required this.opponentName,
    required this.score,
    required this.delta,
    required this.ratingAfter,
    required this.kFactor,
    required this.expectedScore,
  });
  final String tournamentId;
  final int matchIndex;
  final DateTime playedAt;
  final String tournamentName, opponentName, score;
  final int delta, ratingAfter, kFactor;
  final double expectedScore;
}

class LocalEloSnapshot {
  const LocalEloSnapshot(
    this.entries,
    this.history, {
    this.matchDeltas = const {},
  });
  final List<LocalEloPlayer> entries;
  final Map<String, List<LocalEloHistoryItem>> history;
  final Map<String, LocalEloMatchDelta> matchDeltas;
}

class LocalEloMatchDelta {
  const LocalEloMatchDelta({this.home, this.away});

  final int? home;
  final int? away;
}

class LocalEloCalculator {
  const LocalEloCalculator();

  LocalEloSnapshot calculate({
    required Map<String, String> players,
    required List<CreatedTournament> tournaments,
    String rankingId = '',
    int startRating = defaultEloRating,
    int newPlayerK = defaultNewPlayerK,
    int normalPlayerK = defaultNormalPlayerK,
    int proPlayerK = defaultNormalPlayerK,
    int matchesBeforeNormal = defaultMatchesBeforeNormal,
    int proRatingThreshold = defaultProRatingThreshold,
    int? validFromYear,
    int? validToYear,
    DateTime? validFromDate,
    DateTime? validToDate,
    DateTime? now,
  }) {
    final entries = <String, LocalEloPlayer>{
      for (final item in players.entries)
        item.key: LocalEloPlayer(
          id: item.key,
          name: item.value,
          rating: startRating,
        ),
    };
    final history = <String, List<LocalEloHistoryItem>>{};
    final matchDeltas = <String, LocalEloMatchDelta>{};
    final ordered = tournaments.toList()
      ..sort((a, b) {
        final time = _date(a).compareTo(_date(b));
        return time == 0 ? a.id.compareTo(b.id) : time;
      });
    final pending = [
      for (final tournament in ordered)
        if (tournament.countsForRanking &&
            tournament.rankingIds.contains(rankingId) &&
            (validFromYear == null ||
                _date(tournament).year >= validFromYear) &&
            (validToYear == null || _date(tournament).year <= validToYear))
          for (final indexedMatch in _matches(
            tournament,
          ).toList().asMap().entries)
            if (indexedMatch.value.hasResult &&
                indexedMatch.value.homePlayer != null &&
                indexedMatch.value.awayPlayer != null &&
                (validFromDate == null ||
                    !_dateOnly(
                      _matchDate(tournament, indexedMatch.value),
                    ).isBefore(_dateOnly(validFromDate))) &&
                (validToDate == null ||
                    !_dateOnly(
                      _matchDate(tournament, indexedMatch.value),
                    ).isAfter(_dateOnly(validToDate))))
              (
                tournament: tournament,
                match: indexedMatch.value,
                matchIndex: indexedMatch.key,
              ),
    ];
    pending.sort((a, b) {
      final time = _matchDate(
        a.tournament,
        a.match,
      ).compareTo(_matchDate(b.tournament, b.match));
      if (time != 0) return time;
      final tid = a.tournament.id.compareTo(b.tournament.id);
      if (tid != 0) return tid;
      return a.match.round.compareTo(b.match.round);
    });
    for (final row in pending) {
      final tournament = row.tournament;
      final match = row.match;
      final date = _matchDate(tournament, match);
      if (now != null &&
          validFromYear == null &&
          validToYear == null &&
          date.year != now.year) {
        continue;
      }
      final homeId = match.homePlayer!.profileId ?? match.homePlayer!.name;
      final awayId = match.awayPlayer!.profileId ?? match.awayPlayer!.name;
      if (homeId == awayId) continue;
      final home = entries[homeId], away = entries[awayId];
      if (home == null || away == null) continue;
      final homeWon = match.winner == match.homePlayer;
      final awayWon = match.winner == match.awayPlayer;
      final draw = !homeWon && !awayWon && match.homeScore == match.awayScore;
      if (!homeWon && !awayWon && !draw) continue;
      final homeScore = draw
          ? .5
          : homeWon
          ? 1.0
          : 0.0;
      final homeExpected = eloExpectedScore(home.rating, away.rating);
      final homeK = eloKFactorForMatches(
        home.matches,
        rating: home.rating,
        newPlayerK: newPlayerK,
        normalPlayerK: normalPlayerK,
        proPlayerK: proPlayerK,
        matchesBeforeNormal: matchesBeforeNormal,
        proRatingThreshold: proRatingThreshold,
      );
      final awayK = eloKFactorForMatches(
        away.matches,
        rating: away.rating,
        newPlayerK: newPlayerK,
        normalPlayerK: normalPlayerK,
        proPlayerK: proPlayerK,
        matchesBeforeNormal: matchesBeforeNormal,
        proRatingThreshold: proRatingThreshold,
      );
      final homeDelta = eloDelta(
        home.rating,
        away.rating,
        homeScore,
        kFactor: homeK,
      );
      final awayDelta = eloDelta(
        away.rating,
        home.rating,
        1 - homeScore,
        kFactor: awayK,
      );
      final homeRule = PlayerWithdrawalService.policy(
        tournament,
        match.homePlayer!,
      );
      final awayRule = PlayerWithdrawalService.policy(
        tournament,
        match.awayPlayer!,
      );
      final countHome =
          (homeRule?.countForRanking ?? true) &&
          (awayRule?.countOpponentsForRanking ?? true);
      final countAway =
          (awayRule?.countForRanking ?? true) &&
          (homeRule?.countOpponentsForRanking ?? true);
      matchDeltas[_matchKey(tournament, row.matchIndex)] = LocalEloMatchDelta(
        home: countHome ? homeDelta : null,
        away: countAway ? awayDelta : null,
      );
      if (countHome) {
        home.rating += homeDelta;
        home.matches++;
      }
      if (countAway) {
        away.rating += awayDelta;
        away.matches++;
      }
      if (draw) {
        if (countHome) home.draws++;
        if (countAway) away.draws++;
      } else if (homeWon) {
        if (countHome) home.wins++;
        if (countAway) away.losses++;
      } else {
        if (countAway) away.wins++;
        if (countHome) home.losses++;
      }
      if (countHome) {
        (history[homeId] ??= []).add(
          LocalEloHistoryItem(
            tournamentId: tournament.id,
            matchIndex: row.matchIndex,
            playedAt: date,
            tournamentName: tournament.name,
            opponentName: away.name,
            score: match.scoreLabel,
            delta: homeDelta,
            ratingAfter: home.rating,
            kFactor: homeK,
            expectedScore: homeExpected,
          ),
        );
      }
      if (countAway) {
        (history[awayId] ??= []).add(
          LocalEloHistoryItem(
            tournamentId: tournament.id,
            matchIndex: row.matchIndex,
            playedAt: date,
            tournamentName: tournament.name,
            opponentName: home.name,
            score:
                '${match.awayScore}:${match.homeScore}${match.hasSetScore ? ' Sets' : ''}',
            delta: awayDelta,
            ratingAfter: away.rating,
            kFactor: awayK,
            expectedScore: 1 - homeExpected,
          ),
        );
      }
    }
    final result = entries.values.where((e) => e.matches > 0).toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));
    return LocalEloSnapshot(result, history, matchDeltas: matchDeltas);
  }

  String? matchKey(CreatedTournament tournament, GroupMatch match) {
    final index = _matches(
      tournament,
    ).toList().indexWhere((candidate) => identical(candidate, match));
    return index < 0 ? null : _matchKey(tournament, index);
  }

  String _matchKey(CreatedTournament tournament, int matchIndex) =>
      '${tournament.id}:$matchIndex';

  DateTime _date(CreatedTournament t) => t.startedAt ?? t.createdAt;
  DateTime _matchDate(CreatedTournament t, GroupMatch m) =>
      m.finishedAt ?? m.startedAt ?? _date(t);
  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);
  Iterable<GroupMatch> _matches(CreatedTournament t) sync* {
    for (final stage in t.runStages) {
      if (stage is KnockoutTournamentRunStage) {
        yield* stage.matches;
      }
      if (stage is GroupTournamentRunStage) {
        for (final group in stage.groups) {
          yield* group.matches;
          yield* group.knockoutRounds.expand((round) => round);
          yield* group.placementMatches;
        }
      }
    }
  }
}
