import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/modes/swiss/swiss_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/application/configuration_duration_estimator.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_planning_parameters.dart';
import 'package:dart_tournament_manager/features/tournaments/application/expanded_format_planner.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_format_planner.dart';

TournamentGroup group(int n, int rounds) {
  final players = List.generate(n, (i) => TournamentPlayer.generated(i + 1));
  return TournamentGroup(
    name: 'Swiss',
    playType: 'swiss',
    players: players,
    matches: SwissEngine.build(players, rounds),
  );
}

void finish(GroupMatch m, [bool home = true]) {
  m.homeLegs = home ? 2 : 0;
  m.awayLegs = home ? 0 : 2;
}

void main() {
  test('saved Swiss pairings and bye points survive restoring', () {
    final original = group(7, 3);
    for (final m in original.matches.where(
      (m) => m.round == 1 && m.hasPlayers,
    )) {
      finish(m);
    }
    final restored = TournamentGroup.fromJson(original.toJson());
    final bye = restored.matches.singleWhere((m) => m.allowsBye).winner!;
    final standing = SwissEngine.standings(
      restored,
    ).singleWhere((s) => s.player == bye);
    expect(standing.points, 3);
    expect(standing.played, 0);
    SwissEngine.advance(original);
    SwissEngine.advance(restored);
    expect(restored.toJson(), original.toJson());
  });
  test(
    'finder includes Swiss and preserves fixed waiting time across formats',
    () async {
      final results = await const ExpandedFormatPlanner().suggest(
        const TournamentPlanningRequest(
          players: 8,
          boards: 3,
          minimumMatchesPerPlayer: 2,
          minimumMinutes: 0,
          maximumMinutes: 10000,
          targetMinutes: 240,
          x01Selection: '501',
          checkoutType: 'double_out',
          maximumGroups: 1,
          maximumStages: 1,
          enabledModes: {'groups:swiss'},
        ),
      );
      expect(results, isNotEmpty);
      for (final result in results) {
        expect(result.configurations.single.groupPlayType, 'swiss');
        final estimate = const ConfigurationDurationEstimator().preview(
          result.configurations,
          3,
          const TournamentPlanningParameters(),
        )!;
        expect(result.estimatedMinutes, estimate.minutes);
        expect(result.totalMatches, estimate.totalMatches);
      }
    },
  );
  test(
    'waits for entire round; correcting a result clears dependent rounds',
    () {
      final g = group(8, 3);
      for (final m in g.matches.where((m) => m.round == 1).take(3)) {
        finish(m);
      }
      SwissEngine.advance(g);
      expect(
        g.matches.where((m) => m.round == 2).any((m) => m.hasPlayers),
        false,
      );
      finish(g.matches.where((m) => m.round == 1).last);
      SwissEngine.advance(g);
      expect(
        g.matches.where((m) => m.round == 2).every((m) => m.hasPlayers),
        true,
      );
      SwissEngine.invalidateAfter(g, 1);
      expect(
        g.matches
            .where((m) => m.round > 1)
            .any((m) => m.hasPlayers || m.hasResult),
        false,
      );
    },
  );
  test('random Swiss tournaments never repeat opponents or byes', () {
    for (var n = 3; n <= 24; n++) {
      for (var seed = 0; seed < 20; seed++) {
        final rounds = SwissEngine.maximumRounds(n);
        final g = group(n, rounds);
        final random = Random(seed);
        final pairs = <String>{};
        final byes = <String>{};
        for (var r = 1; r <= rounds; r++) {
          final seen = <TournamentPlayer>{};
          for (final m in g.matches.where((m) => m.round == r)) {
            expect(m.homePlayer, isNotNull, reason: '$n/$seed/$r');
            expect(seen.add(m.homePlayer!), true);
            if (!m.hasPlayers) {
              expect(byes.add(m.winner!.name), true);
              continue;
            }
            expect(seen.add(m.awayPlayer!), true);
            final names = [m.homePlayer!.name, m.awayPlayer!.name]..sort();
            expect(pairs.add(names.join('|')), true);
            finish(m, random.nextBool());
          }
          expect(seen.length, n);
          SwissEngine.advance(g);
        }
        expect(g.matches.every((m) => m.isResolved), true);
        expect(
          SwissEngine.standings(g).fold<int>(0, (s, p) => s + p.points),
          rounds * ((n + 1) ~/ 2) * 3,
        );
      }
    }
  });
  test(
    'time includes board batches, round barriers and fixed waiting reserve',
    () {
      const config = TournamentStage(
        name: 'Swiss',
        type: 'groups',
        groupCount: 1,
        groupSizes: [8],
        groupPlayType: 'swiss',
        groupPlayTypes: ['swiss'],
        groupRoundRobinRepeats: [3],
      );
      const estimator = ConfigurationDurationEstimator();
      final parameters = TournamentPlanningParameters.fromValues({
        PlanningParameter.minutes501DoubleOut: 10,
        PlanningParameter.boardIdleMinutes: 0,
      });
      final three = estimator.preview([config], 3, parameters)!;
      final four = estimator.preview([config], 4, parameters)!;
      expect(three.totalMatches, 12);
      expect(three.minimumMatches, 3);
      expect(three.waitMinutes, 10);
      expect(three.minutes, 160); // 3 rounds × 2 batches × 25 + 2 × 5
      expect(four.minutes, 85); // 3 rounds × 25 + 2 × 5
      expect(four.matchEndSeconds.last, 85 * 60);
    },
  );
}
