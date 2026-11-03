import 'dart:io';

import 'package:dart_tournament_manager/features/rankings/domain/local_elo_calculator.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/statistics/domain/player_monthly_performance.dart';
import 'package:dart_tournament_manager/features/tournaments/application/player_insights_service.dart';
import 'package:dart_tournament_manager/features/tournaments/application/player_insight_preferences.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/player_insight.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _date = DateTime.utc(2026, 3, 15);

TournamentPlayer _player(String id) =>
    TournamentPlayer(profileId: id, name: id.toUpperCase(), isGenerated: false);

CreatedTournament _tournament({
  required String id,
  required List<TournamentPlayer> players,
  List<GroupMatch> matches = const [],
  String name = 'Testturnier',
  DateTime? date,
  DateTime? finishedAt,
  TournamentGameFormat format = const TournamentGameFormat(),
  List<TournamentRunStage>? runStages,
  List<TournamentStage>? stages,
  List<String> rankingIds = const [],
}) {
  final createdAt = date ?? _date;
  final groupStage = GroupTournamentRunStage(
    name: 'Gruppenphase',
    groupPlayType: 'round_robin',
    groups: [
      TournamentGroup(
        name: 'Gruppe A',
        playType: 'round_robin',
        players: players,
        matches: matches,
      ),
    ],
    qualificationPlan: null,
    tieBreakers: const [],
  );
  return CreatedTournament(
    id: id,
    name: name,
    createdAt: createdAt,
    tournamentDate: createdAt,
    finishedAt: finishedAt,
    players: players,
    stages:
        stages ??
        [
          TournamentStage(
            name: 'Gruppenphase',
            type: 'groups',
            gameFormat: format,
          ),
        ],
    runStages: runStages ?? [groupStage],
    rankingIds: rankingIds,
  );
}

GroupMatch _match(
  TournamentPlayer home,
  TournamentPlayer away, {
  required int homeLegs,
  required int awayLegs,
  required DateTime date,
  int round = 1,
  int? homeSets,
  int? awaySets,
}) => GroupMatch(
  homePlayer: home,
  awayPlayer: away,
  round: round,
  homeLegs: homeLegs,
  awayLegs: awayLegs,
  homeSets: homeSets,
  awaySets: awaySets,
  finishedAt: date,
);

PlayerInsightEngine _engine() => PlayerInsightEngine();

