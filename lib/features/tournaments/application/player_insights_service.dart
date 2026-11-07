import '../../rankings/application/local_ranking_elo_service.dart';
import '../../rankings/domain/local_elo_calculator.dart';
import '../../rankings/domain/local_ranking.dart';
import '../../statistics/domain/player_monthly_performance.dart';
import '../data/app_database.dart';
import '../data/tournament_storage.dart';
import '../domain/player_insight.dart';
import '../domain/tournament_models.dart';
import '../domain/tournament_winner.dart';
import 'player_insight_preferences.dart';

const _rankingDependentInsights = {
  PlayerInsightType.bogeyOpponent,
  PlayerInsightType.rival,
  PlayerInsightType.giantKiller,
  PlayerInsightType.underdog,
  PlayerInsightType.titleDefender,
  PlayerInsightType.risingStar,
  PlayerInsightType.eloClimber,
};

class PlayerInsightsService {
  const PlayerInsightsService({
    required LocalAppDatabase database,
    required TournamentStorage storage,
  }) : _database = database,
       _storage = storage;

  final LocalAppDatabase _database;
  final TournamentStorage _storage;

  Future<Map<String, List<PlayerInsight>>> calculate({
    required CreatedTournament tournament,
    DateTime? now,
  }) async {
    final preferences = await PlayerInsightPreferencesStorage().load();
    final tournaments = await _storage.loadTournaments();
    final history = [
      for (final item in tournaments)
        if (item.id == tournament.id) tournament else item,
      if (!tournaments.any((item) => item.id == tournament.id)) tournament,
    ];
    final participantIds = {
      for (final player in tournament.players.expand(
        (item) => item.individuals,
      ))
        _playerId(player),
    };
    final monthlyEntries = <String, List<PlayerMonthlyPerformance>>{
      for (final playerId in participantIds)
        playerId: <PlayerMonthlyPerformance>[],
    };
    for (final entry in await _database.loadPlayerMonthlyPerformanceForPlayers(
      participantIds,
    )) {
      monthlyEntries[entry.playerId]?.add(entry);
    }

    final rankings = await _database.loadLocalRankings();
    final eloRanking = rankings
        .where(
          (ranking) =>
              ranking.type == RankingType.elo &&
              tournament.rankingIds.contains(ranking.id),
        )
        .firstOrNull;
    final eloSnapshot = eloRanking == null
        ? null
        : await LocalRankingEloService(
            database: _database,
            tournamentStorage: _storage,
          ).calculate(eloRanking, tournaments: history);

    final calculated = PlayerInsightEngine().calculate(
      tournament: tournament,
      history: history,
      monthlyEntries: monthlyEntries,
      eloRanking: eloRanking,
      eloSnapshot: eloSnapshot,
      insightPreferences: preferences,
      now: now ?? DateTime.now(),
    );
    final rankedPlayerIds = <String>{};
    if (tournament.countsForRanking && tournament.rankingIds.isNotEmpty) {
      final catalogIds = (await _database.loadPlayerProfiles())
          .map((profile) => profile.id)
          .toSet();
      for (final ranking in rankings.where(
        (ranking) => tournament.rankingIds.contains(ranking.id),
      )) {
        rankedPlayerIds.addAll(
          (await _database.loadRankingPlayerIds(
            ranking.id,
          )).where(catalogIds.contains),
        );
      }
    }
    return {
      for (final entry in calculated.entries)
        entry.key: List.unmodifiable(
          entry.value.where(
            (insight) =>
                preferences.isEnabled(insight.type) &&
                (!_rankingDependentInsights.contains(insight.type) ||
                    rankedPlayerIds.contains(entry.key)),
          ),
        ),
    };
  }
}

