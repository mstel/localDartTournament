import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/second_screen_widget_placement.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

void main() {
  test('board metadata and saved monitor layouts survive tournament JSON', () {
    final tournament = CreatedTournament(
      name: 'TV-Test',
      players: const [],
      stages: const [],
      runStages: const [],
      boardCount: 2,
      directorBoardNames: const {1: 'Bühne links'},
      directorBoardLiveUrls: const {1: 'https://example.test/board/1'},
      secondScreenLayouts: const {
        'Vereins-TV': [
          SecondScreenWidgetPlacement(
            widgetId: 'boards',
            widthUnits: 3,
            heightUnits: 2,
          ),
        ],
      },
      secondScreenActiveLayout: 'Vereins-TV',
    );

    final restored = CreatedTournament.fromJson(tournament.toJson());

    expect(restored.boardDisplayName(1), 'Bühne links');
    expect(restored.boardDisplayName(2), 'Board 2');
    expect(restored.directorBoardLiveUrls[1], 'https://example.test/board/1');
    expect(restored.secondScreenActiveLayout, 'Vereins-TV');
    expect(
      restored.secondScreenLayouts['Vereins-TV']?.single.toJson(),
      const SecondScreenWidgetPlacement(
        widgetId: 'boards',
        widthUnits: 3,
        heightUnits: 2,
      ).toJson(),
    );
  });

  test('saved widget sizes are bounded when reading tournament JSON', () {
    final placement = SecondScreenWidgetPlacement.fromJson({
      'widgetId': 'recent',
      'widthUnits': 99,
      'heightUnits': 0,
    });

    expect(placement.widthUnits, 4);
    expect(placement.heightUnits, 1);
  });

  test('stale tournament saves preserve a monitor layout from another window', () async {
    final directory = await Directory.systemTemp.createTemp(
      'monitor-layout-storage-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File(
      '${directory.path}${Platform.pathSeparator}tournaments.json',
    );
    final storage = TournamentStorage(file: file);
    final tournament = CreatedTournament(
      name: 'TV-Test',
      players: const [],
      stages: const [],
      runStages: const [],
    );
    await storage.saveTournament(tournament);

    final stalePageCopy = (await storage.loadTournaments()).single;
    final monitorCopy = (await storage.loadTournaments()).single
      ..secondScreenLayouts['Vereins-TV'] = const [
        SecondScreenWidgetPlacement(widgetId: 'liveBoard', widthUnits: 2),
      ]
      ..secondScreenActiveLayout = 'Vereins-TV';
    await storage.saveTournament(monitorCopy);

    stalePageCopy.name = 'Aktualisierter Turniername';
    await storage.saveTournament(stalePageCopy);
    final saved = (await storage.loadTournaments()).single;

    expect(saved.name, 'Aktualisierter Turniername');
    expect(saved.secondScreenActiveLayout, 'Vereins-TV');
    expect(
      saved.secondScreenLayouts['Vereins-TV']?.single.widgetId,
      'liveBoard',
    );
  });
}
