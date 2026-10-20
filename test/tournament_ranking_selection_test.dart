import 'dart:io';
import 'dart:async';

import 'package:dart_tournament_manager/features/tournaments/application/tournament_run_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show TournamentRunPage;

import 'order_of_play_test.dart' show fixture;

void main() {
  test(
    'ranking selections loaded from storage can be removed and saved',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ranking-selection-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final storage = TournamentStorage(
        file: File('${directory.path}/tournaments.json'),
      );
      final original = fixture()
        ..countsForRanking = true
        ..rankingIds.add('club-ranking');

      await storage.saveTournament(original);
      final loaded = (await storage.loadTournaments()).single;
      loaded.countsForRanking = false;
      loaded.rankingIds.clear();
      await storage.saveTournament(loaded);

      final saved = (await storage.loadTournaments()).single;
      expect(saved.countsForRanking, isFalse);
      expect(saved.rankingIds, isEmpty);
    },
  );

  testWidgets(
    'ranking participation can be disabled and saved in a running tournament',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = _ControlledRunController();
      final tournament = fixture()
        ..countsForRanking = true
        ..rankingIds.add('club-ranking')
        ..plannedMinutes = 45
        ..stages.add(const TournamentStage(name: 'Gruppen', type: 'groups'));

      await tester.pumpWidget(
        MaterialApp(
          home: TournamentRunPage(
            tournament: tournament,
            runController: controller,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Einstellungen'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      final setting = find.widgetWithText(
        SwitchListTile,
        'Für Rangliste/n berücksichtigen',
      );
      expect(tester.widget<SwitchListTile>(setting).value, isTrue);

      await tester.tap(setting);
      await tester.pump();
      expect(tournament.countsForRanking, isFalse);
      expect(tournament.rankingIds, isEmpty);
      expect(tester.widget<SwitchListTile>(setting).onChanged, isNull);
      controller.completePendingSave();
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(setting).value, isFalse);
      expect(tester.widget<SwitchListTile>(setting).onChanged, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _ControlledRunController extends TournamentRunController {
  final _pendingSave = Completer<void>();
  var _saveCount = 0;

  @override
  Future<void> saveProgress({
    required CreatedTournament tournament,
    required int activeStageIndex,
    required Set<int> completedStageIndexes,
  }) async {
    _saveCount++;
    if (_saveCount > 1) await _pendingSave.future;
  }

  void completePendingSave() {
    _pendingSave.complete();
  }
}
