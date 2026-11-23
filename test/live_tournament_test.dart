import 'dart:convert';

import 'package:dart_tournament_manager/features/live/application/live_tournament_config.dart';
import 'package:dart_tournament_manager/features/live/application/live_tournament_payload_builder.dart';
import 'package:dart_tournament_manager/features/live/application/live_tournament_publisher.dart';
import 'package:dart_tournament_manager/features/live/data/live_tournament_uploader.dart';
import 'package:dart_tournament_manager/features/live/presentation/live_tournament_settings_panel.dart';
import 'package:dart_tournament_manager/features/statistics/domain/best_performance.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 23, 20);

LiveTournamentPayloadBuilder _fixedBuilder() =>
    LiveTournamentPayloadBuilder(now: () => _now);

PlayerProfile _lenaProfile() => PlayerProfile(
  id: 'p1',
  firstName: 'Lena',
  lastName: 'Mustermann',
  country: 'DE',
  city: 'Berlin',
  dartsSetupJson: '{"nickname":"Lollo"}',
  createdAt: _now,
  isActive: true,
);

CreatedTournament _tournament({bool liveVisible = true}) {
  final lena = TournamentPlayer(
    profileId: 'p1',
    name: 'Lena Mustermann (Lollo)',
    compactName: 'Lollo',
    isGenerated: false,
  );
  final tom = TournamentPlayer(
    profileId: 'p2',
    name: 'Tom Schmidt',
    compactName: 'T. Schmidt',
    isGenerated: false,
  );
  final match = GroupMatch(
    homePlayer: lena,
    awayPlayer: tom,
    round: 1,
    homeLegs: 3,
    awayLegs: 1,
    bestPerformances: const [
      BestPerformance(
        type: BestPerformanceType.score180,
        playerName: 'Lena Mustermann',
        playerProfileId: 'p1',
        value: 180,
      ),
    ],
  );
  final group = TournamentGroup(
    name: 'Gruppe A',
    playType: 'round_robin',
    players: [lena, tom],
    matches: [match],
  );
  const stage = TournamentStage(
    name: 'Gruppenphase',
    type: 'groups',
    groupSizes: [8],
    qualifiedParticipantCount: 8,
    gameFormat: TournamentGameFormat(),
  );
  final runStage = GroupTournamentRunStage(
    name: 'Gruppenphase',
    groupPlayType: 'round_robin',
    groups: [group],
    qualificationPlan: const QualificationPlan(
      totalQualifiers: 8,
      fixedPerGroup: 8,
      extraCount: 0,
      extraRank: 0,
      eligibleGroupSize: 8,
      extraGroups: [],
    ),
    tieBreakers: const ['points', 'legDifference'],
  );
  return CreatedTournament(
    id: 'live-test',
    name: 'Vereinsabend',
    players: [lena, tom],
    stages: [stage],
    runStages: [runStage],
    tournamentDate: DateTime(2026, 11, 23),
    startedAt: DateTime(2026, 11, 23, 18),
    finishedAt: DateTime(2026, 11, 23, 20),
  )..tournamentSettings = TournamentSettings(liveVisible: liveVisible);
}

void _collectKeys(Object? value, Set<String> keys) {
  if (value is Map) {
    for (final entry in value.entries) {
      keys.add('${entry.key}');
      _collectKeys(entry.value, keys);
    }
  } else if (value is Iterable) {
    for (final item in value) {
      _collectKeys(item, keys);
    }
  }
}

