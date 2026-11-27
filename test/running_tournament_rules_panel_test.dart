import 'package:dart_tournament_manager/features/league/domain/league_match.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_run_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/engines/qualification_plan_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/running_tournament_rules_panel.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show TournamentRunPage;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _rulesTitle =
    'Weiterkommensregeln, Auslosungsmethode & Optionale Platzierungsspiele';
const _panelKey = ValueKey('running-tournament-rules-panel');
const _saveKey = ValueKey('running-rules-save');

class _MemoryTournamentStorage extends TournamentStorage {
  CreatedTournament? _saved;

  @override
  Future<void> saveTournament(CreatedTournament tournament) async {
    _saved = CreatedTournament.fromJson(tournament.toJson());
  }

  @override
  Future<List<CreatedTournament>> loadTournaments() async =>
      _saved == null ? const [] : [_saved!];
}

List<GroupMatch> _roundRobin(List<TournamentPlayer> players) => [
  for (var home = 0; home < players.length; home++)
    for (var away = home + 1; away < players.length; away++)
      GroupMatch(
        homePlayer: players[home],
        awayPlayer: players[away],
        round: 1,
      ),
];

CreatedTournament _groupThenKnockoutTournament({
  int qualifiedCount = 4,
  int? knockoutAdvancingCount = 4,
  String knockoutSeedingMode = 'cross',
  List<int> placementPlaces = const [],
}) {
  final players = [
    for (var index = 1; index <= 8; index++) TournamentPlayer.generated(index),
  ];
  final groups = [
    TournamentGroup(
      name: 'A',
      playType: 'round_robin',
      players: players.sublist(0, 4),
      matches: _roundRobin(players.sublist(0, 4)),
    ),
    TournamentGroup(
      name: 'B',
      playType: 'round_robin',
      players: players.sublist(4, 8),
      matches: _roundRobin(players.sublist(4, 8)),
    ),
  ];
  final groupStage = TournamentStage(
    name: 'Gruppen',
    type: 'groups',
    groupCount: 2,
    groupSizes: const [4, 4],
    qualifiedParticipantCount: qualifiedCount,
    qualificationAutoAdjust: true,
    qualificationAdvancementPolicy: 'larger_group',
    groupTieBreakers: defaultGroupTieBreakers,
  );
  final plan = const QualificationPlanEngine().build(
    groupSizes: const [4, 4],
    totalQualifiers: qualifiedCount,
    autoAdjust: true,
    advancementPolicy: 'larger_group',
  );
  final knockoutStage = TournamentStage(
    name: 'KO',
    type: 'single_knockout',
    knockoutParticipantCount: qualifiedCount,
    knockoutAdvancingCount: knockoutAdvancingCount,
    knockoutSeedingMode: knockoutSeedingMode,
    placementPlaces: placementPlaces,
  );
  final koPlayers = players.take(qualifiedCount).toList();
  final firstRound = <GroupMatch>[
    for (var i = 0; i < koPlayers.length ~/ 2; i++)
      GroupMatch(
        homePlayer: koPlayers[i],
        awayPlayer: koPlayers[koPlayers.length - 1 - i],
        round: 1,
      ),
  ];
  return CreatedTournament(
    name: 'Gruppen+KO Regeln',
    players: players,
    stages: [groupStage, knockoutStage],
    runStages: [
      GroupTournamentRunStage(
        name: groupStage.name,
        groupPlayType: 'round_robin',
        groups: groups,
        qualificationPlan: plan,
        tieBreakers: defaultGroupTieBreakers,
      ),
      KnockoutTournamentRunStage(
        name: knockoutStage.name,
        participants: koPlayers,
        eliminationLossLimit: 1,
        rounds: [
          firstRound,
          [
            GroupMatch(round: 2, label: 'Halbfinale'),
            GroupMatch(round: 2, label: 'Halbfinale'),
          ],
          [GroupMatch(round: 3, label: 'Finale')],
        ],
      ),
    ],
  );
}