class PlayerInsightEngine {
  Map<String, List<PlayerInsight>> calculate({
    required CreatedTournament tournament,
    required List<CreatedTournament> history,
    required Map<String, List<PlayerMonthlyPerformance>> monthlyEntries,
    required LocalRanking? eloRanking,
    required LocalEloSnapshot? eloSnapshot,
    required PlayerInsightPreferences insightPreferences,
    required DateTime now,
  }) {
    final participants = <String, TournamentPlayer>{
      for (final player in tournament.players.expand(
        (item) => item.individuals,
      ))
        _playerId(player): player,
    };
    if (participants.isEmpty) return const {};

    final tournaments = [
      for (final item in history)
        if (item.id != tournament.id) item,
      tournament,
    ];
    final matches = [
      for (final item in tournaments) ..._matchesForTournament(item),
    ]..sort(_compareMatches);
    final insights = <String, List<PlayerInsight>>{
      for (final playerId in participants.keys) playerId: <PlayerInsight>[],
    };
    void add(
      String playerId,
      PlayerInsightType type,
      String explanation, {
      String? rivalId,
    }) {
      insights[playerId]?.add(
        PlayerInsight(
          type: type,
          playerId: playerId,
          rivalId: rivalId,
          explanation: explanation,
        ),
      );
    }

    final matchesByPlayer = <String, List<_InsightMatch>>{
      for (final playerId in participants.keys) playerId: [],
    };
    for (final match in matches) {
      for (final playerId in match.players) {
        matchesByPlayer[playerId]?.add(match);
      }
    }
    final tournamentMatches = matches
        .where((match) => match.tournament.id == tournament.id)
        .toList();
    final firstCompletedMatchIndex = tournamentMatches.indexWhere(
      (match) => match.hasOutcome,
    );
    final momentumPlayerIds = firstCompletedMatchIndex < 0
        ? const <String>{}
        : tournamentMatches[firstCompletedMatchIndex].winnerIds;

    for (final entry in participants.entries) {
      final playerId = entry.key;
      final playerName = entry.value.name;
      final playerMatches = matchesByPlayer[playerId]!;
      final recent = playerMatches.reversed.toList();
      final outcomes = [
        for (final match in recent)
          if (match.winnerIds.contains(playerId))
            true
          else if (match.loserIds.contains(playerId))
            false
          else
            null,
      ];
      final winsInARow = _leadingStreak(outcomes, true);
      final lossesInARow = _leadingStreak(outcomes, false);

      if (winsInARow >=
          insightPreferences.thresholdFor(PlayerInsightType.unstoppable)) {
        add(
          playerId,
          PlayerInsightType.unstoppable,
          '$playerName hat mindestens '
          '${insightPreferences.thresholdFor(PlayerInsightType.unstoppable)} '
          'Matches in Folge gewonnen '
          '(aktuell $winsInARow).',
        );
      } else if (winsInARow >=
          insightPreferences.thresholdFor(PlayerInsightType.hotStreak)) {
        add(
          playerId,
          PlayerInsightType.hotStreak,
          '$playerName hat seine letzten $winsInARow Matches in Folge gewonnen.',
        );
      }
      if (lossesInARow >=
          insightPreferences.thresholdFor(PlayerInsightType.coldStreak)) {
        add(
          playerId,
          PlayerInsightType.coldStreak,
          '$playerName hat seine letzten $lossesInARow Matches in Folge verloren.',
        );
      }
      final hasLostSinceFirstTournamentWin =
          momentumPlayerIds.contains(playerId) &&
          tournamentMatches.indexed.any(
            (entry) =>
                entry.$1 > firstCompletedMatchIndex &&
                entry.$2.loserIds.contains(playerId),
          );
      if (momentumPlayerIds.contains(playerId) &&
          !hasLostSinceFirstTournamentWin) {
        add(
          playerId,
          PlayerInsightType.momentum,
          '$playerName hat die erste abgeschlossene Partie des Turniers '
          'gewonnen und seitdem noch keine Partie verloren.',
        );
      }
      if (outcomes.isNotEmpty && outcomes.first == true && lossesInARow == 0) {
        final precedingLosses = _leadingStreak(
          outcomes.skip(1).toList(),
          false,
        );
        if (precedingLosses >=
            insightPreferences.thresholdFor(PlayerInsightType.backOnTrack)) {
          add(
            playerId,
            PlayerInsightType.backOnTrack,
            '$playerName hat nach $precedingLosses Niederlagen in Folge '
            'wieder ein Match gewonnen.',
          );
        }
      }
      if (outcomes.length >= 5 &&
          outcomes.take(5).every((outcome) => outcome != null) &&
          List.generate(
            4,
            (index) => outcomes[index] != outcomes[index + 1],
          ).every((alternates) => alternates)) {
        add(
          playerId,
          PlayerInsightType.consistent,
          'Die letzten 5 Matches von $playerName wechselten ohne zwei '
          'aufeinanderfolgende Siege oder Niederlagen.',
        );
      }

      final lastFive = recent.take(5).toList();
      if (lastFive.length == 5) {
        final decidingMatches = lastFive
            .where((match) => match.isDecider)
            .length;
        final minimumDeciders = insightPreferences.thresholdFor(
          PlayerInsightType.lastLegStanding,
        );
        if (decidingMatches >= minimumDeciders) {
          add(
            playerId,
            PlayerInsightType.lastLegStanding,
            '$playerName hat $decidingMatches seiner letzten 5 Matches '
            'im entscheidenden letzten Leg beendet.',
          );
        }
      }

      _addRisingStar(
        add,
        playerId,
        playerName,
        monthlyEntries[playerId] ?? const [],
        now,
        insightPreferences,
      );
      _addTitleDefender(add, playerId, playerName, tournament, history);
    }

    _addHeadToHeadInsights(
      participants,
      matches,
      add,
      eloSnapshot,
      insightPreferences,
    );
    _addTournamentUnderdogs(
      tournament,
      participants,
      eloRanking,
      eloSnapshot,
      add,
    );
    _addEloClimbers(
      participants,
      eloRanking,
      eloSnapshot,
      insightPreferences,
      add,
      now,
    );

    return {
      for (final entry in insights.entries)
        entry.key: List.unmodifiable(entry.value),
    };
  }

