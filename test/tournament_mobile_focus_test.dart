import 'package:dart_tournament_manager/features/tournaments/modes/triple_ko/triple_ko_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/stage_controls.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/mini_knockout_group_run_section.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:dart_tournament_manager/app/app_theme.dart';
import 'package:dart_tournament_manager/shared/persistence/storage_access.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show TournamentRunPage;
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/round_match_list.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/knockout_run_section.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String> getApplicationSupportPath() async => path;
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
      testWidgets('Tournament focuses rounds at $size text $scale', (
        tester,
      ) async {
        final directory = Directory.systemTemp.createTempSync(
          'tournament_mobile_',
        );
        final previous = PathProviderPlatform.instance;
        PathProviderPlatform.instance = _Paths(directory.path);
        addTearDown(() {
          PathProviderPlatform.instance = previous;
          directory.deleteSync(recursive: true);
        });
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        final players = List.generate(
          4,
          (i) => TournamentPlayer.generated(i + 1),
        );
        final matches = [
          for (var round = 1; round <= 3; round++)
            for (var pair = 0; pair < 2; pair++)
              GroupMatch(
                homePlayer: players[pair * 2],
                awayPlayer: players[pair * 2 + 1],
                round: round,
              ),
        ];
        final tournament = CreatedTournament(
          name: 'Vereinsmeisterschaft',
          players: players,
          stages: const [
            TournamentStage(
              name: 'Gruppenphase',
              type: 'group',
              groupCount: 1,
              groupSizes: [4],
            ),
          ],
          runStages: [
            GroupTournamentRunStage(
              name: 'Gruppenphase',
              groupPlayType: 'round_robin',
              qualificationPlan: null,
              tieBreakers: defaultGroupTieBreakers,
              groups: [
                TournamentGroup(
                  name: 'Gruppe A',
                  playType: 'round_robin',
                  players: players,
                  matches: matches,
                ),
              ],
            ),
          ],
        );
        final boundary = GlobalKey();
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              theme: buildDartTournamentTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: boundary,
                child: TournamentRunPage(tournament: tournament),
              ),
            ),
          );
          await tester.pump();
          await StorageAccess.run(() async {});
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (size.width < 840 || scale > 1) {
          await tester.tap(find.byType(DropdownButtonFormField<StageViewMode>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Ergebnisse').last);
        } else {
          await tester.tap(find.text('Ergebnisse'));
        }
        await tester.pumpAndSettle();
        expect(find.text('Turnieruhr starten'), findsNothing);
        expect(find.byTooltip('Ergebnis eingeben'), findsWidgets);
        if (font.isNotEmpty) {
          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await render.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/layout_previews/tournament_focus_${size.width.toInt()}_$scale.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        tester.view.physicalSize = const Size(1440, 900);
        await tester.pumpAndSettle();
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(find.byTooltip('Ergebnis eingeben'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => StorageAccess.run(() async {}));
      });

      testWidgets(
        'Knockout uses match list with optional bracket $size text $scale',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.reset);
          final stage = KnockoutTournamentRunStage(
            name: 'K.-o.-Phase',
            rounds: [
              for (var r = 1; r <= 3; r++)
                [
                  GroupMatch(
                    homePlayer: TournamentPlayer.generated(r),
                    awayPlayer: TournamentPlayer.generated(r + 4),
                    round: r,
                  ),
                ],
            ],
          );
          GroupMatch? edited;
          await tester.pumpWidget(
            MaterialApp(
              theme: buildDartTournamentTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: KnockoutRunSection(
                    stage: stage,
                    qualifyingRank: 1,
                    onEditResult: (m) => edited = m,
                    canEditResults: true,
                    isEditMode: false,
                    canEditBracket: true,
                    onEditModeChanged: (_) {},
                    onSwapSlot: (_, _) {},
                    bracketBuilder: (_, _, _, _, _, _) =>
                        const Text('Gesamter Turnierbaum'),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (font.isNotEmpty) {
            await tester.runAsync(() async {
              final render = tester.firstRenderObject<RenderRepaintBoundary>(
                find.byType(RepaintBoundary),
              );
              final image = await render.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'build/layout_previews/knockout_focus_${size.width.toInt()}_$scale.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          final compact = size.width < 840 || scale > 1;
          expect(
            find.byType(RoundMatchList),
            compact ? findsOneWidget : findsNothing,
          );
          if (compact) {
            expect(find.text('Gesamter Turnierbaum'), findsNothing);
            await tester.tap(find.byTooltip('Ergebnis eingeben'));
            expect(edited, same(stage.rounds.first.first));
            await tester.scrollUntilVisible(
              find.text('Turnierbaum & Setzung').hitTestable(),
              150,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.tap(find.text('Turnierbaum & Setzung'));
            await tester.pumpAndSettle();
            expect(find.text('Gesamter Turnierbaum'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('Mini knockout matches remain editable on phones', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    final match = GroupMatch(
      homePlayer: TournamentPlayer.generated(1),
      awayPlayer: TournamentPlayer.generated(2),
      round: 1,
    );
    final group = TournamentGroup(
      name: 'Gruppe A',
      playType: 'mini_knockout',
      players: [],
      matches: [],
      knockoutRounds: [
        [match],
      ],
    );
    GroupMatch? edited;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDartTournamentTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MiniKnockoutGroupRunSection(
              group: group,
              bracket: const Text('Gruppenbaum-Vorschau'),
              canEditResults: true,
              onEditResult: (value) => edited = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gruppenbaum-Vorschau'), findsNothing);
    await tester.tap(find.byTooltip('Ergebnis eingeben'));
    expect(edited, same(match));
    await tester.tap(find.text('Gruppenbaum'));
    await tester.pumpAndSettle();
    expect(find.text('Gruppenbaum-Vorschau'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'Real mini triple bracket survives portrait landscape portrait text $scale',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync(
          'triple_rotation_',
        );
        final previous = PathProviderPlatform.instance;
        PathProviderPlatform.instance = _Paths(directory.path);
        addTearDown(() {
          PathProviderPlatform.instance = previous;
          directory.deleteSync(recursive: true);
        });
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 800);
        addTearDown(tester.view.reset);
        final players = List.generate(
          4,
          (i) => TournamentPlayer.generated(i + 1),
        );
        final rounds = TripleKoEngine.build([
          for (var i = 0; i < 4; i += 2)
            GroupMatch(
              homePlayer: players[i],
              awayPlayer: players[i + 1],
              round: 1,
            ),
        ]);
        final tournament = CreatedTournament(
          name: 'Rotation',
          players: players,
          stages: const [
            TournamentStage(
              name: 'Mini-Triple-KO',
              type: 'group',
              groupCount: 1,
              groupSizes: [4],
            ),
          ],
          runStages: [
            GroupTournamentRunStage(
              name: 'Mini-Triple-KO',
              groupPlayType: 'triple_elimination',
              qualificationPlan: null,
              tieBreakers: defaultGroupTieBreakers,
              groups: [
                TournamentGroup(
                  name: 'Gruppe A',
                  playType: 'triple_elimination',
                  players: players,
                  matches: rounds.expand((r) => r).toList(),
                  knockoutRounds: rounds,
                ),
              ],
            ),
          ],
        );
        final rotationBoundary = GlobalKey();
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              theme: buildDartTournamentTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: rotationBoundary,
                child: TournamentRunPage(tournament: tournament),
              ),
            ),
          );
          await tester.pump();
          await StorageAccess.run(() async {});
        });
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<StageViewMode>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ergebnisse').last);
        await tester.pumpAndSettle();
        expect(find.byType(TournamentRunPage), findsOneWidget);
        expect(find.byTooltip('Ergebnis eingeben'), findsWidgets);
        expect(tester.takeException(), isNull);

        for (final size in [
          const Size(900, 400),
          const Size(360, 800),
          const Size(800, 600),
          const Size(1440, 900),
          const Size(360, 800),
        ]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Rotation to $size');
          expect(find.byType(TournamentRunPage), findsOneWidget);
          expect(find.byTooltip('Ergebnis eingeben'), findsWidgets);
        }
        if (font.isNotEmpty) {
          await tester.runAsync(() async {
            final render =
                rotationBoundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await render.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/layout_previews/mini_triple_rotation_$scale.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        expect(rounds.first.first.homePlayer, same(players.first));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
