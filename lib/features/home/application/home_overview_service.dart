import '../../rankings/application/local_ranking_elo_service.dart';
import '../../rankings/domain/local_elo_calculator.dart';
import '../../rankings/domain/local_ranking.dart';
import '../../statistics/domain/best_performance.dart';
import '../../tournaments/data/app_database.dart';
import '../../tournaments/data/tournament_storage.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../../tournaments/application/tournament_timing.dart';

abstract interface class HomeOverviewDataSource {
  Future<List<CreatedTournament>> loadTournaments();
  Future<List<LocalRanking>> loadRankings();
  Future<LocalEloSnapshot?> loadEloSnapshot(
    LocalRanking ranking,
    List<CreatedTournament> tournaments,
  );
}

class LocalHomeOverviewDataSource implements HomeOverviewDataSource {
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

class HomeOverviewSnapshot {
  const HomeOverviewSnapshot({
    this.activeTournament,
    this.latestTournament,
    this.cards = const [],
  });

  final HomeOverviewActiveTournament? activeTournament;
  final HomeOverviewCard? latestTournament;
  final List<HomeOverviewCard> cards;
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
    HomeOverviewActiveTournament? activeSummary;
    for (final tournament in active) {
      final matches =
          matchesByTournament[tournament.id] ?? const <GroupMatch>[];
      if (_isActive(tournament, matches)) {
        activeSummary = _activeSummary(tournament, matches);
        break;
      }
    }
    if (activeSummary != null) {
      final cards = _cards(
        const LocalRanking(id: 'all-tournaments', name: 'Alle Turniere'),
        tournaments,
        tournaments,
        matchesByTournament,
        null,
      );
      return HomeOverviewSnapshot(
        activeTournament: activeSummary,
        latestTournament: cards[1],
        cards: cards,
      );
    }

    final rankings = await _source.loadRankings();
    if (rankings.isEmpty) {
      final cards = _cards(
        const LocalRanking(id: 'all-tournaments', name: 'Alle Turniere'),
        tournaments,
        tournaments,
        matchesByTournament,
        null,
      );
      return HomeOverviewSnapshot(
        activeTournament: activeSummary,
        latestTournament: cards[1],
        cards: cards,
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
    final cards = _cards(
      ranking,
      eligible.isEmpty ? tournaments : eligible,
      eligible,
      matchesByTournament,
      elo,
    );
    return HomeOverviewSnapshot(
      activeTournament: activeSummary,
      latestTournament: cards[1],
      cards: cards,
    );
  }

  List<HomeOverviewCard> _cards(
    LocalRanking ranking,
    List<CreatedTournament> recentTournaments,
    List<CreatedTournament> rankingTournaments,
    Map<String, List<GroupMatch>> matchesByTournament,
    LocalEloSnapshot? elo,
  ) => [
    _recentMatchesCard(recentTournaments, matchesByTournament, elo: elo),
    _lastTournamentCard(recentTournaments, matchesByTournament),
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
    final matches = allMatches
        .where((match) => match.hasPlayers && !match.isAnnulled)
        .toList();
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
        '${match.homeScore ?? 0}:${match.awayScore ?? 0}${match.hasSetScore ? ' Sets' : ''}';
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
    final ranking = stats.values.toList()
      ..sort((left, right) {
        final wins = right.wins.compareTo(left.wins);
        if (wins != 0) return wins;
        return right.legsFor.compareTo(left.legsFor);
      });
    final podium = ranking.take(3).toList();
    return HomeOverviewCard(
      title: 'Letztes Turnier · ${tournament.name}',
      icon: 'emoji_events',
      lines: [
        for (var index = 0; index < podium.length; index++)
          '${index + 1}. ${podium[index].player.name} (${podium[index].wins}:${podium[index].losses})',
        'Datum: ${_formatDate(tournament.effectiveDate)}',
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
      winner.wins++;
      winner.legsFor += match.homePlayer == match.winner
          ? match.homeLegs ?? 0
          : match.awayLegs ?? 0;
      loser.losses++;
      loser.legsFor += match.homePlayer == match.loser
          ? match.homeLegs ?? 0
          : match.awayLegs ?? 0;
    }
    return stats;
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
}
