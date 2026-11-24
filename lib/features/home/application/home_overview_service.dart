import '../../rankings/application/local_ranking_elo_service.dart';
import '../../rankings/domain/local_elo_calculator.dart';
import '../../rankings/domain/local_ranking.dart';
import '../../statistics/domain/best_performance.dart';
import '../../statistics/domain/player_monthly_performance.dart';
import '../../statistics/domain/tournament_monthly_results.dart';
import '../../tournaments/data/app_database.dart';
import '../../tournaments/data/tournament_storage.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../../tournaments/application/tournament_timing.dart';
import '../../tournaments/domain/engines/placement_engine.dart';
import '../../tournaments/domain/tournament_winner.dart';
import '../../../shared/utils/match_display.dart';

abstract interface class HomeOverviewDataSource {
  Future<List<CreatedTournament>> loadTournaments();
  Future<List<LocalRanking>> loadRankings();
  Future<LocalEloSnapshot?> loadEloSnapshot(
    LocalRanking ranking,
    List<CreatedTournament> tournaments,
  );
}

/// Optional capability for sources that can provide the combined player-month
/// performances used by the compact home win-rate chart.
///
/// Kept separate from [HomeOverviewDataSource] so existing simple test doubles
/// do not have to implement it.
abstract interface class HomeMonthlyPerformanceDataSource
    extends HomeOverviewDataSource {
  Future<List<PlayerMonthlyPerformance>> loadMonthlyPerformances(
    Set<String> playerIds,
    List<CreatedTournament> completedTournaments,
  );
}

class LocalHomeOverviewDataSource
    implements HomeOverviewDataSource, HomeMonthlyPerformanceDataSource {
  LocalHomeOverviewDataSource({
    TournamentStorage? tournamentStorage,
    LocalAppDatabase? database,
  }) : _tournamentStorage = tournamentStorage ?? TournamentStorage(),
       _database = database ?? LocalAppDatabase();

  final TournamentStorage _tournamentStorage;
  final LocalAppDatabase _database;

  @override
  Future<List<CreatedTournament>> loadTournaments() =>
      _tournamentStorage.loadTournaments();

  @override
  Future<List<LocalRanking>> loadRankings() => _database.loadLocalRankings();

  @override
  Future<LocalEloSnapshot?> loadEloSnapshot(
    LocalRanking ranking,
    List<CreatedTournament> tournaments,
  ) {
    if (ranking.type != RankingType.elo) {
      return Future<LocalEloSnapshot?>.value();
    }
    return LocalRankingEloService(
      database: _database,
      tournamentStorage: _tournamentStorage,
    ).calculate(ranking, tournaments: tournaments);
  }

  @override
  Future<List<PlayerMonthlyPerformance>> loadMonthlyPerformances(
    Set<String> playerIds,
    List<CreatedTournament> completedTournaments,
  ) async {
    final catalogIds = (await _database.loadPlayerProfiles())
        .map((profile) => profile.id)
        .toSet();
    final ids = {...playerIds, ...catalogIds};
    return combineMonthlyPlayerPerformances(
      recorded: await _database.loadPlayerMonthlyPerformanceForPlayers(ids),
      imported: await _database.loadMonthlyPlayerPerformances(ids),
      tournamentResults: const TournamentMonthlyResultCalculator().calculate(
        completedTournaments,
        playerIds: ids,
      ),
    );
  }
}

class HomeOverviewActiveTournament {
  const HomeOverviewActiveTournament({
    required this.id,
    required this.name,
    required this.participantCount,
    required this.playedMatches,
    required this.totalMatches,
    required this.openMatches,
  });

  final String id;
  final String name;
  final int participantCount;
  final int playedMatches;
  final int totalMatches;
  final int openMatches;

  double get progress => totalMatches == 0 ? 0 : playedMatches / totalMatches;
}

class HomeOverviewCard {
  const HomeOverviewCard({
    required this.title,
    required this.lines,
    required this.icon,
  });