Map<String, List<PlayerInsight>> _calculate({
  required CreatedTournament current,
  required List<CreatedTournament> history,
  Map<String, List<PlayerMonthlyPerformance>> monthlyEntries = const {},
  LocalRanking? ranking,
  LocalEloSnapshot? snapshot,
}) => _engine().calculate(
  tournament: current,
  history: history,
  monthlyEntries: monthlyEntries,
  eloRanking: ranking,
  eloSnapshot: snapshot,
  now: _date,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'streak, last-leg, and rising-star insights use recent match history',
    () {
      final home = _player('home');
      final away = _player('away');
      final history = [
        for (var index = 0; index < 5; index++)
          _tournament(
            id: 'win-$index',
            players: [home, away],
            date: DateTime.utc(2026, 3, index + 1),
            format: const TournamentGameFormat(bestOfLegs: 5),
            matches: [
              _match(
                home,
                away,
                homeLegs: 3,
                awayLegs: 2,
                date: DateTime.utc(2026, 3, index + 1),
              ),
            ],
          ),
      ];
      final current = _tournament(
        id: 'current',
        players: [home, away],
        date: _date,
        format: const TournamentGameFormat(bestOfLegs: 5),
      );

      final results = _calculate(
        current: current,
        history: history,
        monthlyEntries: {
          'home': const [
            PlayerMonthlyPerformance(
              playerId: 'home',
              year: 2026,
              month: 2,
              weightedLegs: 10,
              average: 55,
            ),
            PlayerMonthlyPerformance(
              playerId: 'home',
              year: 2026,
              month: 3,
              weightedLegs: 10,
              average: 60,
            ),
          ],
        },
      );

      final homeTypes = results['home']!.map((insight) => insight.type).toSet();
      final awayTypes = results['away']!.map((insight) => insight.type).toSet();
      expect(
        homeTypes,
        containsAll({
          PlayerInsightType.unstoppable,
          PlayerInsightType.risingStar,
          PlayerInsightType.lastLegStanding,
        }),
      );
      expect(homeTypes, isNot(contains(PlayerInsightType.hotStreak)));
      expect(homeTypes, isNot(contains(PlayerInsightType.momentum)));
      expect(awayTypes, contains(PlayerInsightType.coldStreak));
      expect(awayTypes, contains(PlayerInsightType.lastLegStanding));
    },
  );

  test('unstoppable replaces hot streak and momentum for five wins', () {
    final player = _player('player');
    final opponent = _player('opponent');
    final history = [
      for (var index = 0; index < 5; index++)
        _tournament(
          id: 'win-$index',
          players: [player, opponent],
          date: DateTime.utc(2026, 3, index + 1),
          matches: [
            _match(
              player,
              opponent,
              homeLegs: 3,
              awayLegs: 0,
              date: DateTime.utc(2026, 3, index + 1),
            ),
          ],
        ),
    ];

    final types = _calculate(
      current: _tournament(id: 'current', players: [player, opponent]),
      history: history,
    )['player']!.map((insight) => insight.type).toSet();

    expect(types, contains(PlayerInsightType.unstoppable));
    expect(types, isNot(contains(PlayerInsightType.hotStreak)));
    expect(types, isNot(contains(PlayerInsightType.momentum)));
  });

  test(
    'ranking-dependent insights require a catalog player assigned to the tournament ranking',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'player_insights_ranking_eligibility_test_',
      );
      addTearDown(() => directory.delete(recursive: true));

      final database = LocalAppDatabase(baseDirectory: directory);
      final rankedProfile = await database.createPlayerProfile(
        displayName: 'Ranglistenspieler',
      );
      final unrankedProfile = await database.createPlayerProfile(
        displayName: 'Nicht zugewiesen',
      );
      const ranking = LocalRanking(id: 'insights-ranking', name: 'Rangliste');
      await database.saveLocalRanking(ranking);
      await database.setRankingPlayers(ranking.id, [rankedProfile.id]);

      final ranked = TournamentPlayer(
        profileId: rankedProfile.id,
        name: rankedProfile.displayName,
        isGenerated: false,
      );
      final unranked = TournamentPlayer(
        profileId: unrankedProfile.id,
        name: unrankedProfile.displayName,
        isGenerated: false,
      );
      final historyMatches = [
        for (var index = 0; index < 10; index++)
          _match(
            ranked,
            unranked,
            homeLegs: 1,
            awayLegs: 3,
            date: DateTime.utc(2026, 3, index + 1),
            round: index + 1,
          ),
      ];
      final current = _tournament(
        id: 'ranked-current',
        players: [ranked, unranked],
        matches: historyMatches,
        rankingIds: [ranking.id],
      );
      final service = PlayerInsightsService(
        database: database,
        storage: TournamentStorage(
          file: File('${directory.path}\\tournaments.json'),
        ),
      );

      final insights = await service.calculate(tournament: current, now: _date);

      expect(
        insights[rankedProfile.id]!.map((insight) => insight.type),
        contains(PlayerInsightType.bogeyOpponent),
      );
      expect(
        insights[unrankedProfile.id]!.map((insight) => insight.type),
        isNot(contains(PlayerInsightType.bogeyOpponent)),
      );

      final preferences = PlayerInsightPreferencesStorage();
      await preferences.save(
        (await preferences.load()).withEnabled(
          PlayerInsightType.bogeyOpponent,
          false,
        ),
      );
      final filtered = await service.calculate(tournament: current, now: _date);
      expect(
        filtered.values.expand((playerInsights) => playerInsights),
        isNot(
          contains(
            isA<PlayerInsight>().having(
              (insight) => insight.type,
              'type',
              PlayerInsightType.bogeyOpponent,
            ),
          ),
        ),
      );
    },
  );

  test('rising star ignores months with fewer than ten weighted legs', () {
    final player = _player('player');
    final current = _tournament(id: 'current', players: [player], date: _date);

    final results = _calculate(
      current: current,
      history: [current],
      monthlyEntries: {
        'player': const [
          PlayerMonthlyPerformance(
            playerId: 'player',
            year: 2026,
            month: 2,
            weightedLegs: 10,
            average: 55,
          ),
          PlayerMonthlyPerformance(
            playerId: 'player',
            year: 2026,
            month: 3,
            weightedLegs: 9,
            average: 70,
          ),
        ],
      },
    );

    expect(
      results['player']!.map((insight) => insight.type),
      isNot(contains(PlayerInsightType.risingStar)),
    );
  });

  test('last-leg insight handles best-of sets formats', () {
    final home = _player('home');
    final away = _player('away');
    final history = [
      for (var index = 0; index < 5; index++)
        _tournament(
          id: 'sets-$index',
          players: [home, away],
          date: DateTime.utc(2026, 3, index + 1),
          format: const TournamentGameFormat(bestOfSets: 3, bestOfLegs: 3),
          matches: [
            _match(
              home,
              away,
              homeLegs: 5,
              awayLegs: 4,
              homeSets: 2,
              awaySets: 1,
              date: DateTime.utc(2026, 3, index + 1),
            ),
          ],
        ),
    ];
    final current = _tournament(
      id: 'current',
      players: [home, away],
      date: _date,
      format: const TournamentGameFormat(bestOfSets: 3, bestOfLegs: 3),
    );

    final results = _calculate(current: current, history: history);

    expect(
      results['home']!.map((insight) => insight.type),
      contains(PlayerInsightType.lastLegStanding),
    );
  });

  test('last-leg insight counts three deciding legs among the last five', () {
    final home = _player('home');
    final away = _player('away');
    final history = [
      for (var index = 0; index < 5; index++)
        _tournament(
          id: 'best-of-three-$index',
          players: [home, away],
          date: DateTime.utc(2026, 3, index + 1),
          format: const TournamentGameFormat(bestOfLegs: 3),
          matches: [
            _match(
              home,
              away,
              homeLegs: 2,
              awayLegs: index < 3 ? 1 : 0,
              date: DateTime.utc(2026, 3, index + 1),
            ),
          ],
        ),
    ];
    final current = _tournament(
      id: 'current',
      players: [home, away],
      date: _date,
    );

    final results = _calculate(current: current, history: history);

    expect(
      results['home']!.map((insight) => insight.type),
      contains(PlayerInsightType.lastLegStanding),
    );
  });

  test(
    'direct-duel insights use the latest ten and require prior losses for revenge',
    () {
      final home = _player('home');
      final away = _player('away');
      final history = [
        for (var index = 0; index < 10; index++)
          _tournament(
            id: 'duel-$index',
            players: [home, away],
            date: DateTime.utc(2026, 2, index + 1),
            matches: [
              _match(
                index == 9 ? home : away,
                index == 9 ? away : home,
                homeLegs: 2,
                awayLegs: 0,
                date: DateTime.utc(2026, 2, index + 1),
              ),
            ],
          ),
      ];
      final current = _tournament(
        id: 'current',
        players: [home, away],
        date: _date,
      );
      final results = _calculate(current: current, history: history);

      final homeInsights = results['home']!;
      expect(
        homeInsights.map((insight) => insight.type),
        containsAll({
          PlayerInsightType.bogeyOpponent,
          PlayerInsightType.sweetRevenge,
        }),
      );
      expect(
        results['away']!.map((insight) => insight.type),
        isNot(contains(PlayerInsightType.bogeyOpponent)),
      );
      expect(
        homeInsights
            .where((insight) => insight.rivalId == 'away')
            .every((insight) => insight.explanation.contains('AWAY')),
        isTrue,
      );
    },
  );

  test('two wins are not enough for a hot streak', () {
    final home = _player('home');
    final away = _player('away');
    final history = [
      for (var index = 0; index < 2; index++)
        _tournament(
          id: 'two-wins-$index',
          players: [home, away],
          date: DateTime.utc(2026, 3, index + 1),
          matches: [
            _match(
              home,
              away,
              homeLegs: 2,
              awayLegs: 0,
              date: DateTime.utc(2026, 3, index + 1),
            ),
          ],
        ),
    ];
    final current = _tournament(
      id: 'current',
      players: [home, away],
      date: _date,
    );

    final results = _calculate(current: current, history: history);

    expect(
      results['home']!.map((insight) => insight.type),
      isNot(contains(PlayerInsightType.hotStreak)),
    );
    expect(
      results['home']!.map((insight) => insight.type),
      isNot(contains(PlayerInsightType.unstoppable)),
    );
  });

  test('head-to-head thresholds do not assume ten unavailable matches', () {
    final home = _player('home');
    final away = _player('away');
    final history = [
      for (var index = 0; index < 9; index++)
        _tournament(
          id: 'short-duel-$index',
          players: [home, away],
          date: DateTime.utc(2026, 2, index + 1),
          matches: [
            _match(
              index < 7 ? away : home,
              index < 7 ? home : away,
              homeLegs: 2,
              awayLegs: 0,
              date: DateTime.utc(2026, 2, index + 1),
            ),
          ],
        ),
    ];
    final current = _tournament(
      id: 'current',
      players: [home, away],
      date: _date,
    );

    final results = _calculate(current: current, history: history);

    expect(
      results.values
          .expand((items) => items)
          .where((insight) => insight.rivalId != null),
      isEmpty,
    );
  });

  test('head-to-head rival counts do not infer opponent wins from draws', () {
    final favorite = _player('favorite');
    final opponent = _player('opponent');
    final history = [
      for (var index = 0; index < 10; index++)
        _tournament(
          id: 'draw-duel-$index',
          players: [favorite, opponent],
          date: DateTime.utc(2026, 2, index + 1),
          matches: [
            _match(
              favorite,
              opponent,
              homeLegs: index < 6 ? 2 : (index < 9 ? 0 : 1),
              awayLegs: index < 6 ? 0 : (index < 9 ? 2 : 1),
              date: DateTime.utc(2026, 2, index + 1),
            ),
          ],
        ),
    ];
    final current = _tournament(
      id: 'current',
      players: [favorite, opponent],
      date: _date,
    );

    final results = _calculate(current: current, history: history);

    expect(
      results['favorite']!.map((insight) => insight.type),
      contains(PlayerInsightType.rival),
    );
    expect(
      results['opponent']!.map((insight) => insight.type),
      isNot(contains(PlayerInsightType.rival)),
    );
  });

  test('favorite-opponent and rival thresholds are separate', () {
    final home = _player('home');
    final favorite = _player('favorite');
    final rival = _player('rival');
    final history = [
      for (var index = 0; index < 10; index++) ...[
        _tournament(
          id: 'favorite-$index',
          players: [home, favorite],
          date: DateTime.utc(2026, 2, index + 1),
          matches: [
            _match(
              index < 7 ? home : favorite,
              index < 7 ? favorite : home,
              homeLegs: 2,
              awayLegs: 0,
              date: DateTime.utc(2026, 2, index + 1),
            ),
          ],
        ),
        _tournament(
          id: 'rival-$index',
          players: [home, rival],
          date: DateTime.utc(2026, 1, index + 1),
          matches: [
            _match(
              index < 5 ? home : rival,
              index < 5 ? rival : home,
              homeLegs: 2,
              awayLegs: 0,
              date: DateTime.utc(2026, 1, index + 1),
            ),
          ],
        ),
      ],
    ];
    final current = _tournament(
      id: 'current',
      players: [home, favorite, rival],
      date: _date,
    );

    final results = _calculate(current: current, history: history);

    expect(
      results['home']!.map((insight) => insight.type),
      containsAll({PlayerInsightType.rival}),
    );
    expect(
      results['favorite']!.map((insight) => insight.type),
      contains(PlayerInsightType.bogeyOpponent),
    );
    expect(
      results['favorite']!
          .singleWhere(
            (insight) => insight.type == PlayerInsightType.bogeyOpponent,
          )
          .explanation,
      contains('7 seiner letzten 10'),
    );
    expect(
      results['favorite']!.map((insight) => insight.type),
      isNot(contains(PlayerInsightType.rival)),
    );
    expect(
      results['rival']!.map((insight) => insight.type),
      contains(PlayerInsightType.rival),
    );
  });

  test('draws break streaks and do not count as alternating results', () {
    final home = _player('home');
    final away = _player('away');
    final history = [
      for (var index = 0; index < 5; index++)
        _tournament(
          id: 'draw-streak-$index',
          players: [home, away],
          date: DateTime.utc(2026, 2, index + 1),
          matches: [
            _match(
              home,
              away,
              homeLegs: index == 2 ? 1 : (index.isEven ? 2 : 0),
              awayLegs: index == 2 ? 1 : (index.isEven ? 0 : 2),
              date: DateTime.utc(2026, 2, index + 1),
            ),
          ],
        ),
    ];
    final current = _tournament(
      id: 'current',
      players: [home, away],
      date: _date,
    );

    final results = _calculate(current: current, history: history);

    expect(
      results['home']!.map((insight) => insight.type),
      isNot(contains(PlayerInsightType.hotStreak)),
    );
    expect(
      results['home']!.map((insight) => insight.type),
      isNot(contains(PlayerInsightType.consistent)),
    );
  });

  test('same-date matches remain ordered within a tournament for streaks', () {
    final home = _player('home');
    final away = _player('away');
    final third = _player('third');
    final fourth = _player('fourth');
    final current = _tournament(
      id: 'date-only-results',
      players: [home, away, third, fourth],
      date: _date,
      matches: [
        for (final (round, opponent) in [(1, away), (2, third), (3, fourth)])
          GroupMatch(
            homePlayer: home,
            awayPlayer: opponent,
            round: round,
            homeLegs: 2,
            awayLegs: 0,
          ),
      ],
    );

    final results = _calculate(current: current, history: [current]);

    expect(
      results['home']!.map((insight) => insight.type),
      contains(PlayerInsightType.hotStreak),
    );
  });

  test('back-on-track and consistent insights use the last five outcomes', () {
    final home = _player('home');
    final away = _player('away');
    final alternating = [
      for (var index = 0; index < 5; index++)
        _tournament(
          id: 'alternate-$index',
          players: [home, away],
          date: DateTime.utc(2026, 2, index + 1),
          matches: [
            _match(
              index.isEven ? home : away,
              index.isEven ? away : home,
              homeLegs: 2,
              awayLegs: 0,
              date: DateTime.utc(2026, 2, index + 1),
            ),
          ],
        ),
    ];
    final comeback = [
      for (var index = 0; index < 4; index++)
        _tournament(
          id: 'comeback-$index',
          players: [home, away],
          date: DateTime.utc(2026, 1, index + 1),
          matches: [
            _match(
              index == 3 ? home : away,
              index == 3 ? away : home,
              homeLegs: 2,
              awayLegs: 0,
              date: DateTime.utc(2026, 1, index + 1),
            ),
          ],
        ),
    ];
    final current = _tournament(
      id: 'current',
      players: [home, away],
      date: _date,
    );

    final alternatingResults = _calculate(
      current: current,
      history: alternating,
    );
    final comebackResults = _calculate(current: current, history: comeback);

    expect(
      alternatingResults['home']!.map((insight) => insight.type),
      contains(PlayerInsightType.consistent),
    );
    expect(
      comebackResults['home']!.map((insight) => insight.type),
      contains(PlayerInsightType.backOnTrack),
    );
  });

  test(
    'title defender requires a completed previous edition with same name',
    () {
      final champion = _player('champion');
      final runnerUp = _player('runner-up');
      final previousDate = DateTime.utc(2026, 2, 1);
      final finalMatch = _match(
        champion,
        runnerUp,
        homeLegs: 2,
        awayLegs: 0,
        date: previousDate,
      );
      final previous = _tournament(
        id: 'previous-edition',
        name: 'Vereinsmeisterschaft',
        players: [champion, runnerUp],
        date: previousDate,
        finishedAt: previousDate,
        stages: const [
          TournamentStage(name: 'Finale', type: 'single_knockout'),
        ],
        runStages: [
          KnockoutTournamentRunStage(
            name: 'Finale',
            rounds: [
              [finalMatch],
            ],
            finalEndsTournament: true,
          ),
        ],
      );
      final current = _tournament(
        id: 'current-edition',
        name: 'Vereinsmeisterschaft',
        players: [champion, runnerUp],
        date: _date,
      );

      final results = _calculate(current: current, history: [previous]);

      expect(
        results['champion']!.map((insight) => insight.type),
        contains(PlayerInsightType.titleDefender),
      );
      final unrelated = CreatedTournament.fromJson({
        ...previous.toJson(),
        'id': 'unrelated-series',
        'rankingIds': ['different-ranking'],
      });
      final unrelatedResults = _calculate(
        current: current,
        history: [unrelated],
      );
      expect(
        unrelatedResults['champion']!.map((insight) => insight.type),
        isNot(contains(PlayerInsightType.titleDefender)),
      );
    },
  );

  test('underdog and ELO climber require a selected ELO ranking', () {
    final first = _player('first');
    final second = _player('second');
    final third = _player('third');
    final ranking = const LocalRanking(id: 'elo', name: 'ELO');
    final current = _tournament(
      id: 'current',
      players: [first, second, third],
      rankingIds: const ['elo'],
      matches: [
        _match(third, first, homeLegs: 2, awayLegs: 0, date: _date),
        _match(third, second, homeLegs: 2, awayLegs: 0, date: _date),
      ],
    );
    final snapshot = LocalEloSnapshot(
      [
        LocalEloPlayer(id: 'first', name: 'FIRST', rating: 1200),
        LocalEloPlayer(id: 'second', name: 'SECOND', rating: 1100),
        LocalEloPlayer(id: 'third', name: 'THIRD', rating: 900),
      ],
      {
        'first': [
          _eloHistory(
            'current',
            playedAt: DateTime.utc(2026, 2, 1),
            rating: 1100,
          ),
          _eloHistory(
            'current',
            playedAt: DateTime.utc(2026, 3, 10),
            rating: 1200,
          ),
        ],
        'second': [
          _eloHistory(
            'current',
            playedAt: DateTime.utc(2026, 2, 1),
            rating: 1000,
          ),
        ],
        'third': [
          _eloHistory(
            'current',
            playedAt: DateTime.utc(2026, 2, 1),
            rating: 900,
          ),
        ],
      },
    );

    final results = _calculate(
      current: current,
      history: [current],
      ranking: ranking,
      snapshot: snapshot,
    );
    expect(
      results['third']!.map((insight) => insight.type),
      contains(PlayerInsightType.underdog),
    );
    expect(
      results['first']!.map((insight) => insight.type),
      contains(PlayerInsightType.eloClimber),
    );
    expect(
      results['second']!.map((insight) => insight.type),
      contains(PlayerInsightType.eloClimber),
    );
  });

  test('underdog is limited to the bottom third of the participant field', () {
    final first = _player('first');
    final second = _player('second');
    final third = _player('third');
    final fourth = _player('fourth');
    final current = _tournament(
      id: 'current',
      players: [first, second, third, fourth],
      rankingIds: const ['elo'],
      matches: [
        _match(third, first, homeLegs: 2, awayLegs: 0, date: _date),
        _match(third, second, homeLegs: 2, awayLegs: 0, date: _date),
        _match(fourth, first, homeLegs: 2, awayLegs: 0, date: _date),
        _match(fourth, second, homeLegs: 2, awayLegs: 0, date: _date),
      ],
    );
    final snapshot = LocalEloSnapshot([
      LocalEloPlayer(id: 'first', name: 'FIRST', rating: 1400),
      LocalEloPlayer(id: 'second', name: 'SECOND', rating: 1300),
      LocalEloPlayer(id: 'third', name: 'THIRD', rating: 1200),
      LocalEloPlayer(id: 'fourth', name: 'FOURTH', rating: 1100),
    ], const {});

    final results = _calculate(
      current: current,
      history: [current],
      ranking: const LocalRanking(id: 'elo', name: 'ELO'),
      snapshot: snapshot,
    );

    expect(
      results['third']!.map((insight) => insight.type),
      isNot(contains(PlayerInsightType.underdog)),
    );
    expect(
      results['fourth']!.map((insight) => insight.type),
      contains(PlayerInsightType.underdog),
    );
  });

  test('giant killer requires an ELO gap at the time of the direct win', () {
    final underdog = _player('underdog');
    final favorite = _player('favorite');
    final date = DateTime.utc(2026, 3, 10);
    final match = _match(
      underdog,
      favorite,
      homeLegs: 2,
      awayLegs: 1,
      date: date,
    );
    final past = _tournament(
      id: 'past',
      players: [underdog, favorite],
      date: date,
      matches: [match],
    );
    final current = _tournament(
      id: 'current',
      players: [underdog, favorite],
      date: _date,
    );
    final snapshot = LocalEloSnapshot(
      [
        LocalEloPlayer(id: 'underdog', name: 'UNDERDOG', rating: 800),
        LocalEloPlayer(id: 'favorite', name: 'FAVORITE', rating: 1100),
      ],
      {
        'underdog': [
          _eloHistory('past', playedAt: date, rating: 800, matchIndex: 0),
        ],
        'favorite': [
          _eloHistory('past', playedAt: date, rating: 1050, matchIndex: 0),
        ],
      },
    );

    final results = _calculate(
      current: current,
      history: [past],
      ranking: const LocalRanking(id: 'elo', name: 'ELO'),
      snapshot: snapshot,
    );
    expect(
      results['underdog']!.map((insight) => insight.type),
      contains(PlayerInsightType.giantKiller),
    );
  });

  test('ELO climber requires a 30-day baseline for every participant', () {
    final first = _player('first');
    final second = _player('second');
    final current = _tournament(
      id: 'current',
      players: [first, second],
      rankingIds: const ['elo'],
    );
    final snapshot = LocalEloSnapshot(
      [
        LocalEloPlayer(id: 'first', name: 'FIRST', rating: 1100),
        LocalEloPlayer(id: 'second', name: 'SECOND', rating: 1200),
      ],
      {
        'first': [
          _eloHistory('past', playedAt: DateTime.utc(2026, 2, 1), rating: 1000),
        ],
        'second': [
          _eloHistory(
            'recent',
            playedAt: DateTime.utc(2026, 3, 10),
            rating: 1200,
          ),
        ],
      },
    );

    final results = _calculate(
      current: current,
      history: [current],
      ranking: const LocalRanking(id: 'elo', name: 'ELO'),
      snapshot: snapshot,
    );

    expect(results.values.expand((items) => items), isEmpty);
  });

  test('insufficient history does not create speculative badges', () {
    final home = _player('home');
    final away = _player('away');
    final current = _tournament(
      id: 'current',
      players: [home, away],
      date: _date,
      matches: [_match(home, away, homeLegs: 2, awayLegs: 0, date: _date)],
    );

    final results = _calculate(current: current, history: [current]);
    expect(results.values.expand((items) => items), isEmpty);
  });
}

LocalEloHistoryItem _eloHistory(
  String tournamentId, {
  required DateTime playedAt,
  required int rating,
  int matchIndex = 0,
}) => LocalEloHistoryItem(
  tournamentId: tournamentId,
  matchIndex: matchIndex,
  playedAt: playedAt,
  tournamentName: 'Test',
  opponentName: 'Gegner',
  score: '2:0',
  delta: 0,
  ratingAfter: rating,
  kFactor: 15,
  expectedScore: 0.5,
);