  void _addRisingStar(
    void Function(String, PlayerInsightType, String, {String? rivalId}) add,
    String playerId,
    String playerName,
    List<PlayerMonthlyPerformance> entries,
    DateTime now,
    PlayerInsightPreferences insightPreferences,
  ) {
    final currentMonth = DateTime(now.year, now.month);
    final previousMonth = DateTime(now.year, now.month - 1);
    final current = _eligibleMonth(entries, currentMonth);
    final previous = _eligibleMonth(entries, previousMonth);
    if (current?.average == null || previous?.average == null) return;
    final improvement = current!.average! - previous!.average!;
    final minimumImprovement = insightPreferences.thresholdFor(
      PlayerInsightType.risingStar,
    );
    if (improvement < minimumImprovement) return;
    add(
      playerId,
      PlayerInsightType.risingStar,
      '$playerName hat seinen Average im Vergleich zum Vormonat um '
      '${improvement.toStringAsFixed(1).replaceFirst('.', ',')} Punkte '
      'gesteigert (Schwelle: $minimumImprovement Punkte).',
    );
  }

  PlayerMonthlyPerformance? _eligibleMonth(
    List<PlayerMonthlyPerformance> entries,
    DateTime month,
  ) => entries
      .where(
        (entry) =>
            entry.year == month.year &&
            entry.month == month.month &&
            entry.weightedLegs >= 10 &&
            entry.average != null,
      )
      .firstOrNull;