  final String title;
  final List<String> lines;
  final String icon;
}

/// One month of the club-wide win-rate trend shown on the homepage.
class HomeWinRatePoint {
  const HomeWinRatePoint({
    required this.year,
    required this.month,
    required this.winRate,
    required this.matches,
    required this.wins,
    required this.losses,
  });

  final int year;
  final int month;
  final double winRate;
  final int matches;
  final int wins;
  final int losses;
}

class HomeOverviewSnapshot {
  const HomeOverviewSnapshot({
    this.activeTournament,
    this.latestTournament,
    this.cards = const [],
    this.winnerName,
    this.winnerId,
    this.winRateSeries = const [],
  });

  final HomeOverviewActiveTournament? activeTournament;
  final HomeOverviewCard? latestTournament;
  final List<HomeOverviewCard> cards;

  /// Winner of the most recent completed tournament shown in the card.
  final String? winnerName;
  final String? winnerId;
  final List<HomeWinRatePoint> winRateSeries;
}

class HomeOverviewService {
  const HomeOverviewService(this._source);

  final HomeOverviewDataSource _source;

  Future<HomeOverviewSnapshot> load() async {
    final tournaments = await _source.loadTournaments();
    final active =
        tournaments
            .where(
              (tournament) =>
                  tournament.startedAt != null && tournament.finishedAt == null,
            )
            .toList()
          ..sort(
            (left, right) =>
                _activityDate(right).compareTo(_activityDate(left)),
          );
    final matchesByTournament = {
      for (final tournament in tournaments)
        tournament.id: TournamentTiming.matches(tournament),
    };
    final completed = _completedTournaments(tournaments, matchesByTournament);
    final playerIds = tournaments
        .expand((tournament) => tournament.players)
        .expand((player) => player.individuals)
        .map((player) => player.profileId)
        .whereType<String>()
        .toSet();
    final source = _source;
    final winRateSeries = _winRateSeries(
      source is HomeMonthlyPerformanceDataSource
          ? await source.loadMonthlyPerformances(playerIds, completed)
          : const <PlayerMonthlyPerformance>[],
    );
    HomeOverviewActiveTournament? activeSummary;
    for (final tournament in active) {
      final matches =
          matchesByTournament[tournament.id] ?? const <GroupMatch>[];
      if (_isActive(tournament, matches)) {
        activeSummary = _activeSummary(
          tournament,
          TournamentTiming.scheduledMatches(tournament),
        );
        break;
      }
    }

    HomeOverviewSnapshot finish({
      required HomeOverviewActiveTournament? activeTournament,
      required List<CreatedTournament> recentTournaments,
      required List<CreatedTournament> rankingTournaments,
      required LocalRanking ranking,
      required LocalEloSnapshot? elo,
    }) {
      final winnerTournament = _completedTournaments(
        recentTournaments,
        matchesByTournament,
      ).lastOrNull;
      final winnerName = winnerTournament == null
          ? null
          : TournamentWinner.name(winnerTournament);
      final winnerId = winnerTournament == null
          ? null
          : TournamentWinner.profileId(winnerTournament);
      final cards = _cards(
        ranking,
        recentTournaments,
        rankingTournaments,
        matchesByTournament,
        elo,
        winnerName,
      );
      return HomeOverviewSnapshot(
        activeTournament: activeTournament,
        latestTournament: cards[1],
        cards: cards,
        winnerName: winnerName,
        winnerId: winnerId,
        winRateSeries: winRateSeries,
      );
    }

    if (activeSummary != null) {
      return finish(
        activeTournament: activeSummary,
        recentTournaments: tournaments,
        rankingTournaments: tournaments,
        ranking: const LocalRanking(
          id: 'all-tournaments',
          name: 'Alle Turniere',
        ),
        elo: null,
      );
    }

    final rankings = await _source.loadRankings();
    if (rankings.isEmpty) {
      return finish(
        activeTournament: null,
        recentTournaments: tournaments,
        rankingTournaments: tournaments,
        ranking: const LocalRanking(
          id: 'all-tournaments',
          name: 'Alle Turniere',
        ),
        elo: null,
      );
    }
    final ranking = rankings.firstWhere(
      (item) => item.isDefaultForStatistics,
      orElse: () => rankings.first,
    );
    final eligible =
        tournaments
            .where(
              (tournament) =>
                  tournament.countsForRanking &&
                  tournament.rankingIds.contains(ranking.id) &&
                  ranking.includesTournamentDate(tournament.effectiveDate),
            )
            .toList()
          ..sort(_compareTournaments);
    final elo = await _source.loadEloSnapshot(ranking, eligible);
    return finish(
      activeTournament: null,
      recentTournaments: eligible.isEmpty ? tournaments : eligible,
      rankingTournaments: eligible,
      ranking: ranking,
      elo: elo,
    );
  }