CreatedTournament _groupTournament({
  bool ranking = false,
  Set<int> completedStageIndexes = const {},
  List<TournamentPlayer>? players,
  List<int> groupSizes = const [4, 4],
  int qualifiedCount = 4,
  bool withResult = false,
  LeagueMatch? leagueMatch,
}) {
  final roster =
      players ??
      [
        for (var index = 1; index <= 8; index++)
          TournamentPlayer.generated(index),
      ];
  var cursor = 0;
  final groups = <TournamentGroup>[];
  for (var index = 0; index < groupSizes.length; index++) {
    final groupPlayers = roster.skip(cursor).take(groupSizes[index]).toList();
    cursor += groupSizes[index];
    groups.add(
      TournamentGroup(
        name: groupLabel(index + 1),
        playType: 'round_robin',
        players: groupPlayers,
        matches: _roundRobin(groupPlayers),
      ),
    );
  }
  if (withResult) {
    groups.first.matches.first
      ..homeLegs = 2
      ..awayLegs = 1;
  }
  final config = TournamentStage(
    name: 'Gruppen',
    type: 'groups',
    groupCount: groupSizes.length,
    groupSizes: groupSizes,
    qualifiedParticipantCount: qualifiedCount,
    qualificationAutoAdjust: true,
    qualificationAdvancementPolicy: 'larger_group',
    groupTieBreakers: defaultGroupTieBreakers,
  );
  final plan = const QualificationPlanEngine().build(
    groupSizes: groupSizes,
    totalQualifiers: qualifiedCount,
    autoAdjust: true,
    advancementPolicy: 'larger_group',
  );
  return CreatedTournament(
    name: 'Regeln im Lauf',
    players: roster,
    leagueMatch: leagueMatch,
    countsForRanking: ranking,
    rankingIds: ranking ? const ['club-ranking'] : const [],
    stages: [config],
    runStages: [
      GroupTournamentRunStage(
        name: config.name,
        groupPlayType: 'round_robin',
        groups: groups,
        qualificationPlan: plan,
        tieBreakers: defaultGroupTieBreakers,
      ),
    ],
    completedStageIndexes: Set<int>.from(completedStageIndexes),
  );
}

CreatedTournament _knockoutTournament({
  bool withResult = false,
  int? knockoutAdvancingCount = 4,
  String knockoutSeedingMode = 'cross',
  List<int> placementPlaces = const [],
}) {
  final players = [
    for (var index = 1; index <= 8; index++) TournamentPlayer.generated(index),
  ];
  final firstRound = [
    GroupMatch(homePlayer: players[0], awayPlayer: players[7], round: 1),
    GroupMatch(homePlayer: players[1], awayPlayer: players[6], round: 1),
    GroupMatch(homePlayer: players[2], awayPlayer: players[5], round: 1),
    GroupMatch(homePlayer: players[3], awayPlayer: players[4], round: 1),
  ];
  if (withResult) {
    firstRound.first
      ..homeLegs = 2
      ..awayLegs = 1;
  }
  return CreatedTournament(
    name: 'KO-Regeln im Lauf',
    players: players,
    stages: [
      TournamentStage(
        name: 'KO',
        type: 'single_knockout',
        knockoutParticipantCount: 8,
        knockoutAdvancingCount: knockoutAdvancingCount,
        knockoutSeedingMode: knockoutSeedingMode,
        placementPlaces: placementPlaces,
      ),
    ],
    runStages: [
      KnockoutTournamentRunStage(
        name: 'KO',
        participants: players,
        eliminationLossLimit: 1,
        rounds: [
          firstRound,
          [
            GroupMatch(round: 2, label: 'Halbfinale'),
            GroupMatch(round: 2, label: 'Halbfinale'),
          ],
          [GroupMatch(round: 3, label: 'Finale')],
        ],
      ),
    ],
  );
}