  void _addHeadToHeadInsights(
    Map<String, TournamentPlayer> participants,
    List<_InsightMatch> matches,
    void Function(String, PlayerInsightType, String, {String? rivalId}) add,
    LocalEloSnapshot? eloSnapshot,
    PlayerInsightPreferences insightPreferences,
  ) {
    final playerIds = participants.keys.toList();
    final directMatchesByPair = <(String, String), List<_InsightMatch>>{};
    for (final match in matches) {
      if (!match.isOneVsOne) continue;
      final homeId = match.homeIds.single;
      final awayId = match.awayIds.single;
      if (!participants.containsKey(homeId) ||
          !participants.containsKey(awayId)) {
        continue;
      }
      final pair = homeId.compareTo(awayId) < 0
          ? (homeId, awayId)
          : (awayId, homeId);
      (directMatchesByPair[pair] ??= []).add(match);
    }
    for (var firstIndex = 0; firstIndex < playerIds.length; firstIndex++) {
      for (
        var secondIndex = firstIndex + 1;
        secondIndex < playerIds.length;
        secondIndex++
      ) {
        final firstId = playerIds[firstIndex];
        final secondId = playerIds[secondIndex];
        final pair = firstId.compareTo(secondId) < 0
            ? (firstId, secondId)
            : (secondId, firstId);
        final directMatches = directMatchesByPair[pair] ?? const [];
        if (directMatches.isEmpty) continue;

        final firstName = participants[firstId]!.name;
        final secondName = participants[secondId]!.name;
        if (directMatches.length >= 10) {
          final latestTen = directMatches.skip(directMatches.length - 10);
          final firstWins = latestTen
              .where((match) => match.winnerIds.contains(firstId))
              .length;
          final firstLosses = latestTen
              .where((match) => match.loserIds.contains(firstId))
              .length;
          final secondWins = latestTen
              .where((match) => match.winnerIds.contains(secondId))
              .length;
          final secondLosses = latestTen
              .where((match) => match.loserIds.contains(secondId))
              .length;

          void addHeadToHeadInsights(
            String playerId,
            String rivalId,
            String playerName,
            String rivalName,
            int wins,
            int losses,
          ) {
            if (losses >=
                insightPreferences.thresholdFor(
                  PlayerInsightType.bogeyOpponent,
                )) {
              add(
                playerId,
                PlayerInsightType.bogeyOpponent,
                '$playerName hat $losses seiner letzten 10 direkten Duelle '
                'gegen $rivalName verloren.',
                rivalId: rivalId,
              );
            }
            final balancedWinThreshold = insightPreferences.thresholdFor(
              PlayerInsightType.rival,
            );
            if (wins >= balancedWinThreshold &&
                wins <= 10 - balancedWinThreshold) {
              add(
                playerId,
                PlayerInsightType.rival,
                '$playerName hat $wins seiner letzten 10 direkten Duelle '
                'gegen $rivalName gewonnen.',
                rivalId: rivalId,
              );
            }
          }

          addHeadToHeadInsights(
            firstId,
            secondId,
            firstName,
            secondName,
            firstWins,
            firstLosses,
          );
          addHeadToHeadInsights(
            secondId,
            firstId,
            secondName,
            firstName,
            secondWins,
            secondLosses,
          );
        }

        _addRevengeInsight(
          firstId,
          secondId,
          firstName,
          secondName,
          directMatches,
          insightPreferences,
          add,
        );
        _addRevengeInsight(
          secondId,
          firstId,
          secondName,
          firstName,
          directMatches,
          insightPreferences,
          add,
        );
        _addGiantKillerInsight(
          firstId,
          secondId,
          firstName,
          secondName,
          directMatches,
          eloSnapshot,
          insightPreferences,
          add,
        );
        _addGiantKillerInsight(
          secondId,
          firstId,
          secondName,
          firstName,
          directMatches,
          eloSnapshot,
          insightPreferences,
          add,
        );
      }
    }
  }

  void _addRevengeInsight(
    String playerId,
    String rivalId,
    String playerName,
    String rivalName,
    List<_InsightMatch> directMatches,
    PlayerInsightPreferences insightPreferences,
    void Function(String, PlayerInsightType, String, {String? rivalId}) add,
  ) {
    final recent = directMatches.reversed.toList();
    final minimumPriorLosses = insightPreferences.thresholdFor(
      PlayerInsightType.sweetRevenge,
    );
    if (recent.length < minimumPriorLosses + 1 ||
        !recent.first.winnerIds.contains(playerId)) {
      return;
    }
    final priorLosses = _leadingStreak([
      for (final match in recent.skip(1)) match.winnerIds.contains(rivalId),
    ], true);
    if (priorLosses < minimumPriorLosses) return;
    add(
      playerId,
      PlayerInsightType.sweetRevenge,
      '$playerName hat $rivalName geschlagen, nachdem er zuvor '
      '$priorLosses direkte Duelle in Folge gegen $rivalName verloren hatte.',
      rivalId: rivalId,
    );
  }

