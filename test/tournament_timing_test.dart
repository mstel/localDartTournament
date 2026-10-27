import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_timing.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_planning_parameters.dart';

void main() {
  final start = DateTime.utc(2026, 10, 3, 12);
  final a = TournamentPlayer.generated(1), b = TournamentPlayer.generated(2);
  CreatedTournament fixture() => CreatedTournament(
    name: 'Test',
    players: [a, b],
    boardCount: 1,
    stages: const [
      TournamentStage(
        name: 'Finale',
        type: 'single_knockout',
        knockoutParticipantCount: 2,
        knockoutBracketSize: 2,
      ),
    ],
    runStages: [
      KnockoutTournamentRunStage(
        name: 'Finale',
        rounds: [
          [GroupMatch(homePlayer: a, awayPlayer: b, round: 1)],
        ],
      ),
    ],
  );
  test('first match records persistent start and freezes original plan', () {
    final t = fixture();
    final match = TournamentTiming.matches(t).single;
    match.startedAt = start;
    TournamentTiming.capture(t, const TournamentPlanningParameters());
    expect(t.startedAt, start);
    final minutes = t.plannedMinutes;
    t.boardCount = 4;
    TournamentTiming.capture(t, const TournamentPlanningParameters());
    final copy = CreatedTournament.fromJson(t.toJson());
    expect(copy.startedAt, start);
    expect(copy.plannedMinutes, minutes);
    expect(copy.plannedMatches, 1);
    expect(copy.plannedMatchEndSeconds, t.plannedMatchEndSeconds);
    expect(copy.plannedMatchEndSeconds, isNotEmpty);
    expect(
      TournamentTiming.snapshot(
        copy,
        start.add(const Duration(minutes: 10)),
      ).elapsed.inMinutes,
      10,
    );
  });
  test('completed clock freezes; clearing results excludes old durations', () {
    final t = fixture();
    final m = TournamentTiming.matches(t).single;
    m.startedAt = start;
    m.finishedAt = start.add(const Duration(minutes: 12));
    m.homeLegs = 2;
    m.awayLegs = 0;
    TournamentTiming.capture(t, const TournamentPlanningParameters());
    final stats = TournamentTiming.snapshot(
      t,
      start.add(const Duration(days: 1)),
    );
    expect(stats.elapsed.inMinutes, 12);
    expect(stats.averageSeconds, 720);
    m.homeLegs = null;
    m.awayLegs = null;
    TournamentTiming.capture(t, const TournamentPlanningParameters());
    expect(t.finishedAt, isNull);
    expect(TournamentTiming.snapshot(t, start).matchSeconds, isEmpty);
  });
  test('old results without start do not invent match durations', () {
    final t = fixture();
    final m = TournamentTiming.matches(t).single;
    m.homeLegs = 2;
    m.awayLegs = 0;
    m.finishedAt = start;
    TournamentTiming.capture(t, const TournamentPlanningParameters());
    expect(t.startedAt, isNull);
    expect(TournamentTiming.snapshot(t, start).unmeasured, 1);
    expect(TournamentTiming.snapshot(t, start).averageSeconds, isNull);
  });
  test(
    'first result backdates the tournament clock by match and board time',
    () {
      final t = fixture();
      final match = TournamentTiming.matches(t).single
        ..homeLegs = 2
        ..awayLegs = 0
        ..finishedAt = start.add(const Duration(hours: 1));
      final parameters = TournamentPlanningParameters.fromValues({
        PlanningParameter.minutes501DoubleOut: 5,
        PlanningParameter.boardIdleMinutes: 4,
      });

      expect(TournamentTiming.startFromFirstResult(t, parameters), isTrue);
      expect(
        t.startedAt,
        match.finishedAt!.subtract(const Duration(minutes: 16, seconds: 30)),
      );
    },
  );
  test('manual start is not overwritten by first result backdating', () {
    final t = fixture()..startedAt = start;
    TournamentTiming.matches(t).single
      ..homeLegs = 2
      ..awayLegs = 0
      ..finishedAt = start.add(const Duration(hours: 1));

    expect(
      TournamentTiming.startFromFirstResult(
        t,
        const TournamentPlanningParameters(),
      ),
      isFalse,
    );
    expect(t.startedAt, start);
  });
  test(
    'starting a match without a result does not start the tournament clock',
    () async {
      final t = fixture();
      TournamentTiming.matches(t).single.startedAt = start;

      await TournamentTiming.prepare(t);

      expect(t.startedAt, isNull);
    },
  );
  test('expected progress follows concurrent blocks and survives saving', () {
    final t = fixture()
      ..startedAt = start
      ..plannedMinimumMinutes = 30
      ..plannedMinutes = 75
      ..plannedMatches = 6
      ..plannedMatchEndSeconds = [1500, 1500, 3000, 3000, 4500, 4500];
    final copy = CreatedTournament.fromJson(t.toJson());
    expect(copy.plannedMinimumMinutes, 30);
    expect(
      TournamentTiming.snapshot(
        copy,
        start.add(const Duration(minutes: 24)),
      ).expectedCompleted,
      0,
    );
    expect(
      TournamentTiming.snapshot(
        copy,
        start.add(const Duration(minutes: 25)),
      ).expectedCompleted,
      2,
    );
    expect(
      TournamentTiming.snapshot(
        copy,
        start.add(const Duration(hours: 3)),
      ).expectedCompleted,
      6,
    );
    expect(
      TournamentTiming.snapshot(
        copy,
        start.add(const Duration(minutes: 25)),
      ).forecast,
      start.add(const Duration(minutes: 75)),
    );
  });
  test('forecast remains fixed at planned duration from the start time', () {
    final t = fixture()
      ..startedAt = start
      ..plannedMinutes = 60
      ..plannedMatches = 6;
    final m = TournamentTiming.matches(t).single;
    m.startedAt = start;
    m.finishedAt = start.add(const Duration(minutes: 10));
    m.homeLegs = 2;
    m.awayLegs = 0;
    expect(
      TournamentTiming.snapshot(
        t,
        start.add(const Duration(minutes: 10)),
      ).forecast,
      start.add(const Duration(hours: 1)),
    );
    expect(
      TournamentTiming.snapshot(
        t,
        start.add(const Duration(minutes: 20)),
      ).forecast,
      start.add(const Duration(hours: 1)),
    );
  });
}
