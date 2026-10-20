import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/planning_duration.dart';

void main() {
  test('three, four and five boards reduce the same tournament estimate', () {
    final times = [
      for (final boards in [3, 4, 5])
        PlanningDuration.calculate(
          groupSizes: [7, 6],
          qualifiers: 4,
          boards: boards,
          matchMinutes: 30,
        ).totalMinutes,
    ];
    expect(times, [420, 330, 300]);
    final threeGroups = [
      for (final boards in [3, 4, 5])
        PlanningDuration.calculate(
          groupSizes: [5, 4, 4],
          qualifiers: 6,
          boards: boards,
          matchMinutes: 30,
        ).totalMinutes,
    ];
    expect(threeGroups, [330, 270, 240]);
  });

  test('idle allowance only counts unused boards in each scheduled block', () {
    final group = PlanningDuration.calculate(
      groupSizes: [4],
      qualifiers: 0,
      boards: 4,
      matchMinutes: 10,
      boardIdleMinutes: 4,
    );
    final knockout = PlanningDuration.calculate(
      groupSizes: const [],
      qualifiers: 8,
      boards: 4,
      matchMinutes: 10,
      boardIdleMinutes: 4,
    );
    expect(group.groupSlots, 3);
    expect(group.groupIdleUnits, 6);
    expect(group.totalMinutes, 54);
    expect(knockout.knockoutSlots, 3);
    expect(knockout.knockoutIdleUnits, 5);
    expect(knockout.totalMinutes, 50);
  });

  test(
    'surplus boards cannot shorten a three-player group below three matches',
    () {
      for (final boards in [1, 3, 5]) {
        final duration = PlanningDuration.calculate(
          groupSizes: [3],
          qualifiers: 0,
          boards: boards,
          matchMinutes: 30,
        );
        expect(duration.totalMinutes, 90);
      }
    },
  );
  test(
    '13 players on four boards use flexible group ordering and sequential knockout',
    () {
      final two = PlanningDuration.calculate(
        groupSizes: [7, 6],
        qualifiers: 4,
        boards: 4,
        matchMinutes: 30,
      );
      final three = PlanningDuration.calculate(
        groupSizes: [5, 4, 4],
        qualifiers: 6,
        boards: 4,
        matchMinutes: 30,
      );
      expect(two.groupSlots, 9);
      expect(two.knockoutSlots, 2);
      expect(two.totalMinutes, 330);
      expect(three.groupSlots, 6);
      expect(three.knockoutSlots, 3);
      expect(three.totalMinutes, 270);
    },
  );

  test(
    'one board counts each real match once including a knockout with byes',
    () {
      final result = PlanningDuration.calculate(
        groupSizes: [5, 4, 4],
        qualifiers: 6,
        boards: 1,
        matchMinutes: 30,
      );
      expect(result.groupMinutes, 22 * 30);
      expect(result.knockoutMinutes, 5 * 30);
    },
  );

  test(
    'more boards never increase time and cannot bypass player dependencies',
    () {
      var previous = 100000;
      for (var boards = 1; boards <= 20; boards++) {
        final result = PlanningDuration.calculate(
          groupSizes: [7, 6],
          qualifiers: 4,
          boards: boards,
          matchMinutes: 30,
        );
        expect(result.totalMinutes, lessThanOrEqualTo(previous));
        expect(result.totalMinutes * boards, greaterThanOrEqualTo(39 * 30));
        expect(result.groupSlots, greaterThanOrEqualTo(7));
        previous = result.totalMinutes;
      }
    },
  );
}
