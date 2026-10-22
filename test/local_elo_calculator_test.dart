import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_elo_calculator.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

CreatedTournament tournament(
  String id,
  DateTime date,
  String home,
  String away, {
  bool assigned = true,
}) {
  final match = GroupMatch(
    round: 1,
    homePlayer: TournamentPlayer(
      profileId: home,
      name: home,
      isGenerated: false,
    ),
    awayPlayer: TournamentPlayer(
      profileId: away,
      name: away,
      isGenerated: false,
    ),
    homeLegs: 2,
    awayLegs: 0,
  );
  return CreatedTournament(
    id: id,
    name: id,
    createdAt: date,
    startedAt: date,
    players: [match.homePlayer!, match.awayPlayer!],
    stages: [],
    runStages: [
      KnockoutTournamentRunStage(
        name: 'Finale',
        rounds: [
          [match],
        ],
      ),
    ],
    rankingIds: assigned ? const ['season'] : const [],
  );
}

CreatedTournament tournamentWithMatches(
  String id,
  DateTime date,
  List<GroupMatch> matches,
) => CreatedTournament(
  id: id,
  name: id,
  createdAt: date,
  startedAt: date,
  players: const [],
  stages: const [],
  runStages: [
    KnockoutTournamentRunStage(name: 'Turnier', rounds: [matches]),
  ],
  rankingIds: const ['season'],
);