  void _addGiantKillerInsight(
    String playerId,
    String rivalId,
    String playerName,
    String rivalName,
    List<_InsightMatch> directMatches,
    LocalEloSnapshot? eloSnapshot,
    PlayerInsightPreferences insightPreferences,
    void Function(String, PlayerInsightType, String, {String? rivalId}) add,
  ) {
    if (eloSnapshot == null || directMatches.isEmpty) return;
    final lastMatch = directMatches.last;
    if (!lastMatch.winnerIds.contains(playerId)) return;
    final ratingBefore = _matchRatings(
      eloSnapshot,
      lastMatch,
      playerId,
      rivalId,
    );
    if (ratingBefore == null) return;
    final difference = ratingBefore.$2 - ratingBefore.$1;
    if (difference <
        insightPreferences.thresholdFor(PlayerInsightType.giantKiller)) {
      return;
    }
    add(
      playerId,
      PlayerInsightType.giantKiller,
      '$playerName hat $rivalName geschlagen, obwohl er zum Zeitpunkt '
      'des Matches $difference ELO-Punkte weniger hatte.',
      rivalId: rivalId,
    );
  }

  (int, int)? _matchRatings(
    LocalEloSnapshot snapshot,
    _InsightMatch match,
    String playerId,
    String rivalId,
  ) {
    LocalEloHistoryItem? ratingFor(String id) => snapshot.history[id]
        ?.where(
          (item) =>
              item.tournamentId == match.tournament.id &&
              item.matchIndex == match.matchIndex &&
              item.decayReason == null,
        )
        .firstOrNull;
    final playerRating = ratingFor(playerId)?.ratingBefore;
    final rivalRating = ratingFor(rivalId)?.ratingBefore;
    return playerRating == null || rivalRating == null
        ? null
        : (playerRating, rivalRating);
  }

  void _addTournamentUnderdogs(
    CreatedTournament tournament,
    Map<String, TournamentPlayer> participants,
    LocalRanking? ranking,
    LocalEloSnapshot? snapshot,
    void Function(String, PlayerInsightType, String, {String? rivalId}) add,
  ) {
    if (ranking == null || snapshot == null || participants.length < 3) return;
    final rankings = [
      for (final entry in snapshot.entries)
        if (participants.containsKey(entry.id)) entry,
    ]..sort((left, right) => right.rating.compareTo(left.rating));
    if (rankings.length < 3 || rankings.length != participants.length) return;
    final cutoff = (rankings.length * 2 / 3).ceil();
    final lowerThird = rankings.skip(cutoff).map((entry) => entry.id).toSet();
    final wins = <String, int>{};
    final losses = <String, int>{};
    for (final match in _matchesForTournament(tournament)) {
      if (!match.match.countsForStatistics || match.match.isKratzer) continue;
      for (final id in match.winnerIds) {
        if (participants.containsKey(id)) {
          wins.update(id, (n) => n + 1, ifAbsent: () => 1);
        }
      }
      for (final id in match.loserIds) {
        if (participants.containsKey(id)) {
          losses.update(id, (n) => n + 1, ifAbsent: () => 1);
        }
      }
    }
    for (final playerId in lowerThird) {
      final winCount = wins[playerId] ?? 0;
      final lossCount = losses[playerId] ?? 0;
      if (winCount <= lossCount || winCount + lossCount == 0) continue;
      add(
        playerId,
        PlayerInsightType.underdog,
        '${participants[playerId]!.name} gehört zu den unteren 33 % '
        'der ELO-Rangliste des Teilnehmerfelds und hat im Turnier '
        'eine positive Matchbilanz ($winCount Siege, $lossCount Niederlagen).',
      );
    }
  }

