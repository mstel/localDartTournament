import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_director_snapshot.dart';
import 'package:dart_tournament_manager/features/tournaments/application/order_of_play/order_of_play_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/tournament_director_dashboard.dart';
import 'package:dart_tournament_manager/features/statistics/domain/best_performance.dart';
import 'package:dart_tournament_manager/shared/theme/tournament_display_palette.dart';
import 'order_of_play_test.dart' show fixture;

class DirectorPreview extends StatefulWidget {
  const DirectorPreview({super.key});
  @override
  State<DirectorPreview> createState() => _DirectorPreviewState();
}

class _DirectorPreviewState extends State<DirectorPreview> {
  late final t = fixture(boards: 4);
  @override
  @override
  void initState() {
    super.initState();
    const c = OrderOfPlayController();
    final first = c.plan(t, 0).planned.first;
    c.start(t, 0, first.entry.match, 1);
    t.blockedBoards.add(4);
  }

  @override
  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: TournamentDirectorDashboard(
          tournament: t,
          activeStage: 0,
          onChange: () async => setState(() {}),
          onResult: (match) async {
            setState(() {
              match.homeLegs = 3;
              match.awayLegs = 1;
              const OrderOfPlayController().resultRecorded(match);
            });
          },
          onBlock: (board) async => setState(() {
            if (!t.blockedBoards.remove(board)) t.blockedBoards.add(board);
          }),
        ),
      ),
    ),
  );
}

