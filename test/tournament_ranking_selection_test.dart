import 'dart:async';
import 'dart:io';

import 'package:dart_tournament_manager/features/tournaments/application/tournament_run_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/engines/group_position_editor.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/creation/stage_setup_widgets.dart'
    show GroupTieBreakerSetup;
import 'package:dart_tournament_manager/features/tournaments/presentation/pages/tournament_results_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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

  testWidgets(
    'tournament settings show elapsed time and the fixed clock panel',
    (tester) async {
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
            widget is TextField &&
            widget.decoration?.labelText == 'Turniername',
      );
      final saveButton = find.widgetWithText(FilledButton, 'Namen speichern');
      expect(
        tester.getRect(nameField).right,
        lessThan(tester.getRect(saveButton).left),
      );
      expect(find.text('Laufzeit 0 h 3 min'), findsOneWidget);
      expect(find.text('Turnieruhr'), findsOneWidget);
      expect(find.text('Prognose nach erstem Ergebnis'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a saved tournament name can be copied into settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final previous = fixture()
      ..name = 'Vorheriges Turnier'
      ..updatedAt = DateTime.utc(2025);
    final current = fixture()
      ..name = 'Aktuelles Turnier'
      ..stages.add(const TournamentStage(name: 'Gruppen', type: 'groups'));
    final storage = _ListTournamentStorage([previous, current]);

    await tester.pumpWidget(
      MaterialApp(
        home: TournamentRunPage(
          tournament: current,
          tournamentStorage: storage,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Einstellungen'));
    await tester.pump(const Duration(milliseconds: 500));
    final openNamePicker = find.text('Name eines anderen Turniers öffnen');
    await tester.ensureVisible(openNamePicker);
    await tester.tap(openNamePicker);
    await tester.pumpAndSettle();
    expect(find.text('Vorheriges Turnier'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Vorheriges Turnier'));
    await tester.pumpAndSettle();

    final nameField = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Turniername',
      ),
    );
    expect(nameField.controller?.text, 'Vorheriges Turnier');
    expect(current.name, 'Aktuelles Turnier');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('name picker shows the newest tournament date first', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final older = CreatedTournament.fromJson({
      ...fixture().toJson(),
      'id': 'older',
      'name': 'Älteres Turnier',
      'startedAt': DateTime(2025, 1, 1).toIso8601String(),
    });
    final newer = CreatedTournament.fromJson({
      ...fixture().toJson(),
      'id': 'newer',
      'name': 'Neueres Turnier',
      'startedAt': DateTime(2026, 1, 1).toIso8601String(),
    });
    final current = fixture()
      ..name = 'Aktuelles Turnier'
      ..stages.add(const TournamentStage(name: 'Gruppen', type: 'groups'));
    final storage = _ListTournamentStorage([older, current, newer]);

    await tester.pumpWidget(
      MaterialApp(
        home: TournamentRunPage(
          tournament: current,
          tournamentStorage: storage,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Einstellungen'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Name eines anderen Turniers öffnen'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Neueres Turnier')).dy,
      lessThan(tester.getTopLeft(find.text('Älteres Turnier')).dy),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('group editing remains enabled when all stages are reset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tournament = fixture()
      ..completedStageIndexes.add(0)
      ..finishedAt = DateTime(2026, 1, 1)
      ..stages.add(const TournamentStage(name: 'Gruppen', type: 'groups'));

    await tester.pumpWidget(
      MaterialApp(home: TournamentRunPage(tournament: tournament)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Einstellungen'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('Gruppen verwalten'));

    final button = find.widgetWithText(OutlinedButton, 'Bearbeiten');
    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('group editing is enabled when all matches are annulled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tournament = fixture()
      ..stages.add(const TournamentStage(name: 'Gruppen', type: 'groups'));
    final stage = tournament.runStages.first as GroupTournamentRunStage;
    for (final match in stage.groups.expand((group) => group.matches)) {
      match
        ..isAnnulled = true
        ..startedAt = DateTime(2026, 1, 1);
    }

    await tester.pumpWidget(
      MaterialApp(home: TournamentRunPage(tournament: tournament)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Einstellungen'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('Gruppen verwalten'));

    final button = find.widgetWithText(OutlinedButton, 'Bearbeiten');
    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
    expect(GroupPositionEditor.canEdit(stage), isTrue);
    final firstPlayer = stage.groups.first.players.first;
    final secondPlayer = stage.groups.first.players.last;
    expect(GroupPositionEditor.swap(stage, firstPlayer, secondPlayer), isTrue);
    expect(
      stage.groups
          .expand((group) => group.matches)
          .every(
            (match) =>
                !match.isAnnulled &&
                match.startedAt == null &&
                match.finishedAt == null,
          ),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('group editing explains why it is disabled after a result', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tournament = fixture()
      ..stages.add(const TournamentStage(name: 'Gruppen', type: 'groups'));
    final group =
        (tournament.runStages.first as GroupTournamentRunStage).groups.first;
    group.matches.first
      ..homeLegs = 2
      ..awayLegs = 0;

    await tester.pumpWidget(
      MaterialApp(home: TournamentRunPage(tournament: tournament)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Einstellungen'));
    await tester.pump(const Duration(milliseconds: 500));
    final button = find.widgetWithText(OutlinedButton, 'Bearbeiten');
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(button));
    await mouse.moveTo(tester.getCenter(button));
    await tester.pumpAndSettle();
    expect(find.textContaining('bevor Ergebnisse vorliegen'), findsOneWidget);
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

class _ListTournamentStorage extends TournamentStorage {
  _ListTournamentStorage(this.tournaments);
  final List<CreatedTournament> tournaments;

  @override
  Future<List<CreatedTournament>> loadTournaments() async => tournaments;
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
