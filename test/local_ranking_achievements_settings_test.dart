import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';

void main() {
  group('LocalRanking achievement settings', () {
    test('defaults both settings to disabled for existing rankings', () {
      final ranking = LocalRanking.fromJson({
        'id': 'ranking-1',
        'name': '2026',
      });

      expect(ranking.achievementsEnabled, isFalse);
      expect(ranking.isCompleted, isFalse);
    });

    test('persists achievement activation and completion independently', () {
      final ranking = const LocalRanking(
        id: 'ranking-1',
        name: '2026',
      ).copyWith(achievementsEnabled: true, isCompleted: true);
      final restored = LocalRanking.fromJson(ranking.toJson());

      expect(restored.achievementsEnabled, isTrue);
      expect(restored.isCompleted, isTrue);
      expect(
        restored
            .copyWith(achievementsEnabled: false, isCompleted: false)
            .achievementsEnabled,
        isFalse,
      );
      expect(
        restored
            .copyWith(achievementsEnabled: false, isCompleted: false)
            .isCompleted,
        isFalse,
      );
    });

    test('persists ranking-specific achievement thresholds', () {
      final ranking = const LocalRanking(id: 'ranking-1', name: '2026')
          .copyWith(
            achievementsEnabled: true,
            achievementTargets: const {
              'tournament_participation_5': 20,
              'monthly_average_60': 45.5,
            },
          );
      final restored = LocalRanking.fromJson(ranking.toJson());

      expect(restored.achievementTargets, {
        'tournament_participation_5': 20,
        'monthly_average_60': 45.5,
      });
      expect(
        restored.copyWith(achievementTargets: const {}).achievementTargets,
        isEmpty,
      );
    });

    test('persists ranking-specific alternative achievement thresholds', () {
      final ranking = const LocalRanking(id: 'ranking-1', name: '2026')
          .copyWith(
            achievementParameters: const {'elo_upset': 350},
            achievementAlternativeTargets: const {
              'legs_lost_10': 4,
              'losses_to_same_opponent_10': 12,
            },
          );
      final restored = LocalRanking.fromJson(ranking.toJson());

      expect(restored.achievementAlternativeTargets, {
        'legs_lost_10': 4,
        'losses_to_same_opponent_10': 12,
      });
      expect(restored.achievementParameters, {'elo_upset': 350});
    });
  });
}