  List<HomeWinRatePoint> _winRateSeries(
    List<PlayerMonthlyPerformance> performances,
  ) {
    final byMonth = <(int, int), ({int wins, int losses, int matches})>{};
    for (final entry in performances) {
      if (entry.matches <= 0) continue;
      final period = (entry.year, entry.month);
      final totals = byMonth.putIfAbsent(
        period,
        () => (wins: 0, losses: 0, matches: 0),
      );
      byMonth[period] = (
        wins: totals.wins + entry.wins,
        losses: totals.losses + entry.losses,
        matches: totals.matches + entry.matches,
      );
    }
    final periods = byMonth.keys.toList()
      ..sort((left, right) {
        final byYear = left.$1.compareTo(right.$1);
        return byYear != 0 ? byYear : left.$2.compareTo(right.$2);
      });
    return [
      for (final period in periods)
        HomeWinRatePoint(
          year: period.$1,
          month: period.$2,
          winRate: byMonth[period]!.wins * 100 / byMonth[period]!.matches,
          matches: byMonth[period]!.matches,
          wins: byMonth[period]!.wins,
          losses: byMonth[period]!.losses,
        ),
    ];
  }

  List<HomeOverviewCard> _cards(
    LocalRanking ranking,
    List<CreatedTournament> recentTournaments,
    List<CreatedTournament> rankingTournaments,
    Map<String, List<GroupMatch>> matchesByTournament,
    LocalEloSnapshot? elo,
    String? winnerName,
  ) => [
    _recentMatchesCard(recentTournaments, matchesByTournament, elo: elo),
    _lastTournamentCard(recentTournaments, matchesByTournament, winnerName),
    _rankingSummaryCard(ranking, rankingTournaments, matchesByTournament),
    _rankingChangesCard(ranking, rankingTournaments, matchesByTournament, elo),
    _bestPerformanceCard(rankingTournaments, matchesByTournament),
    _longestStreakCard(rankingTournaments, matchesByTournament),
    _recentAchievementsCard(rankingTournaments, matchesByTournament),
  ];

  HomeOverviewActiveTournament _activeSummary(
    CreatedTournament tournament,
    List<GroupMatch> allMatches,
  ) {
    final matches = allMatches;
    final played = matches.where((match) => match.hasResult).length;
    return HomeOverviewActiveTournament(
      id: tournament.id,
      name: tournament.name,
      participantCount: tournament.players
          .expand((player) => player.individuals)
          .map((player) => player.profileId ?? player.name)
          .toSet()
          .length,
      playedMatches: played,
      totalMatches: matches.length,
      openMatches: matches.length - played,
    );
  }