Future<void> _pumpRunPage(
  WidgetTester tester, {
  required CreatedTournament tournament,
  required _MemoryTournamentStorage storage,
  Size size = const Size(1440, 1200),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget home = TournamentRunPage(
    tournament: tournament,
    tournamentStorage: storage,
    runController: TournamentRunController(storage: storage),
  );
  if (textScale != 1) {
    home = MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: home,
    );
  }
  await tester.pumpWidget(MaterialApp(home: home));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _pumpIsolatedPanel(
  WidgetTester tester, {
  required CreatedTournament tournament,
  required Size size,
  required double textScale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final draft = RunningRulesDraft.fromStage(tournament.stages.single);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: RunningTournamentRulesPanel(
                stage: tournament.stages.single,
                draft: draft,
                enabled: true,
                saving: false,
                onSave: () {},
                onChanged: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openSettings(WidgetTester tester) async {
  final settings = find.text('Einstellungen');
  if (settings.evaluate().isNotEmpty) {
    await tester.ensureVisible(settings);
    await tester.tap(settings);
  } else {
    // Bei 200 % Schrift wird die Navigation zum Dropdown; der aktuelle
    // Eintrag ist dann „Übersicht“ und „Einstellungen“ erst im Menü sichtbar.
    final selector = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField &&
          widget.decoration.labelText == 'Turnieransicht',
    );
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Einstellungen').last);
  }
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _expandRulesPanel(WidgetTester tester) async {
  final panel = find.byKey(_panelKey);
  await tester.ensureVisible(panel);
  final outer = find
      .descendant(of: panel, matching: find.byType(ExpansionTile))
      .first;
  await tester.tap(outer);
  await tester.pumpAndSettle();
}

void main() {
  for (final ranking in [false, true]) {
    testWidgets('settings show the exact rules title above tie breakers '
        '(ranking=$ranking)', (tester) async {
      final tournament = _groupTournament(ranking: ranking);
      final storage = _MemoryTournamentStorage();
      await _pumpRunPage(tester, tournament: tournament, storage: storage);
      await _openSettings(tester);

      final title = find.text(_rulesTitle);
      final tieBreakers = find.text('Tie Breaker Einstellungen');
      await tester.ensureVisible(tieBreakers);
      await tester.pumpAndSettle();

      expect(title, findsOneWidget);
      expect(tieBreakers, findsOneWidget);
      expect(
        tester.getTopLeft(title).dy,
        lessThan(tester.getTopLeft(tieBreakers).dy),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('league and adjusted matches hide the running rules panel', (
    tester,
  ) async {
    final base = _groupTournament();
    final league = CreatedTournament.fromJson({
      ...base.toJson(),
      'leagueMatch': LeagueMatch.adjusted(
        homeTeam: 'Heim',
        awayTeam: 'Gast',
        homePlayers: const ['Teilnehmer 1'],
        awayPlayers: const ['Teilnehmer 2'],
        singlesPerPlayer: 1,
        doublesCount: 0,
      ).toJson(),
    });
    final storage = _MemoryTournamentStorage();
    await _pumpRunPage(tester, tournament: league, storage: storage);
    await _openSettings(tester);

    expect(find.byKey(_panelKey), findsNothing);
    expect(find.text(_rulesTitle), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('team tournaments hide the running rules panel', (tester) async {
    final teams = [
      TournamentPlayer.team([
        TournamentPlayer.generated(1),
        TournamentPlayer.generated(2),
      ]),
      TournamentPlayer.team([
        TournamentPlayer.generated(3),
        TournamentPlayer.generated(4),
      ]),
    ];
    final tournament = _groupTournament(
      players: teams,
      groupSizes: const [2],
      qualifiedCount: 1,
    );
    final storage = _MemoryTournamentStorage();
    await _pumpRunPage(tester, tournament: tournament, storage: storage);
    await _openSettings(tester);

    expect(find.byKey(_panelKey), findsNothing);
    expect(find.text(_rulesTitle), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'group rules edit qualifier count and qualification details and persist',
    (tester) async {
      final tournament = _groupTournament();
      final storage = _MemoryTournamentStorage();
      await _pumpRunPage(
        tester,
        tournament: tournament,
        storage: storage,
        size: const Size(1440, 1400),
      );
      await _openSettings(tester);
      await _expandRulesPanel(tester);

      final panel = find.byKey(_panelKey);
      expect(
        find.byKey(const ValueKey('group-qualifier-count-field')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: panel,
          matching: find.text('Weiterkommen im Detail'),
        ),
        findsOneWidget,
      );
      final details = find.byKey(
        const ValueKey('running-rules-qualification-details'),
      );
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: panel, matching: find.text('Weiterkommensregel')),
        findsWidgets,
      );

      final qualifierField = find.byKey(
        const ValueKey('group-qualifier-count-field'),
      );
      await tester.ensureVisible(qualifierField);
      await tester.enterText(qualifierField, '6');
      await tester.pumpAndSettle();

      final save = find.byKey(_saveKey);
      await tester.ensureVisible(save);
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(tournament.stages.single.qualifiedParticipantCount, 6);
      final runStage = tournament.runStages.single as GroupTournamentRunStage;
      expect(runStage.qualificationPlan?.totalQualifiers, 6);
      expect(runStage.qualificationPlan?.fixedByGroup, [3, 3]);

      final persisted = await storage.loadTournaments();
      expect(persisted, hasLength(1));
      expect(persisted.single.stages.single.qualifiedParticipantCount, 6);
      final persistedRun =
          persisted.single.runStages.single as GroupTournamentRunStage;
      expect(persistedRun.qualificationPlan?.totalQualifiers, 6);
      expect(persistedRun.qualificationPlan?.fixedByGroup, [3, 3]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('knockout rules edit draw mode and placement games and persist', (
    tester,
  ) async {
    final tournament = _knockoutTournament();
    final storage = _MemoryTournamentStorage();
    await _pumpRunPage(
      tester,
      tournament: tournament,
      storage: storage,
      size: const Size(1440, 1400),
    );
    await _openSettings(tester);
    await _expandRulesPanel(tester);

    final panel = find.byKey(_panelKey);
    expect(
      find.descendant(of: panel, matching: find.text('Auslosungsmethode')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: panel,
        matching: find.text('Optionale Platzierungsspiele'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('running-knockout-play-fully')),
      findsNothing,
    );
    // Advancing count remains editable in running settings (no play-fully toggle).
    expect(
      find.byKey(const ValueKey('knockout-advancing-count-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('running-placement-place-3')),
      findsOneWidget,
    );

    final seeding = find.byKey(const ValueKey('running-knockout-seeding-mode'));
    await tester.ensureVisible(seeding);
    await tester.tap(seeding);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leistungsbasierte Setzliste (ELO)').last);
    await tester.pumpAndSettle();

    final fifthPlace = find.byKey(const ValueKey('running-placement-place-5'));
    await tester.ensureVisible(fifthPlace);
    await tester.tap(fifthPlace);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(fifthPlace).selected, isTrue);

    final save = find.byKey(_saveKey);
    await tester.ensureVisible(save);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(tournament.stages.single.knockoutSeedingMode, 'elo');
    expect(tournament.stages.single.placementPlaces, [5]);
    final runStage = tournament.runStages.single as KnockoutTournamentRunStage;
    expect(
      runStage.placementMatches.map((match) => match.placementRank),
      contains(5),
    );

    final persisted = await storage.loadTournaments();
    expect(persisted, hasLength(1));
    expect(persisted.single.stages.single.knockoutSeedingMode, 'elo');
    expect(persisted.single.stages.single.placementPlaces, [5]);
    final persistedRun =
        persisted.single.runStages.single as KnockoutTournamentRunStage;
    expect(
      persistedRun.placementMatches.map((match) => match.placementRank),
      contains(5),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'running KO settings hide play-fully but keep placement games editable',
    (tester) async {
      final tournament = _knockoutTournament(knockoutAdvancingCount: null);
      final storage = _MemoryTournamentStorage();
      await _pumpRunPage(
        tester,
        tournament: tournament,
        storage: storage,
        size: const Size(1440, 1400),
      );
      await _openSettings(tester);
      await _expandRulesPanel(tester);

      final panel = find.byKey(_panelKey);
      expect(
        find.byKey(const ValueKey('running-knockout-play-fully')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: panel,
          matching: find.text('Turnierform vollständig ausspielen'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('running-placement-place-3')),
        findsOneWidget,
      );

      final thirdPlace = find.byKey(
        const ValueKey('running-placement-place-3'),
      );
      await tester.ensureVisible(thirdPlace);
      await tester.tap(thirdPlace);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(thirdPlace).selected, isTrue);

      final save = find.byKey(_saveKey);
      await tester.ensureVisible(save);
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(tournament.stages.single.knockoutAdvancingCount, isNull);
      expect(tournament.stages.single.placementPlaces, contains(3));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('rules panel is disabled after the source phase is completed', (
    tester,
  ) async {
    final tournament = _groupTournament(completedStageIndexes: const {0});
    final storage = _MemoryTournamentStorage();
    await _pumpRunPage(
      tester,
      tournament: tournament,
      storage: storage,
      size: const Size(1440, 1400),
    );
    await _openSettings(tester);
    await _expandRulesPanel(tester);

    final panel = find.byKey(_panelKey);
    final rulesWidget = find
        .ancestor(of: panel, matching: find.byType(RunningTournamentRulesPanel))
        .first;
    expect(
      tester.widget<RunningTournamentRulesPanel>(rulesWidget).enabled,
      isFalse,
    );
    expect(
      find.descendant(
        of: panel,
        matching: find.textContaining('kann nicht mehr geändert werden'),
      ),
      findsOneWidget,
    );
    final qualifierField = find.byKey(
      const ValueKey('group-qualifier-count-field'),
    );
    await tester.ensureVisible(qualifierField);
    expect(tester.widget<TextField>(qualifierField).enabled, isFalse);
    final save = find.byKey(_saveKey);
    await tester.ensureVisible(save);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'group phase settings show follow-up knockout rules and propagate to next stage',
    (tester) async {
      final tournament = _groupThenKnockoutTournament(qualifiedCount: 8);
      final storage = _MemoryTournamentStorage();
      await _pumpRunPage(
        tester,
        tournament: tournament,
        storage: storage,
        size: const Size(1440, 1600),
      );
      await _openSettings(tester);
      await _expandRulesPanel(tester);

      final panel = find.byKey(_panelKey);
      expect(
        find.descendant(of: panel, matching: find.text('Folgephase: KO')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('Auslosungsmethode')),
        findsOneWidget,
      );

      final qualifierField = find.byKey(
        const ValueKey('group-qualifier-count-field'),
      );
      await tester.ensureVisible(qualifierField);
      await tester.enterText(qualifierField, '6');
      await tester.pumpAndSettle();

      final seeding = find.byKey(
        const ValueKey('running-knockout-seeding-mode'),
      );
      await tester.ensureVisible(seeding);
      await tester.tap(seeding);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leistungsbasierte Setzliste (ELO)').last);
      await tester.pumpAndSettle();

      final fifthPlace = find.byKey(
        const ValueKey('running-placement-place-5'),
      );
      await tester.ensureVisible(fifthPlace);
      await tester.tap(fifthPlace);
      await tester.pumpAndSettle();

      final save = find.byKey(_saveKey);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(tournament.stages[0].qualifiedParticipantCount, 6);
      expect(tournament.stages[1].knockoutParticipantCount, 6);
      expect(tournament.stages[1].knockoutBracketSize, 8);
      expect(tournament.stages[1].knockoutSeedingMode, 'elo');
      expect(tournament.stages[1].placementPlaces, contains(5));
      final koRun = tournament.runStages[1] as KnockoutTournamentRunStage;
      expect(koRun.rounds.first.length, 4);
      expect(
        koRun.placementMatches.map((match) => match.placementRank),
        contains(5),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('settings view hides phase switcher', (tester) async {
    final tournament = _groupThenKnockoutTournament();
    final storage = _MemoryTournamentStorage();
    await _pumpRunPage(tester, tournament: tournament, storage: storage);
    expect(find.byKey(const ValueKey('stage-phase-switcher')), findsOneWidget);
    await _openSettings(tester);
    expect(find.byKey(const ValueKey('stage-phase-switcher')), findsNothing);
    expect(find.byKey(_panelKey), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'knockout rules remain editable while phase has results but is not completed',
    (tester) async {
      final tournament = _knockoutTournament(withResult: true);
      final storage = _MemoryTournamentStorage();
      await _pumpRunPage(
        tester,
        tournament: tournament,
        storage: storage,
        size: const Size(1440, 1400),
      );
      await _openSettings(tester);
      await _expandRulesPanel(tester);

      final panel = find.byKey(_panelKey);
      final rulesWidget = find
          .ancestor(
            of: panel,
            matching: find.byType(RunningTournamentRulesPanel),
          )
          .first;
      expect(
        tester.widget<RunningTournamentRulesPanel>(rulesWidget).enabled,
        isTrue,
      );
      final seeding = find.byKey(
        const ValueKey('running-knockout-seeding-mode'),
      );
      await tester.ensureVisible(seeding);
      expect(
        tester.widget<DropdownButtonFormField<String>>(seeding).onChanged,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('rules panel renders at $size with 200% text', (tester) async {
      final tournament = _knockoutTournament();
      await _pumpIsolatedPanel(
        tester,
        tournament: tournament,
        size: size,
        textScale: 2,
      );
      await _expandRulesPanel(tester);

      expect(find.byKey(_panelKey), findsOneWidget);
      expect(find.text(_rulesTitle), findsOneWidget);
      expect(find.text('Auslosungsmethode'), findsOneWidget);
      expect(find.text('Optionale Platzierungsspiele'), findsOneWidget);
      // Play-fully toggle is hidden in running KO settings.
      expect(
        find.byKey(const ValueKey('running-placement-place-3')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('group qualification details render at $size with 200% text', (
      tester,
    ) async {
      final tournament = _groupTournament();
      await _pumpIsolatedPanel(
        tester,
        tournament: tournament,
        size: size,
        textScale: 2,
      );
      await _expandRulesPanel(tester);
      final details = find.byKey(
        const ValueKey('running-rules-qualification-details'),
      );
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();

      expect(find.text('Weiterkommensregel'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
