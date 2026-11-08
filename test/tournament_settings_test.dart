import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_settings.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/tournament_run_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CreatedTournament _tournament() => CreatedTournament(
  id: 'settings-test',
  name: 'Testturnier',
  players: const [],
  stages: const [],
  runStages: const [],
);

void main() {
  test('tournament settings persist and old tournament JSON gets defaults', () {
    final oldTournament = _tournament();
    final restoredOld = CreatedTournament.fromJson(oldTournament.toJson());
    expect(restoredOld.tournamentSettings, const TournamentSettings());

    final tournament = _tournament()
      ..tournamentSettings = const TournamentSettings(
        groupMatchDeficitThreshold: 1,
        usePercentageForGroups: true,
        soundModeEnabled: true,
        announceHintsAudibly: true,
        idleBoardSoundEnabled: true,
        idleBoardSoundStartMinutes: 5,
        idleBoardSoundRepeatMinutes: 2,
        readAlternativeRecommendations: true,
        alternativeRecommendationCount: 2,
        announcementNameFormat: AnnouncementNameFormat.firstNameLastInitial,
        speakNicknameWhenAvailable: true,
      );
    final restored = CreatedTournament.fromJson(tournament.toJson());
    expect(restored.tournamentSettings, tournament.tournamentSettings);
    final settingsJson =
        tournament.toJson()['tournamentSettings'] as Map<String, dynamic>;
    expect(settingsJson['version'], 1);
  });

  test('group deficit defaults to three scaled matches', () {
    expect(const TournamentSettings().groupMatchDeficitThreshold, 3);
  });

  testWidgets(
    'tournament settings expose numeric thresholds and sound options',
    (tester) async {
      tester.view
        ..physicalSize = const Size(800, 1200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tournament = _tournament();
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                TournamentRunSettingsPanel(
                  tournament: tournament,
                  onChanged: () async {
                    saves++;
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sprachassistenz aktivieren'));
      await tester.pumpAndSettle();
      expect(tournament.tournamentSettings.soundModeEnabled, isTrue);
      expect(find.text('Alternative Empfehlungen vorlesen'), findsOneWidget);
      await tester.tap(find.text('Alternative Empfehlungen vorlesen'));
      await tester.pumpAndSettle();
      final alternativeCount = find.byKey(
        const ValueKey('alternative-recommendation-count'),
      );
      expect(alternativeCount, findsOneWidget);
      await tester.enterText(alternativeCount, '2');
      await tester.ensureVisible(find.text('Zahlenwerte speichern'));
      await tester.tap(find.text('Zahlenwerte speichern'));
      await tester.pumpAndSettle();
      expect(tournament.tournamentSettings.alternativeRecommendationCount, 2);

      await tester.tap(find.text('Hinweise akustisch ankündigen'));
      await tester.pumpAndSettle();
      expect(tournament.tournamentSettings.announceHintsAudibly, isTrue);

      expect(find.byType(TextFormField), findsNWidgets(3));
      final playerThreshold = find.byKey(
        const ValueKey('player-match-deficit-threshold'),
      );
      await tester.enterText(playerThreshold, '123');
      await tester.ensureVisible(find.text('Zahlenwerte speichern'));
      await tester.tap(find.text('Zahlenwerte speichern'));
      await tester.pumpAndSettle();
      expect(tournament.tournamentSettings.playerMatchDeficitThreshold, 123);

      await tester.tap(
        find.text('Bei Board-Leerstand regelmäßig ein Signal abspielen'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(5));
      expect(saves, 6);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'alternative recommendation number button follows voice assistant mode',
    (tester) async {
      final tournament = _tournament();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                TournamentRunSettingsPanel(
                  tournament: tournament,
                  onChanged: () async {},
                  showPrioritySettings: false,
                  showHintAudioSettings: false,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Zahlenwerte speichern'), findsNothing);
      await tester.tap(find.text('Sprachassistenz aktivieren'));
      await tester.pumpAndSettle();
      expect(find.text('Zahlenwerte speichern'), findsOneWidget);

      await tester.tap(find.text('Sprachassistenz aktivieren'));
      await tester.pumpAndSettle();
      expect(find.text('Zahlenwerte speichern'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tournament settings remain usable across responsive widths', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    for (final size in [
      const Size(360, 800),
      const Size(800, 600),
      const Size(1440, 900),
    ]) {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(
              children: [
                TournamentRunSettingsPanel(
                  tournament: _tournament(),
                  onChanged: () async {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Viewport $size');
    }
  });
}
