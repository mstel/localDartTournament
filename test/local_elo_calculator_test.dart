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
