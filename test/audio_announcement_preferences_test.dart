import 'package:dart_tournament_manager/features/tournaments/application/audio_announcement_preferences.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/settings/presentation/audio_announcement_defaults_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('audio announcement preferences persist with safe defaults', () async {
    final storage = AudioAnnouncementPreferencesStorage();
    final defaults = await storage.load();
    expect(defaults.nameFormat, AnnouncementNameFormat.fullName);
    expect(defaults.speakNicknameWhenAvailable, isFalse);

    await storage.save(
      const AudioAnnouncementPreferences(
        nameFormat: AnnouncementNameFormat.firstNameLastInitial,
        speakNicknameWhenAvailable: true,
      ),
    );

    final loaded = await storage.load();
    expect(loaded.nameFormat, AnnouncementNameFormat.firstNameLastInitial);
    expect(loaded.speakNicknameWhenAvailable, isTrue);
  });

  test('speech uses selected name style and lets nickname take precedence', () {
    const player = TournamentPlayer(
      profileId: 'player',
      name: 'Ada Lovelace',
      isGenerated: false,
    );
    final opponent = TournamentPlayer.generated(1);
    final profile = PlayerProfile(
      id: 'player',
      firstName: 'Ada',
      lastName: 'Lovelace',
      country: '',
      city: '',
      dartsSetupJson: PlayerProfile.encodeMetadata(nickname: 'Enchantress'),
      createdAt: DateTime.utc(2026),
      isActive: true,
    );
    final match = GroupMatch(
      homePlayer: player,
      awayPlayer: opponent,
      round: 1,
    );

    expect(
      spokenMatchLabel(
        match,
        const AudioAnnouncementPreferences(
          nameFormat: AnnouncementNameFormat.firstNameLastInitial,
        ),
        {'player': profile},
      ),
      'Ada L. gegen Spieler 1',
    );
    expect(
      spokenMatchLabel(
        match,
        const AudioAnnouncementPreferences(
          nameFormat: AnnouncementNameFormat.firstNameLastInitial,
          speakNicknameWhenAvailable: true,
        ),
        {'player': profile},
      ),
      'Enchantress gegen Spieler 1',
    );
  });

  testWidgets('audio defaults panel starts collapsed and saves its controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: const [AudioAnnouncementDefaultsPanel()]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ton Modus Einstellungen'), findsOneWidget);
    expect(
      find.byType(DropdownButtonFormField<AnnouncementNameFormat>),
      findsNothing,
    );

    await tester.tap(find.text('Ton Modus Einstellungen'));
    await tester.pumpAndSettle();
    expect(
      find.byType(DropdownButtonFormField<AnnouncementNameFormat>),
      findsOneWidget,
    );
    expect(find.byType(CheckboxListTile), findsOneWidget);

    await tester.tap(
      find.byType(DropdownButtonFormField<AnnouncementNameFormat>),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Vorname + ersten Buchstaben des Nachnamens aussprechen').last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();

    final settings = await AudioAnnouncementPreferencesStorage().load();
    expect(settings.nameFormat, AnnouncementNameFormat.firstNameLastInitial);
    expect(settings.speakNicknameWhenAvailable, isTrue);
  });

  testWidgets('audio defaults panel handles small and large text layouts', (
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
            body: ListView(children: const [AudioAnnouncementDefaultsPanel()]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ton Modus Einstellungen'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Viewport $size');
    }
  });
}