void main() {
  const calculator = LocalEloCalculator();

  test('only counts completed matches between assigned ranking players', () {
    final snapshot = calculator.calculate(
      players: const {'a': 'Anna', 'b': 'Ben'},
      tournaments: [
        tournament('ranked-match', DateTime.utc(2026, 2), 'a', 'b'),
        tournament('guest-match', DateTime.utc(2026, 3), 'a', 'guest'),
      ],
      rankingId: 'season',
      now: DateTime.utc(2026, 12),
    );

    expect(snapshot.entries.map((player) => player.id).toSet(), {'a', 'b'});
    expect(snapshot.entries.every((player) => player.matches == 1), isTrue);
    expect(snapshot.history['a'], hasLength(1));
    expect(snapshot.history['a']!.single.opponentName, 'Ben');
  });

  test(
    'exposes exact ranked deltas for the corresponding tournament match',
    () {
      final ranked = tournament(
        'ranked-match',
        DateTime.utc(2026, 2),
        'a',
        'b',
      );
      final match = (ranked.runStages.single as KnockoutTournamentRunStage)
          .rounds
          .single
          .single;
      final snapshot = calculator.calculate(
        players: const {'a': 'Anna', 'b': 'Ben'},
        tournaments: [ranked],
        rankingId: 'season',
      );

      final delta = snapshot.matchDeltas[calculator.matchKey(ranked, match)];
      expect(delta?.home, 13);
      expect(delta?.away, -13);
    },
  );

  test('redistributes absence decay points and preserves total Elo', () {
    final prior = tournamentWithMatches('prior', DateTime.utc(2026, 1), [
      GroupMatch(
        round: 1,
        homePlayer: const TournamentPlayer(
          profileId: 'a',
          name: 'Anna',
          isGenerated: false,
        ),
        awayPlayer: const TournamentPlayer(
          profileId: 'c',
          name: 'Chris',
          isGenerated: false,
        ),
        homeLegs: 0,
        awayLegs: 2,
      ),
    ]);
    final snapshot = calculator.calculate(
      players: const {'a': 'Anna', 'b': 'Ben', 'c': 'Chris'},
      tournaments: [
        prior,
        tournament('played', DateTime.utc(2026, 2), 'a', 'b'),
      ],
      rankingId: 'season',
      absenceDecayEnabled: true,
      absenceDecayPoints: 10,
    );

    expect(
      snapshot.entries.map((player) => player.rating).reduce((a, b) => a + b),
      3000,
    );
    expect(
      snapshot.entries.singleWhere((player) => player.id == 'c').rating,
      1003,
    );
    expect(
      snapshot.history['c']!.singleWhere((item) => item.matchIndex == -1).delta,
      -10,
    );
    final decayDeltas = snapshot.history.values
        .expand((items) => items)
        .where((item) => item.matchIndex == -1)
        .map((item) => item.delta);
    expect(decayDeltas.reduce((a, b) => a + b), 0);
  });

  test(
    'caps decay at the start rating unless below-start decay is enabled',
    () {
      final first = tournamentWithMatches('first', DateTime.utc(2026, 1), [
        GroupMatch(
          round: 1,
          homePlayer: const TournamentPlayer(
            profileId: 'a',
            name: 'Anna',
            isGenerated: false,
          ),
          awayPlayer: const TournamentPlayer(
            profileId: 'c',
            name: 'Chris',
            isGenerated: false,
          ),
          homeLegs: 0,
          awayLegs: 2,
        ),
        GroupMatch(
          round: 1,
          homePlayer: const TournamentPlayer(
            profileId: 'a',
            name: 'Anna',
            isGenerated: false,
          ),
          awayPlayer: const TournamentPlayer(
            profileId: 'b',
            name: 'Ben',
            isGenerated: false,
          ),
          homeLegs: 2,
          awayLegs: 0,
        ),
      ]);
      final second = tournament('second', DateTime.utc(2026, 2), 'a', 'b');
      LocalEloSnapshot calculate({required bool allowBelowStart}) =>
          calculator.calculate(
            players: const {'a': 'Anna', 'b': 'Ben', 'c': 'Chris'},
            tournaments: [first, second],
            rankingId: 'season',
            absenceDecayEnabled: true,
            absenceDecayPoints: 50,
            allowDecayBelowStartRating: allowBelowStart,
          );
      final capped = calculate(allowBelowStart: false);
      final belowStartAllowed = calculate(allowBelowStart: true);

      expect(
        capped.entries.singleWhere((player) => player.id == 'c').rating,
        1000,
      );
      expect(
        capped.entries.map((player) => player.rating).reduce((a, b) => a + b),
        3000,
      );
      expect(
        belowStartAllowed.entries
            .singleWhere((player) => player.id == 'c')
            .rating,
        963,
      );
      expect(
        belowStartAllowed.entries
            .map((player) => player.rating)
            .reduce((a, b) => a + b),
        3000,
      );
    },
  );

  test(
    'starts inactivity decay only after the configured missed tournaments',
    () {
      final prior = tournamentWithMatches('prior', DateTime.utc(2026, 1), [
        GroupMatch(
          round: 1,
          homePlayer: const TournamentPlayer(
            profileId: 'a',
            name: 'Anna',
            isGenerated: false,
          ),
          awayPlayer: const TournamentPlayer(
            profileId: 'c',
            name: 'Chris',
            isGenerated: false,
          ),
          homeLegs: 0,
          awayLegs: 2,
        ),
      ]);
      final snapshot = calculator.calculate(
        players: const {'a': 'Anna', 'b': 'Ben', 'c': 'Chris'},
        tournaments: [
          prior,
          tournament('first', DateTime.utc(2026, 2), 'a', 'b'),
          tournament('second', DateTime.utc(2026, 3), 'a', 'b'),
        ],
        rankingId: 'season',
        inactivityDecayEnabled: true,
        inactivityGraceTournaments: 1,
        inactivityDecayPoints: 4,
      );

      expect(
        snapshot.entries.singleWhere((player) => player.id == 'c').rating,
        1009,
      );
      expect(
        snapshot.entries.map((player) => player.rating).reduce((a, b) => a + b),
        3000,
      );
    },
  );

  test('uses prior ranking history instead of resetting players to 1000', () {
    final prior = tournament('prior', DateTime.utc(2026, 1), 'a', 'b');
    final current = tournament('current', DateTime.utc(2026, 2), 'c', 'a');
    final currentMatch =
        (current.runStages.single as KnockoutTournamentRunStage).matches.single;
    final snapshot = calculator.calculate(
      players: const {'a': 'Anna', 'b': 'Ben', 'c': 'Chris'},
      tournaments: [prior, current],
      rankingId: 'season',
      newPlayerK: 25,
      normalPlayerK: 15,
      matchesBeforeNormal: 1,
    );

    final delta =
        snapshot.matchDeltas[calculator.matchKey(current, currentMatch)];
    expect(delta?.home, 13);
    expect(delta?.away, -8);
  });

  test('does not expose deltas for an unassigned ranking tournament', () {
    final unassigned = tournament(
      'guest-match',
      DateTime.utc(2026, 2),
      'a',
      'b',
      assigned: false,
    );
    final snapshot = calculator.calculate(
      players: const {'a': 'Anna', 'b': 'Ben'},
      tournaments: [unassigned],
      rankingId: 'season',
    );

    expect(snapshot.matchDeltas, isEmpty);
  });

  test(
    'excludes every match involving players below the tournament participation threshold',
    () {
      final first = tournament('first', DateTime.utc(2026, 1), 'a', 'b');
      final second = tournament('second', DateTime.utc(2026, 2), 'a', 'b');
      final third = tournament('third', DateTime.utc(2026, 3), 'a', 'c');
      final firstMatch = (first.runStages.single as KnockoutTournamentRunStage)
          .rounds
          .single
          .single;
      final secondMatch =
          (second.runStages.single as KnockoutTournamentRunStage)
              .rounds
              .single
              .single;
      final thirdMatch = (third.runStages.single as KnockoutTournamentRunStage)
          .rounds
          .single
          .single;

      final snapshot = calculator.calculate(
        players: const {'a': 'Anna', 'b': 'Ben', 'c': 'Chris'},
        tournaments: [first, second, third],
        rankingId: 'season',
        minimumParticipationTournaments: 2,
      );

      expect(snapshot.entries.map((player) => player.id).toSet(), {'a', 'b'});
      expect(snapshot.entries.every((player) => player.matches == 2), isTrue);
      expect(
        snapshot.matchDeltas[calculator.matchKey(first, firstMatch)],
        isNotNull,
      );
      expect(
        snapshot.matchDeltas[calculator.matchKey(second, secondMatch)],
        isNotNull,
      );
      expect(
        snapshot.matchDeltas[calculator.matchKey(third, thirdMatch)],
        isNull,
      );
      expect(snapshot.history.keys, {'a', 'b'});
    },
  );

  test('applies ranking assignment and date range before replay', () {
    final old = tournament('old', DateTime.utc(2025, 12), 'a', 'b');
    final unassigned = tournament(
      'other',
      DateTime.utc(2026, 2),
      'a',
      'b',
      assigned: false,
    );
    final snapshot = calculator.calculate(
      players: const {'a': 'Anna', 'b': 'Ben'},
      tournaments: [old, unassigned],
      rankingId: 'season',
      validFromYear: 2026,
      validToYear: 2026,
    );

    expect(snapshot.entries, isEmpty);
  });
}
