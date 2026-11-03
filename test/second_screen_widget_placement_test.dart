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
            startsNewRow: true,
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
        startsNewRow: true,
      ).toJson(),
    );
  });

  test('saved widget sizes are bounded when reading tournament JSON', () {
    final minimum = SecondScreenWidgetPlacement.fromJson({
      'widgetId': 'recent',
      'widthUnits': 99,
      'heightUnits': 0,
    });

    expect(minimum.widthUnits, 4);
    expect(minimum.heightUnits, 0.5);

    final intermediate = SecondScreenWidgetPlacement.fromJson({
      'widgetId': 'boards',
      'widthUnits': 2,
      'heightUnits': 1.5,
    });
    expect(intermediate.heightUnits, 1.5);
    expect(
      SecondScreenWidgetPlacement.fromJson(intermediate.toJson()).heightUnits,
      1.5,
    );
    expect(
      SecondScreenWidgetPlacement.fromJson({
        'widgetId': 'recent',
        'startsNewRow': true,
      }).startsNewRow,
      isTrue,
    );
    expect(
      SecondScreenWidgetPlacement.fromJson({
        'widgetId': 'standings',
        'heightUnits': 3.8,
      }).heightUnits,
      3,
    );
    final columnPlacement = SecondScreenWidgetPlacement.fromJson({
      'widgetId': 'standings',
      'columnIndex': 1,
    });
    expect(columnPlacement.columnIndex, 1);
    expect(
      SecondScreenWidgetPlacement.fromJson(
        columnPlacement.toJson(),
      ).columnIndex,
      1,
    );
    expect(
      SecondScreenWidgetPlacement.fromJson({
        'widgetId': 'boards',
        'columnIndex': 7,
      }).columnIndex,
      1,
    );
    expect(
      SecondScreenWidgetPlacement.fromJson({'widgetId': 'boards'}).columnIndex,
      isNull,
    );
    expect(
      SecondScreenWidgetPlacement(
        widgetId: 'nextStagePreview',
      ).toJson()['widgetId'],
      'nextStagePreview',
    );
  });

  test(
    'stale tournament saves preserve a monitor layout from another window',
    () async {
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
    },
  );

  test(
    'layout updates and deletes apply to the latest stored tournament',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'monitor-layout-update-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final storage = TournamentStorage(
        file: File(
          '${directory.path}${Platform.pathSeparator}tournaments.json',
        ),
      );
      final tournament = CreatedTournament(
        name: 'TV-Test',
        players: const [],
        stages: const [],
        runStages: const [],
      );
      await storage.saveTournament(tournament);

      final staleCopy = (await storage.loadTournaments()).single;
      final latestCopy = (await storage.loadTournaments()).single
        ..secondScreenLayouts['Vereins-TV'] = const [
          SecondScreenWidgetPlacement(widgetId: 'boards', heightUnits: 2),
        ]
        ..secondScreenActiveLayout = 'Vereins-TV';
      await storage.saveTournament(latestCopy);

      await storage.saveSecondScreenLayout(
        tournament: staleCopy,
        name: 'Vereins-TV',
        placements: const [
          SecondScreenWidgetPlacement(widgetId: 'boards', heightUnits: 1.5),
        ],
        activate: true,
      );
      expect(
        (await storage.loadTournaments())
            .single
            .secondScreenLayouts['Vereins-TV']
            ?.single
            .heightUnits,
        1.5,
      );

      await storage.saveSecondScreenLayout(
        tournament: staleCopy,
        name: 'Vereins-TV',
        placements: null,
        activate: false,
      );
      final saved = (await storage.loadTournaments()).single;
      expect(saved.secondScreenLayouts, isEmpty);
      expect(saved.secondScreenActiveLayout, isNull);
    },
  );
}