  HomeOverviewCard _recentMatchesCard(
    List<CreatedTournament> tournaments,
    Map<String, List<GroupMatch>> matchesByTournament, {
    LocalEloSnapshot? elo,
  }) {
    final recent = <({CreatedTournament tournament, GroupMatch match})>[];
    for (final tournament in tournaments) {
      for (final match in matchesByTournament[tournament.id] ?? const []) {
        if (match.hasResult && match.winner != null) {
          recent.add((tournament: tournament, match: match));
        }
      }
    }
    recent.sort((left, right) {
      final date = _matchDate(
        right.tournament,
        right.match,
      ).compareTo(_matchDate(left.tournament, left.match));
      return date != 0
          ? date
          : _compareTournaments(right.tournament, left.tournament);
    });
    final calculator = const LocalEloCalculator();
    return HomeOverviewCard(
      title: 'Letzte 3 Begegnungen',
      icon: 'sports',
      lines: [
        for (final entry in recent.take(3))
          _matchDescription(entry.tournament, entry.match, elo, calculator),
        if (recent.isEmpty) 'Noch keine abgeschlossenen Begegnungen.',
      ],
    );
  }

  String _matchDescription(
    CreatedTournament tournament,
    GroupMatch match,
    LocalEloSnapshot? elo,
    LocalEloCalculator calculator,
  ) {
    final winner = match.winner!;
    final loser = match.loser;
    final score =
        '${winnerFirstScore(match)}${match.hasSetScore ? ' Sets' : ''}';
    final key = calculator.matchKey(tournament, match);
    final delta = key == null ? null : elo?.matchDeltas[key];
    final winnerDelta = winner == match.homePlayer ? delta?.home : delta?.away;
    final loserDelta = loser == match.homePlayer ? delta?.home : delta?.away;
    final eloText = winnerDelta == null || loserDelta == null
        ? ''
        : ' · ${_signed(winnerDelta)} / ${_signed(loserDelta)} ELO';
    return '${winner.name} besiegte ${loser?.name ?? 'Gegner'} in ${tournament.name} '
        '($score$eloText)';
  }

  HomeOverviewCard _lastTournamentCard(
    List<CreatedTournament> tournaments,
    Map<String, List<GroupMatch>> matchesByTournament,
    String? winnerName,
  ) {
    final completed =
        tournaments
            .where(
              (tournament) => _isCompleted(
                tournament,
                matchesByTournament[tournament.id] ?? const [],
              ),
            )
            .toList()
          ..sort(_compareTournaments);
    if (completed.isEmpty) {
      return const HomeOverviewCard(
        title: 'Letztes Turnier',
        icon: 'emoji_events',
        lines: ['Noch kein abgeschlossenes Turnier.'],
      );
    }
    final tournament = completed.last;
    final stats = _playerStats(
      tournament,
      matchesByTournament[tournament.id] ?? const [],
    );
    final ranking = _finalStageRanking(tournament)
        .map((player) => stats[player.name])
        .whereType<_HomePlayerStats>()
        .toList();
    final rankedNames = ranking.map((entry) => entry.player.name).toSet();
    final remaining =
        stats.values
            .where((entry) => !rankedNames.contains(entry.player.name))
            .toList()
          ..sort((left, right) {
            final wins = right.wins.compareTo(left.wins);
            if (wins != 0) return wins;
            final difference = right.legDifference.compareTo(
              left.legDifference,
            );
            if (difference != 0) return difference;
            final legs = right.legsFor.compareTo(left.legsFor);
            if (legs != 0) return legs;
            return left.player.name.compareTo(right.player.name);
          });
    ranking.addAll(remaining);
    final podium = ranking.take(3).toList();
    return HomeOverviewCard(
      title: 'Letztes Turnier · ${tournament.name}',
      icon: 'emoji_events',
      lines: [
        for (var index = 0; index < podium.length; index++)
          '${index + 1}. ${podium[index].player.name} (${podium[index].wins}:${podium[index].losses})',
        'Datum: ${_formatDate(tournament.effectiveDate)}',
        if (winnerName != null && winnerName.trim().isNotEmpty)
          'Sieger: $winnerName',
        if (podium.isEmpty) 'Noch keine Ergebnisse eingetragen.',
      ],
    );
  }