void main() {
  const font = String.fromEnvironment('LAYOUT_PREVIEW_FONT');
  setUpAll(() async {
    if (font.isNotEmpty) {
      await (FontLoader(
        'Roboto',
      )..addFont(File(font).readAsBytes().then(ByteData.sublistView))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('all director sections at $size text $scale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: boundary,
              child: const DirectorPreview(),
            ),
          ),
        );
        expect(find.text('Dashboard'), findsOneWidget);
        expect(find.text('Empfohlene Partien'), findsOneWidget);
        expect(find.text('Letzte Ergebnisse'), findsOneWidget);
        expect(find.text('Fortschritt nach Etappen'), findsNothing);
        expect(find.text('Bestleistungen'), findsNothing);
        expect(tester.takeException(), isNull);
        for (final section in ['Übersicht', 'Boards', 'Spiele']) {
          final tab = find.widgetWithText(ChoiceChip, section);
          if (tab.evaluate().isNotEmpty) {
            await tester.ensureVisible(tab);
            await tester.tap(tab);
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
          if (font.isNotEmpty) {
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'build/layout_previews/Director_${size.width}_${scale}_$section.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -550),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  const c = OrderOfPlayController();
  test('blocked boards excluded in plan, starts and player suggestions', () {
    final t = fixture();
    t.blockedBoards.add(1);
    final schedule = c.plan(t, 0);
    expect(schedule.planned.every((a) => a.board == 2), isTrue);
    expect(c.start(t, 0, schedule.planned.first.entry.match, 1), isFalse);
    expect(c.suggestForPlayer(t, 0, t.players.first)!.board, 2);
    t.blockedBoards.add(2);
    expect(c.plan(t, 0).planned, isEmpty);
    expect(TournamentDirectorSnapshot(t, 0).ready.length, 15);
    expect(c.suggestForPlayer(t, 0, t.players.first), isNull);
    t.blockedBoards.remove(1);
    expect(c.plan(t, 0).planned.length, 15);
  });
  test('search prioritizes running match, excludes completed pairings', () {
    final t = fixture();
    final first = c.plan(t, 0).planned.first;
    c.start(t, 0, first.entry.match, 1);
    var view = TournamentDirectorSnapshot(t, 0);
    expect(
      view.search(t.players.first.name).first.match,
      same(first.entry.match),
    );
    expect(
      view.canStart(
        view.ready.firstWhere((e) => e.players.contains(t.players.first.name)),
      ),
      isFalse,
    );
    first.entry.match.homeLegs = 3;
    first.entry.match.awayLegs = 1;
    c.resultRecorded(first.entry.match);
    view = TournamentDirectorSnapshot(t, 0);
    expect(
      view
          .search(t.players.first.name)
          .any((e) => identical(e.match, first.entry.match)),
      isFalse,
    );
    t.completedStageIndexes.add(0);
    expect(c.start(t, 0, view.ready.first.match, 2), isFalse);
  });
  test(
    'legacy migration keeps backup and board locks survive reload',
    () async {
      final dir = await Directory.systemTemp.createTemp('director_test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/tournaments.json');
      final t = fixture();
      await file.writeAsString(
        jsonEncode({
          'schemaVersion': 17,
          'tournaments': [t.toJson()],
        }),
      );
      final storage = TournamentStorage(file: file);
      final loaded = (await storage.loadTournaments()).single;
      expect(loaded.blockedBoards, isEmpty);
      loaded.blockedBoards.add(2);
      await storage.saveTournament(loaded);
      expect((await storage.loadTournaments()).single.blockedBoards, {2});
      expect(await File('${file.path}.v17.bak').exists(), isTrue);
      expect(jsonDecode(await file.readAsString())['schemaVersion'], 28);
    },
  );
  testWidgets('director dashboard survives width changes', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: DirectorPreview()));
    expect(find.byType(TournamentDirectorDashboard), findsOneWidget);
    expect(find.text('2. Bildschirm (TV-Vollbild) öffnen'), findsNothing);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.byType(TournamentDirectorDashboard), findsOneWidget);
    expect(find.text('2. Bildschirm (TV-Vollbild) öffnen'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('director match tiles use the second-screen navy palette', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: DirectorPreview()));

    final tiles = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'director-match-tile-',
          ),
    );
    expect(tiles, findsWidgets);
    final decoration =
        tester.widget<Container>(tiles.first).decoration! as BoxDecoration;
    expect(decoration.color, TournamentDisplayPalette.card);
    expect(
      (decoration.border! as Border).top.color,
      TournamentDisplayPalette.border.withAlpha(150),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('dashboard has a direct next-stage preview action', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    final first = TournamentPlayer.generated(1).copyWith(name: 'Spieler A');
    final second = TournamentPlayer.generated(2).copyWith(name: 'Spieler B');
    final tournament = CreatedTournament(
      name: 'Testturnier',
      players: [first, second],
      stages: const [
        TournamentStage(name: 'Gruppenphase', type: 'groups', groupSizes: [2]),
        TournamentStage(
          name: 'KO',
          type: 'single_knockout',
          knockoutParticipantCount: 2,
        ),
      ],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppenphase',
          groupPlayType: 'round_robin',
          groups: [
            TournamentGroup(
              name: 'Gruppe A',
              playType: 'round_robin',
              players: [first, second],
              matches: [
                GroupMatch(homePlayer: first, awayPlayer: second, round: 1),
              ],
            ),
          ],
          qualificationPlan: null,
          tieBreakers: defaultGroupTieBreakers,
        ),
        KnockoutTournamentRunStage(
          name: 'KO',
          rounds: [
            [GroupMatch(round: 1)],
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TournamentDirectorDashboard(
              tournament: tournament,
              activeStage: 0,
              onChange: () async {},
              onResult: (_) async {},
              onBlock: (_) async {},
              onCompleteStage: () {},
              onFinishEarly: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final previewButton = find.text('Vorschau nächste Etappe');
    expect(previewButton, findsOneWidget);
    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    expect(find.text('KO · Turnierbaum-Vorschau'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('dashboard shows at most six upcoming and four recent matches', (
    tester,
  ) async {
    final tournament = fixture();
    final matches = (tournament.runStages.single as GroupTournamentRunStage)
        .groups
        .single
        .matches;
    for (var index = 0; index < 4; index++) {
      matches[index]
        ..homeLegs = 3
        ..awayLegs = 1
        ..finishedAt = DateTime.utc(2026, 1, index + 1);
    }
    matches[2].bestPerformances = const [
      BestPerformance(
        type: BestPerformanceType.score180,
        playerName: 'Spieler 3',
        value: 180,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TournamentDirectorDashboard(
              tournament: tournament,
              activeStage: 0,
              onChange: () async {},
              onResult: (_) async {},
              onBlock: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final upcoming = find
        .ancestor(
          of: find.text('Empfohlene Partien'),
          matching: find.byType(Card),
        )
        .first;
    final recent = find
        .ancestor(
          of: find.text('Letzte Ergebnisse'),
          matching: find.byType(Card),
        )
        .first;
    expect(
      find.descendant(of: upcoming, matching: find.byType(Container)),
      findsNWidgets(6),
    );
    expect(
      find.descendant(of: recent, matching: find.byType(Container)),
      findsNWidgets(4),
    );
    expect(find.text('Bestleistungen'), findsOneWidget);
    expect(find.text('Spieler 3 · 180+ 180'), findsAtLeastNWidgets(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('director queue marks priority matches with a tooltip', (
    tester,
  ) async {
    final tournament = fixture();
    final matches = (tournament.runStages.single as GroupTournamentRunStage)
        .groups
        .single
        .matches;
    for (final match in matches.take(2)) {
      match
        ..homeLegs = 3
        ..awayLegs = 1;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TournamentDirectorDashboard(
              tournament: tournament,
              activeStage: 0,
              onChange: () async {},
              onResult: (_) async {},
              onBlock: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Priorisierte Partie'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('save and synchronization errors stay visible and offer retry', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TournamentDirectorDashboard(
              tournament: fixture(),
              activeStage: 0,
              saveError: 'Nicht gespeichert',
              onChange: () async {
                retried = true;
              },
              onResult: (_) async {},
              onBlock: (_) async {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Nicht gespeichert').first, findsOneWidget);
    final retryBtn = find.text('Speichern erneut versuchen').first;
    await tester.ensureVisible(retryBtn);
    await tester.tap(retryBtn);
    await tester.pumpAndSettle();
    expect(retried, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