void main() {
  test('live flag is additive to tournament settings JSON', () {
    final tournament = _tournament();
    final restored = CreatedTournament.fromJson(tournament.toJson());
    expect(restored.tournamentSettings.liveVisible, isTrue);
    expect(
      (tournament.toJson()['tournamentSettings'] as Map)['version'],
      TournamentSettings.schemaVersion,
    );

    final old = _tournament(liveVisible: false);
    final oldJson = old.toJson()['tournamentSettings'] as Map<String, dynamic>;
    oldJson.remove('liveVisible');
    expect(
      TournamentSettings.fromJson(oldJson).liveVisible,
      isFalse,
    );
  });

  test('format lines cover the requested spectator example', () {
    final tournament = _tournament();
    tournament.stages.add(
      const TournamentStage(
        name: 'Finale',
        type: 'single_knockout',
        gameFormat: TournamentGameFormat(),
      ),
    );
    tournament.runStages.add(
      KnockoutTournamentRunStage(
        name: 'Finale',
        rounds: const [],
        placementMatches: [
          GroupMatch(
            homePlayer: tournament.players.first,
            awayPlayer: tournament.players.last,
            round: 1,
          ),
        ],
      ),
    );

    final format =
        _fixedBuilder().build(tournament).toJson()['tournament']['format']
            as List<Object?>;
    expect(format, contains('501 Double Out Best of 3 Legs'));
    expect(format, contains('Gruppen'));
    expect(format, contains('Top 8 weiter'));
    expect(format, contains('Single KO Finale 501 Double Out Best of 3 Legs'));
    expect(format, contains('Spiel um Platz 3'));
    expect(
      format.any((line) => '$line'.startsWith('Tie-Breaker:')),
      isTrue,
    );
  });

  test('payload anonymises names and contains only allowed content', () {
    final profiles = {'p1': _lenaProfile()};
    final payload = _fixedBuilder()
        .build(_tournament(), profiles: profiles);
    final json = payload.toJson();
    final text = jsonEncode(json);

    expect(text, contains('Lena M.'));
    expect(text, contains('Tom S.'));
    expect(text, isNot(contains('Mustermann')));
    expect(text, isNot(contains('Lollo')));
    expect(text, isNot(contains('T. Schmidt')));

    final keys = <String>{};
    _collectKeys(json, keys);
    for (final forbidden in const [
      'elo',
      'ranking',
      'achievements',
      'boards',
      'boardNumber',
      'hints',
      'insights',
      'activityLog',
      'tournamentNotes',
      'soundModeEnabled',
      'pastTournaments',
    ]) {
      expect(keys, isNot(contains(forbidden)), reason: '$forbidden leaked');
    }

    expect(
      json['tournament']['format'],
      contains('501 Double Out Best of 3 Legs'),
    );
    expect(json['tournament']['format'], contains('Gruppen'));
    expect(json['tournament']['format'], contains('Top 8 weiter'));
    expect(json['tournament']['status'], 'finished');
    expect(json['endScreen']['winner'], 'Lena M.');
    expect(json['bestPerformances'].single['player'], 'Lena M.');
  });

  test('publisher uploads viewer and payload only while live', () async {
    final uploader = InMemoryLiveTournamentUploader()
      ..currentUserId = 'operator';
    final publisher = LiveTournamentPublisher(
      uploader: uploader,
      builder: _fixedBuilder(),
      viewerHtml: '<html>live</html>',
    );

    final disabled = await publisher.publish(_tournament(liveVisible: false));
    expect(disabled.status, LivePublishStatus.disabled);
    expect(uploader.json, isEmpty);
    expect(uploader.viewer, isEmpty);

    final first = await publisher.publish(_tournament());
    expect(first.status, LivePublishStatus.published);
    expect(first.url, LiveTournamentConfig.viewerUrl);
    expect(uploader.jsonUploadCount, 1);
    expect(uploader.viewerUploadCount, 1);
    expect(uploader.json.containsKey('${LiveTournamentConfig.channel}/latest.json'), isTrue);

    await publisher.publish(_tournament());
    expect(uploader.jsonUploadCount, 1, reason: 'unchanged payload was re-uploaded');

    await publisher.unpublish();
    expect(uploader.json, isEmpty);
    expect(uploader.deleted, contains('${LiveTournamentConfig.channel}/latest.json'));
  });

  testWidgets(
    'live settings expose the exact label, URL and QR code',
    (tester) async {
      final tournament = _tournament(liveVisible: false);
      final uploader = InMemoryLiveTournamentUploader()
        ..currentUserId = 'operator';
      final publisher = LiveTournamentPublisher(
        uploader: uploader,
        builder: _fixedBuilder(),
        viewerHtml: '<html>live</html>',
      );
      var opened = '';
      Future<void> onChanged(bool value) async {
        tournament.tournamentSettings = tournament.tournamentSettings.copyWith(
          liveVisible: value,
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LiveTournamentSettingsPanel(
                tournament: tournament,
                publisher: publisher,
                onLiveVisibleChanged: onChanged,
                profiles: const {},
                onOpenUrl: (url) async => opened = url,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Turnier Live sichtbar machen?'), findsOneWidget);
      expect(find.byKey(const ValueKey('live-viewer-url')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('live-visible-switch')));
      await tester.pumpAndSettle();

      expect(tournament.tournamentSettings.liveVisible, isTrue);
      expect(find.byKey(const ValueKey('live-viewer-url')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-qr-code')), findsOneWidget);
      expect(uploader.json, isNotEmpty);

      await tester.tap(find.byKey(const ValueKey('live-open-url')));
      await tester.pumpAndSettle();
      expect(opened, LiveTournamentConfig.viewerUrl);
    },
  );

  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('live settings wrap at $size with 200 percent text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tournament = _tournament();
      final uploader = InMemoryLiveTournamentUploader()
        ..currentUserId = 'operator';
      final publisher = LiveTournamentPublisher(
        uploader: uploader,
        builder: _fixedBuilder(),
        viewerHtml: '<html>live</html>',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: size, textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: LiveTournamentSettingsPanel(
                  tournament: tournament,
                  publisher: publisher,
                  onLiveVisibleChanged: (value) async {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Turnier Live sichtbar machen?'), findsOneWidget);
      expect(find.byKey(const ValueKey('live-viewer-url')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