  void _addEloClimbers(
    Map<String, TournamentPlayer> participants,
    LocalRanking? ranking,
    LocalEloSnapshot? snapshot,
    PlayerInsightPreferences insightPreferences,
    void Function(String, PlayerInsightType, String, {String? rivalId}) add,
    DateTime now,
  ) {
    if (ranking == null || snapshot == null) return;
    final cutoff = now.subtract(const Duration(days: 30));
    final gains = <String, int>{};
    final ratings = {
      for (final entry in snapshot.entries) entry.id: entry.rating,
    };
    if (participants.keys.any((playerId) => !ratings.containsKey(playerId))) {
      return;
    }
    for (final playerId in participants.keys) {
      final baseline = (snapshot.history[playerId] ?? const [])
          .where((item) => !item.playedAt.isAfter(cutoff))
          .fold<LocalEloHistoryItem?>(
            null,
            (latest, item) =>
                latest == null || !item.playedAt.isBefore(latest.playedAt)
                ? item
                : latest,
          );
      if (baseline == null) return;
      gains[playerId] = ratings[playerId]! - baseline.ratingAfter;
    }
    final highestGain = gains.values.fold<int>(
      0,
      (highest, gain) => gain > highest ? gain : highest,
    );
    if (highestGain <
        insightPreferences.thresholdFor(PlayerInsightType.eloClimber)) {
      return;
    }
    for (final entry in gains.entries) {
      if (entry.value != highestGain) continue;
      final playerName = participants[entry.key]!.name;
      add(
        entry.key,
        PlayerInsightType.eloClimber,
        '$playerName hat in den letzten 30 Tagen $highestGain ELO-Punkte '
        'gewonnen und damit den höchsten Zuwachs im Teilnehmerfeld erzielt.',
      );
    }
  }

  void _addTitleDefender(
    void Function(String, PlayerInsightType, String, {String? rivalId}) add,
    String playerId,
    String playerName,
    CreatedTournament tournament,
    List<CreatedTournament> history,
  ) {
    final previousEdition =
        history
            .where(
              (item) =>
                  item.id != tournament.id &&
                  _seriesKey(item) == _seriesKey(tournament) &&
                  _isBeforeTournament(item, tournament) &&
                  _winnerId(item) != null,
            )
            .toList()
          ..sort(
            (left, right) => right.effectiveDate.compareTo(left.effectiveDate),
          );
    if (previousEdition.isEmpty ||
        _winnerId(previousEdition.first) != playerId) {
      return;
    }
    add(
      playerId,
      PlayerInsightType.titleDefender,
      '$playerName hat die vorherige Ausgabe von '
      '„${tournament.name}“ gewonnen.',
    );
  }

  bool _isBeforeTournament(
    CreatedTournament candidate,
    CreatedTournament current,
  ) {
    final dateComparison = candidate.effectiveDate.compareTo(
      current.effectiveDate,
    );
    return dateComparison < 0 ||
        dateComparison == 0 && candidate.id.compareTo(current.id) < 0;
  }

