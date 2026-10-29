import 'package:dart_tournament_manager/features/tournaments/application/group_tie_breaker_preferences.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('loads the default order when no device preference exists', () async {
    expect(await GroupTieBreakerPreferences().load(), defaultGroupTieBreakers);
  });

  test('remembers a reordered list on the device', () async {
    const order = ['legDifference', 'points', 'legsFor', 'headToHead'];
    final preferences = GroupTieBreakerPreferences();

    await preferences.save(order);

    expect(await GroupTieBreakerPreferences().load(), order);
  });

  test('falls back to defaults for an invalid saved order', () async {
    SharedPreferences.setMockInitialValues({
      GroupTieBreakerPreferences.key: ['points', 'unknown'],
    });
    expect(await GroupTieBreakerPreferences().load(), defaultGroupTieBreakers);
  });

  test(
    'migrates the previous default order to the new tournament default',
    () async {
      SharedPreferences.setMockInitialValues({
        GroupTieBreakerPreferences.key:
            GroupTieBreakerPreferences.previousDefault,
      });

      expect(
        await GroupTieBreakerPreferences().load(),
        defaultGroupTieBreakers,
      );
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getStringList(GroupTieBreakerPreferences.key),
        defaultGroupTieBreakers,
      );
    },
  );

  test('rejects an incomplete order when saving', () async {
    await expectLater(
      GroupTieBreakerPreferences().save(['points']),
      throwsArgumentError,
    );
  });
}