  String _formatDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}.${value.year}';

  HomeOverviewCard _rankingSummaryCard(
    LocalRanking ranking,
    List<CreatedTournament> tournaments,
    Map<String, List<GroupMatch>> matchesByTournament,
  ) {
    final matches = [
      for (final tournament in tournaments)
        for (final match in matchesByTournament[tournament.id] ?? const [])
          if (match.countsForStatistics) match,
    ];
    final legs = matches.fold<int>(
      0,
      (sum, match) =>
          (sum + (match.homeLegs ?? 0) + (match.awayLegs ?? 0)).toInt(),
    );
    final scores180 = matches
        .expand((match) => match.bestPerformances)
        .where(
          (performance) =>
              performance.normalizedType == BestPerformanceType.score180,
        )
        .length;
    final highFinish = matches
        .expand((match) => match.bestPerformances)
        .where(
          (performance) => performance.type == BestPerformanceType.highFinish,
        )
        .fold<int>(
          0,
          (best, item) =>
              item.value != null && item.value! > best ? item.value! : best,
        );
    return HomeOverviewCard(
      title: 'Zusammenfassung · ${ranking.name}',
      icon: 'leaderboard',
      lines: [
        '${tournaments.length} Turniere · ${matches.length} Begegnungen',
        '$legs Legs · $scores180 geworfene 180er',
        if (highFinish > 0) 'Höchstes Finish: $highFinish',
      ],
    );
  }

  HomeOverviewCard _rankingChangesCard(
    LocalRanking ranking,
    List<CreatedTournament> tournaments,
    Map<String, List<GroupMatch>> matchesByTournament,
    LocalEloSnapshot? elo,
  ) {
    if (elo == null || tournaments.isEmpty) {
      return HomeOverviewCard(
        title: 'Ranglistenänderungen',
        icon: 'swap_vert',
        lines: ['${ranking.name}: Noch keine ELO-Bewegungen verfügbar.'],
      );
    }
    final latestId = tournaments.reversed
        .where(
          (tournament) => (matchesByTournament[tournament.id] ?? const []).any(
            (match) => match.hasResult,
          ),
        )
        .map((tournament) => tournament.id)
        .firstOrNull;
    if (latestId == null) {
      return HomeOverviewCard(
        title: 'Ranglistenänderungen',
        icon: 'swap_vert',
        lines: ['${ranking.name}: Noch keine Ranglistenänderungen.'],
      );
    }
    final beforeRating = <String, int>{
      for (final player in elo.entries)
        player.id: _ratingBeforeTournament(
          elo.history[player.id] ?? [],
          latestId,
          player.rating,
        ),
    };
    final before = _places(beforeRating);
    final after = _places({
      for (final player in elo.entries) player.id: player.rating,
    });
    final moved =
        [
          for (final entry in after.entries)
            if (before[entry.key] != null && before[entry.key] != entry.value)
              (id: entry.key, from: before[entry.key]!, to: entry.value),
        ]..sort((left, right) {
          final leftGain = left.from - left.to;
          final rightGain = right.from - right.to;
          return rightGain.compareTo(leftGain);
        });
    final up = moved.where((item) => item.to < item.from).firstOrNull;
    final down = moved.where((item) => item.to > item.from).lastOrNull;
    return HomeOverviewCard(
      title: 'Ranglistenänderungen',
      icon: 'swap_vert',
      lines: [
        if (up != null)
          '↑ ${_playerName(elo, up.id)} · Platz ${up.from} → ${up.to}',
        if (down != null)
          '↓ ${_playerName(elo, down.id)} · Platz ${down.from} → ${down.to}',
        if (up == null && down == null) 'Nach dem letzten Turnier unverändert.',
      ],
    );
  }

  HomeOverviewCard _bestPerformanceCard(
    List<CreatedTournament> tournaments,
    Map<String, List<GroupMatch>> matchesByTournament,
  ) {
    final performances = [
      for (final tournament in tournaments)
        for (final match in matchesByTournament[tournament.id] ?? const [])
          for (final performance in match.bestPerformances)
            (
              tournament: tournament,
              performance: performance,
              date: _matchDate(tournament, match),
            ),
    ];
    final highFinish =
        performances
            .where(
              (item) => item.performance.type == BestPerformanceType.highFinish,
            )
            .toList()
          ..sort(
            (left, right) => (right.performance.value ?? 0).compareTo(
              left.performance.value ?? 0,
            ),
          );
    final shortLegs =
        performances
            .where(
              (item) =>
                  item.performance.normalizedType ==
                  BestPerformanceType.shortLeg,
            )
            .toList()
          ..sort(
            (left, right) => (left.performance.value ?? 999).compareTo(
              right.performance.value ?? 999,
            ),
          );
    final bestLeg = shortLegs.firstOrNull;
    final darts = bestLeg?.performance.value;
    final average = darts == null || darts == 0
        ? null
        : (501 / darts * 3).toStringAsFixed(1);
    final latest = [...performances]
      ..sort((left, right) => right.date.compareTo(left.date));
    return HomeOverviewCard(
      title: 'Kürzliche Bestleistungen',
      icon: 'military_tech',
      lines: [
        if (highFinish.isNotEmpty)
          'Höchstes Finish: ${highFinish.first.performance.value ?? '–'} · ${highFinish.first.performance.playerName}',
        if (bestLeg != null)
          'Bestes Leg: ${bestLeg.performance.details ?? '$darts Darts'}'
              '${average == null ? '' : ' · Ø $average'} · ${bestLeg.performance.playerName}',
        if (latest.isNotEmpty)
          '${latest.first.performance.playerName}: ${latest.first.performance.label} im ${latest.first.tournament.name}',
        if (performances.isEmpty) 'Noch keine Bestleistungen erfasst.',
      ],
    );
  }

  HomeOverviewCard _longestStreakCard(
    List<CreatedTournament> tournaments,
    Map<String, List<GroupMatch>> matchesByTournament,
  ) {
    final events = <({DateTime date, int order, GroupMatch match})>[];
    var order = 0;
    for (final tournament in tournaments) {
      for (final match in matchesByTournament[tournament.id] ?? const []) {
        if (match.countsForStatistics &&
            match.winner != null &&
            match.loser != null) {
          events.add((
            date: _matchDate(tournament, match),
            order: order++,
            match: match,
          ));
        }
      }
    }
    events.sort((left, right) {
      final date = left.date.compareTo(right.date);
      return date != 0 ? date : left.order.compareTo(right.order);
    });
    final current = <String, int>{};
    var bestName = '';
    var best = 0;
    for (final event in events) {
      final winner = event.match.winner!;
      final loser = event.match.loser!;
      final winnerId = winner.profileId ?? winner.name;
      final loserId = loser.profileId ?? loser.name;
      final streak = (current[winnerId] ?? 0) + 1;
      current[winnerId] = streak;
      current[loserId] = 0;
      if (streak > best) {
        best = streak;
        bestName = winner.name;
      }
    }
    return HomeOverviewCard(
      title: 'Längste Siegesserie',
      icon: 'local_fire_department',
      lines: [
        if (best > 0)
          '$best Siege in Folge · $bestName'
        else
          'Noch keine Siegesserie erfasst.',
      ],
    );
  }

  HomeOverviewCard _recentAchievementsCard(
    List<CreatedTournament> tournaments,
    Map<String, List<GroupMatch>> matchesByTournament,
  ) {
    final completed =
        tournaments
            .where(
              (tournament) => _isCompleted(
                tournament,
                matchesByTournament[tournament.id] ?? const [],
              ),
            )
            .toList()
          ..sort(_compareTournaments);
    final latest = completed.isEmpty ? null : completed.last;
    final notices = latest == null
        ? const <TournamentAchievementNotice>[]
        : [
            for (final match in matchesByTournament[latest.id] ?? const [])
              ...match.achievementNotifications,
          ];
    return HomeOverviewCard(
      title: 'Zuletzt erfüllte Achievements',
      icon: 'workspace_premium',
      lines: [
        for (final notice in notices.reversed.take(3))
          '${notice.playerName}: ${notice.achievementName}',
        if (notices.isEmpty) 'Im letzten Turnier keine neuen Achievements.',
      ],
    );
  }

  Map<String, _HomePlayerStats> _playerStats(
    CreatedTournament tournament,
    List<GroupMatch> matches,
  ) {
    final stats = {
      for (final player in tournament.players)
        for (final individual in player.individuals)
          individual.name: _HomePlayerStats(individual),
    };
    for (final match in matches) {
      if (!match.countsForStatistics ||
          match.winner == null ||
          match.loser == null) {
        continue;
      }
      final winner = stats[match.winner!.name];
      final loser = stats[match.loser!.name];
      if (winner == null || loser == null) continue;
      final winnerLegs = match.homePlayer == match.winner
          ? match.homeLegs ?? 0
          : match.awayLegs ?? 0;
      final loserLegs = match.homePlayer == match.loser
          ? match.homeLegs ?? 0
          : match.awayLegs ?? 0;
      winner.wins++;
      winner.legsFor += winnerLegs;
      winner.legsAgainst += loserLegs;
      loser.losses++;
      loser.legsFor += loserLegs;
      loser.legsAgainst += winnerLegs;
    }
    return stats;
  }

  /// Das Podium folgt dem finalen KO-Baum, nicht der Anzahl aller Siege.
  /// Sonst kann ein Finalverlierer mit vielen Gruppensiegen vor dem
  /// Finalsieger stehen.
  List<TournamentPlayer> _finalStageRanking(CreatedTournament tournament) {
    final finalStage = tournament.runStages.isEmpty
        ? null
        : tournament.runStages.last;
    if (finalStage is! KnockoutTournamentRunStage) return const [];
    return PlacementEngine.applyRanking(
      _knockoutRanking(finalStage),
      finalStage.placementMatches,
    );
  }

  List<TournamentPlayer> _knockoutRanking(KnockoutTournamentRunStage stage) {
    if (stage.isKratzer) {
      final players = [...stage.participants];
      players.sort((a, b) {
        final lives = stage
            .livesRemainingFor(b)
            .compareTo(stage.livesRemainingFor(a));
        return lives != 0 ? lives : a.name.compareTo(b.name);
      });
      return players;
    }

    final ranking = <TournamentPlayer>[];
    void addUnique(List<TournamentPlayer> target, TournamentPlayer? player) {
      if (player != null && !target.any((entry) => entry.name == player.name)) {
        target.add(player);
      }
    }

    if (stage.eliminationLossLimit > 1) {
      final losses = <String, int>{};
      final lastRound = <String, int>{};
      final players = <TournamentPlayer>[];
      for (final round in stage.rounds) {
        for (final match in round) {
          addUnique(players, match.homePlayer);
          addUnique(players, match.awayPlayer);
          if (!match.hasResult) continue;
          final loser = match.loser;
          final winner = match.winner;
          if (loser != null) {
            losses[loser.name] = (losses[loser.name] ?? 0) + 1;
            lastRound[loser.name] = match.round;
          }
          if (winner != null) lastRound[winner.name] = match.round;
        }
      }
      players.sort((a, b) {
        final lossComparison = (losses[a.name] ?? 0).compareTo(
          losses[b.name] ?? 0,
        );
        if (lossComparison != 0) return lossComparison;
        final roundComparison = (lastRound[b.name] ?? 0).compareTo(
          lastRound[a.name] ?? 0,
        );
        if (roundComparison != 0) return roundComparison;
        return a.name.compareTo(b.name);
      });
      if (stage.finalEndsTournament &&
          stage.rounds.isNotEmpty &&
          stage.rounds.last.length == 1 &&
          stage.rounds.last.single.hasResult) {
        final last = stage.rounds.last.single;
        players.removeWhere(
          (player) =>
              player.name == last.winner?.name ||
              player.name == last.loser?.name,
        );
        players.insertAll(0, [
          if (last.winner != null) last.winner!,
          if (last.loser != null) last.loser!,
        ]);
      }
      return PlacementEngine.applyRanking(players, stage.placementMatches);
    }

    if (stage.rounds.isNotEmpty) {
      final finalRound = stage.rounds.last;
      if (finalRound.length == 1) {
        addUnique(ranking, finalRound.first.winner);
        addUnique(ranking, finalRound.first.loser);
      } else {
        for (final match in finalRound) {
          addUnique(ranking, match.winner);
        }
      }
      for (final match in stage.placementMatches.where(
        (match) => match.label == 'Spiel um Platz 3',
      )) {
        addUnique(ranking, match.winner);
        addUnique(ranking, match.loser);
      }
      for (
        var roundIndex = stage.rounds.length - 2;
        roundIndex >= 0;
        roundIndex--
      ) {
        for (final match in stage.rounds[roundIndex]) {
          addUnique(ranking, match.loser);
        }
      }
    }
    return ranking;
  }

  int _ratingBeforeTournament(
    List<LocalEloHistoryItem> history,
    String tournamentId,
    int fallback,
  ) {
    final entries = history
        .where((item) => item.tournamentId == tournamentId)
        .toList();
    if (entries.isEmpty) return fallback;
    entries.sort((left, right) => left.playedAt.compareTo(right.playedAt));
    return entries.first.ratingBefore;
  }

  Map<String, int> _places(Map<String, int> ratings) {
    final sorted = ratings.entries.toList()
      ..sort((left, right) {
        final rating = right.value.compareTo(left.value);
        return rating != 0 ? rating : left.key.compareTo(right.key);
      });
    return {
      for (var index = 0; index < sorted.length; index++)
        sorted[index].key: index + 1,
    };
  }

  String _playerName(LocalEloSnapshot elo, String id) =>
      elo.entries.where((player) => player.id == id).firstOrNull?.name ?? id;

  bool _isActive(CreatedTournament tournament, List<GroupMatch> allMatches) {
    if (tournament.finishedAt != null || tournament.startedAt == null) {
      return false;
    }
    final matches = allMatches.where(
      (match) => match.hasPlayers && !match.isAnnulled,
    );
    return matches.isEmpty || matches.any((match) => !match.isResolved);
  }

  bool _isCompleted(CreatedTournament tournament, List<GroupMatch> allMatches) {
    if (tournament.finishedAt != null) return true;
    final matches = allMatches
        .where((match) => match.hasPlayers && !match.isAnnulled)
        .toList();
    return matches.isNotEmpty && matches.every((match) => match.isResolved);
  }

  List<CreatedTournament> _completedTournaments(
    List<CreatedTournament> tournaments,
    Map<String, List<GroupMatch>> matchesByTournament,
  ) =>
      tournaments
          .where(
            (tournament) => _isCompleted(
              tournament,
              matchesByTournament[tournament.id] ?? const [],
            ),
          )
          .toList()
        ..sort(_compareTournaments);

  DateTime _activityDate(CreatedTournament tournament) =>
      tournament.startedAt ?? tournament.updatedAt;

  DateTime _matchDate(CreatedTournament tournament, GroupMatch match) =>
      match.finishedAt ?? match.startedAt ?? tournament.effectiveDate;

  int _compareTournaments(CreatedTournament left, CreatedTournament right) {
    final date = left.effectiveDate.compareTo(right.effectiveDate);
    return date != 0 ? date : left.id.compareTo(right.id);
  }

  String _signed(int value) => value > 0 ? '+$value' : '$value';
}

class _HomePlayerStats {
  _HomePlayerStats(this.player);

  final TournamentPlayer player;
  int wins = 0;
  int losses = 0;
  int legsFor = 0;
  int legsAgainst = 0;

  int get legDifference => legsFor - legsAgainst;
}
