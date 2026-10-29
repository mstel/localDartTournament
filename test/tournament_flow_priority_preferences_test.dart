import 'package:dart_tournament_manager/features/tournaments/application/tournament_flow_priority_preferences.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_flow_priority_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'loads compatible defaults when no hint settings have been saved',
    () async {
      expect(
        await TournamentFlowPriorityPreferences().load(),
        const TournamentFlowPrioritySettings(),
      );
    },
  );

  test('persists editable thresholds and percentage mode', () async {
    const settings = TournamentFlowPrioritySettings(
      playerMatchDeficitThreshold: 4,
      groupMatchDeficitThreshold: 5,
      usePercentageForGroups: true,
    );

    await TournamentFlowPriorityPreferences().save(settings);

    expect(await TournamentFlowPriorityPreferences().load(), settings);
  });

  test('rejects non-positive thresholds', () async {
    await expectLater(
      TournamentFlowPriorityPreferences().save(
        const TournamentFlowPrioritySettings(playerMatchDeficitThreshold: 0),
      ),
      throwsArgumentError,
    );
  });
}
