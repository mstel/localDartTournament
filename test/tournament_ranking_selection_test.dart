import 'dart:async';
import 'dart:io';

import 'package:dart_tournament_manager/features/tournaments/application/tournament_run_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/creation/stage_setup_widgets.dart'
    show GroupTieBreakerSetup;
import 'package:dart_tournament_manager/features/tournaments/presentation/pages/tournament_results_page.dart';
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
      final storage = _RecordingTournamentStorage();
      final tournament = fixture()
        ..countsForRanking = true
        ..rankingIds.add('club-ranking')
        ..plannedMinutes = 45
        ..stages.add(const TournamentStage(name: 'Gruppen', type: 'groups'));
      await storage.saveTournament(tournament);
      final controller = _ControlledRunController(storage: storage);

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
      await tester.ensureVisible(find.text('Ranglistenoptionen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ranglistenoptionen'));
      await tester.pump(const Duration(milliseconds: 500));
      final setting = find.widgetWithText(
        SwitchListTile,
        'Für Rangliste berücksichtigen',
      );
      await tester.ensureVisible(setting);
      await tester.pump();
      expect(tester.widget<SwitchListTile>(setting).value, isTrue);
      final onChanged = tester.widget<SwitchListTile>(setting).onChanged!;

      onChanged(false);
      await tester.pump();
      expect(tournament.countsForRanking, isFalse);
      expect(tournament.rankingIds, isEmpty);
      expect(tester.widget<SwitchListTile>(setting).onChanged, isNull);
      controller.completePendingSave();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.widget<SwitchListTile>(setting).value, isFalse);
      expect(tester.widget<SwitchListTile>(setting).onChanged, isNotNull);
      final persisted = (await storage.loadTournaments()).single;
      expect(persisted.countsForRanking, isFalse);
      expect(persisted.rankingIds, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('tournament settings show a compact name field and live clock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tournament = fixture()
      ..stages.add(const TournamentStage(name: 'Gruppen', type: 'groups'))
      ..startedAt = DateTime.now().subtract(
        const Duration(minutes: 3, seconds: 12),
      );

    await tester.pumpWidget(
      MaterialApp(home: TournamentRunPage(tournament: tournament)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Einstellungen'));
    await tester.pump(const Duration(milliseconds: 500));

    final nameField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Turniername',
    );
    final saveButton = find.widgetWithText(FilledButton, 'Namen speichern');
    expect(
      tester.getRect(nameField).right,
      lessThan(tester.getRect(saveButton).left),
    );
    expect(find.textContaining('Status: Läuft aktiv · 00:03:'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'running group tie-breakers are applied from a separate settings panel',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final storage = _RecordingTournamentStorage();
      final tournament = fixture()
        ..plannedMinutes = 60
        ..stages.add(
          const TournamentStage(
            name: 'Gruppen',
            type: 'groups',
            groupSizes: [6],
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: TournamentRunPage(
            tournament: tournament,
            runController: TournamentRunController(storage: storage),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Einstellungen'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(find.text('Tie Breaker Einstellungen'));
      await tester.pump();
      await tester.tap(find.text('Tie Breaker Einstellungen'));
      await tester.pump(const Duration(milliseconds: 500));

      final tieBreakerSetup = tester.widget<GroupTieBreakerSetup>(
        find.byType(GroupTieBreakerSetup),
      );
      expect(tieBreakerSetup.tieBreakers, hasLength(4));
      final expected = List<String>.from(tieBreakerSetup.tieBreakers);
      final first = expected.removeAt(1);
      expected.insert(0, first);
      await tieBreakerSetup.onMoveTieBreaker(1, -1);
      await tester.pump();

      expect(
        tester
            .widget<GroupTieBreakerSetup>(find.byType(GroupTieBreakerSetup))
            .tieBreakers,
        expected,
      );
      expect(tournament.stages.single.groupTieBreakers, isNot(expected));
      expect(
        (tournament.runStages.single as GroupTournamentRunStage).tieBreakers,
        isNot(expected),
      );
      final applyButton = find.widgetWithText(FilledButton, 'Übernehmen');
      final applyAction = tester.widget<FilledButton>(applyButton).onPressed;
      expect(applyAction, isNotNull);
      applyAction!();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tournament.stages.single.groupTieBreakers, expected);
      expect(
        (tournament.runStages.single as GroupTournamentRunStage).tieBreakers,
        expected,
      );
      expect(
        (await storage.loadTournaments()).single.stages.single.groupTieBreakers,
        expected,
      );
      expect(
        find.text(
          'Tie-Breaker übernommen. Tabelle und Prognose wurden aktualisiert.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('final results use the current group tie-breaker order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final players = [
      for (var index = 1; index <= 4; index++)
        TournamentPlayer.generated(index),
    ];
    final a = players[0];
    final b = players[1];
    final c = players[2];
    final d = players[3];
    final matches = [
      GroupMatch(
        homePlayer: a,
        awayPlayer: b,
        homeLegs: 2,
        awayLegs: 1,
        round: 1,
      ),
      GroupMatch(
        homePlayer: a,
        awayPlayer: c,
        homeLegs: 1,
        awayLegs: 0,
        round: 1,
      ),
      GroupMatch(
        homePlayer: a,
        awayPlayer: d,
        homeLegs: 1,
        awayLegs: 0,
        round: 1,
      ),
      GroupMatch(
        homePlayer: b,
        awayPlayer: c,
        homeLegs: 3,
        awayLegs: 0,
        round: 1,
      ),
      GroupMatch(
        homePlayer: b,
        awayPlayer: d,
        homeLegs: 3,
        awayLegs: 0,
        round: 1,
      ),
      GroupMatch(
        homePlayer: c,
        awayPlayer: d,
        homeLegs: 1,
        awayLegs: 0,
        round: 1,
      ),
    ];
    final stage = TournamentStage(
      name: 'Gruppenphase',
      type: 'groups',
      groupSizes: const [4],
      groupTieBreakers: const [
        'headToHead',
        'points',
        'legDifference',
        'legsFor',
      ],
    );
    final tournament = CreatedTournament(
      name: 'Abschlusstest',
      players: players,
      stages: [stage],
      runStages: [
        GroupTournamentRunStage(
          name: stage.name,
          groupPlayType: 'round_robin',
          qualificationPlan: null,
          groups: [
            TournamentGroup(
              name: 'Gruppe A',
              playType: 'round_robin',
              players: players,
              matches: matches,
            ),
          ],
          tieBreakers: stage.groupTieBreakers,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: TournamentResultsPage(tournament: tournament)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final podiumNames = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .where((text) => players.any((player) => player.name == text))
        .toList();
    expect(podiumNames.take(2), ['Spieler 1', 'Spieler 2']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _RecordingTournamentStorage extends TournamentStorage {
  Map<String, dynamic>? _savedTournament;

  @override
  Future<void> saveTournament(CreatedTournament tournament) async {
    _savedTournament = tournament.toJson();
  }

  @override
  Future<List<CreatedTournament>> loadTournaments() async {
    final saved = _savedTournament;
    return saved == null
        ? []
        : [CreatedTournament.fromJson(Map<String, dynamic>.from(saved))];
  }
}

class _ControlledRunController extends TournamentRunController {
  _ControlledRunController({required TournamentStorage storage})
    : super(storage: storage);
  final _pendingSave = Completer<void>();
  var _saveCount = 0;

  @override
  Future<void> saveProgress({
    required CreatedTournament tournament,
    required int activeStageIndex,
    required Set<int> completedStageIndexes,
  }) async {
    _saveCount++;
    if (_saveCount > 1) {
      await _pendingSave.future;
      await super.saveProgress(
        tournament: tournament,
        activeStageIndex: activeStageIndex,
        completedStageIndexes: completedStageIndexes,
      );
    }
  }

  void completePendingSave() {
    _pendingSave.complete();
  }
}