  String _seriesKey(CreatedTournament tournament) {
    final rankingIds = tournament.rankingIds.toList()..sort();
    return '${tournament.name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')}|'
        '${tournament.leagueMatch == null ? 'tournament' : 'league'}|'
        '${tournament.importedArchive?.mode ?? ''}|'
        '${rankingIds.join(',')}';
  }

  String? _winnerId(CreatedTournament tournament) {
    final profileId = TournamentWinner.profileId(tournament);
    if (profileId != null) return profileId;
    final winnerName = TournamentWinner.name(tournament);
    if (winnerName == null) return null;
    final matchingPlayers = tournament.players
        .where((player) => player.name == winnerName)
        .toList();
    return matchingPlayers.length == 1
        ? _playerId(matchingPlayers.single)
        : null;
  }

  int _leadingStreak(List<bool?> outcomes, bool value) {
    var count = 0;
    for (final outcome in outcomes) {
      if (outcome != value) break;
      count++;
    }
    return count;
  }

  List<_InsightMatch> _matchesForTournament(CreatedTournament tournament) {
    final result = <_InsightMatch>[];
    final seen = <GroupMatch>{};
    var index = 0;
    for (
      var stageIndex = 0;
      stageIndex < tournament.runStages.length;
      stageIndex++
    ) {
      final stage = tournament.runStages[stageIndex];
      final stageMatches = <GroupMatch>[
        if (stage is KnockoutTournamentRunStage) ...stage.matches,
        if (stage is GroupTournamentRunStage)
          for (final group in stage.groups) ...[
            ...group.matches,
            ...group.knockoutRounds.expand((round) => round),
            ...group.placementMatches,
          ],
      ];
      for (final match in stageMatches) {
        final matchIndex = index;
        index++;
        if (!seen.add(match) ||
            !match.hasResult ||
            match.isAnnulled ||
            match.withdrawalIgnored) {
          continue;
        }
        final homeIds = match.isKratzer
            ? <String>{}
            : match.homePlayer == null
            ? <String>{}
            : _playerIds(match.homePlayer!);
        final awayIds = match.isKratzer
            ? <String>{}
            : match.awayPlayer == null
            ? <String>{}
            : _playerIds(match.awayPlayer!);
        final winnerIds = match.isKratzer || match.winner == null
            ? <String>{}
            : _playerIds(match.winner!);
        final loserIds = match.isKratzer || match.loser == null
            ? <String>{}
            : _playerIds(match.loser!);
        final date =
            match.finishedAt ??
            match.startedAt ??
            tournament.tournamentDate ??
            tournament.createdAt;
        final gameFormat = stageIndex < tournament.stages.length
            ? tournament.stages[stageIndex].gameFormat
            : null;
        result.add(
          _InsightMatch(
            tournament: tournament,
            match: match,
            matchIndex: matchIndex,
            date: date,
            homeIds: homeIds,
            awayIds: awayIds,
            winnerIds: winnerIds,
            loserIds: loserIds,
            gameFormat: gameFormat,
          ),
        );
      }
    }
    return result;
  }

  int _compareMatches(_InsightMatch left, _InsightMatch right) {
    final time = left.date.compareTo(right.date);
    if (time != 0) return time;
    final tournament = left.tournament.id.compareTo(right.tournament.id);
    if (tournament != 0) return tournament;
    final round = left.match.round.compareTo(right.match.round);
    return round != 0 ? round : left.matchIndex.compareTo(right.matchIndex);
  }
}

class _InsightMatch {
  const _InsightMatch({
    required this.tournament,
    required this.match,
    required this.matchIndex,
    required this.date,
    required this.homeIds,
    required this.awayIds,
    required this.winnerIds,
    required this.loserIds,
    required this.gameFormat,
  });

  final CreatedTournament tournament;
  final GroupMatch match;
  final int matchIndex;
  final DateTime date;
  final Set<String> homeIds;
  final Set<String> awayIds;
  final Set<String> winnerIds;
  final Set<String> loserIds;
  final TournamentGameFormat? gameFormat;

  Set<String> get players => {...homeIds, ...awayIds};
  bool get hasOutcome => winnerIds.isNotEmpty || loserIds.isNotEmpty;
  bool get isOneVsOne =>
      !match.isKratzer && homeIds.length == 1 && awayIds.length == 1;
  bool get isDecider {
    final format = gameFormat;
    if (format == null || match.winner == null) return false;
    if (format.bestOfSets > 1) {
      return match.hasSetScore &&
          match.homeSets! + match.awaySets! == format.bestOfSets &&
          match.homeLegs != null &&
          match.awayLegs != null &&
          match.homeLegs! + match.awayLegs! ==
              format.bestOfSets * format.bestOfLegs;
    }
    return match.homeLegs != null &&
        match.awayLegs != null &&
        match.homeLegs! + match.awayLegs! == format.bestOfLegs;
  }
}

String _playerId(TournamentPlayer player) =>
    player.profileId ?? 'name:${player.name.trim().toLowerCase()}';

Set<String> _playerIds(TournamentPlayer player) => {
  for (final individual in player.individuals) _playerId(individual),
};
