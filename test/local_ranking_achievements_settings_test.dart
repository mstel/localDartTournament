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
  });
}
