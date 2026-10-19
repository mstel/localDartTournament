import 'package:dart_tournament_manager/tournament_workspace.dart'
    show TournamentFormatPlannerDialog;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/app/app_theme.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/stage_play_order_section.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/order_of_play_section.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/result_entry.dart';
import 'package:dart_tournament_manager/features/statistics/presentation/live_tournament_statistics_section.dart';

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
      testWidgets('Tournament views at $size text $scale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
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
        matches.first.homeLegs = 3;
        matches.first.awayLegs = 1;
        final stage = GroupTournamentRunStage(
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
        );
        final tournament = CreatedTournament(
          name: 'Vereinsmeisterschaft',
          players: players,
          stages: [],
          runStages: [stage],
        );
        Future<void> show(String name, Widget child) async {
          final boundary = GlobalKey();
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
                child: Scaffold(
                  body: name == 'finder'
                      ? child
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: child,
                        ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
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
                'build/layout_previews/views_${name}_${size.width.toInt()}_$scale.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }

        await show('finder', const TournamentFormatPlannerDialog());
        expect(
          find
              .byKey(const ValueKey('planner-mode-single_knockout'))
              .hitTestable(),
          findsNothing,
        );
        expect(find.text('Vorschläge berechnen').hitTestable(), findsOneWidget);
        final forms = find.text('Turnierformen');
        await tester.ensureVisible(forms);
        await tester.tap(forms);
        await tester.pumpAndSettle();
        final mode = find.byKey(const ValueKey('planner-mode-single_knockout'));
        await tester.ensureVisible(mode);
        expect(tester.widget<CheckboxListTile>(mode).value, isFalse);
        await tester.tap(mode);
        await tester.pumpAndSettle();
        expect(tester.widget<CheckboxListTile>(mode).value, isTrue);
        await tester.tap(mode);
        await tester.pumpAndSettle();
        await tester.ensureVisible(forms);
        await tester.tap(forms);
        await tester.pumpAndSettle();
        await tester.tap(forms);
        await tester.pumpAndSettle();
        expect(tester.widget<CheckboxListTile>(mode).value, isFalse);
        expect(tester.takeException(), isNull);
        await show(
          'matches',
          StagePlayOrderSection(
            stage: stage,
            matches: matches,
            onEditResult: (_) {},
            canEditResults: true,
          ),
        );
        expect(find.byType(MatchResultTile), findsOneWidget);
        final results = find.widgetWithText(ChoiceChip, 'Ergebnisse');
        await tester.ensureVisible(results);
        await tester.tap(results);
        await tester.pumpAndSettle();
        expect(
          tester.widget<MatchResultTile>(find.byType(MatchResultTile)).match,
          same(matches.first),
        );
        expect(tester.takeException(), isNull);
        await show(
          'boards',
          OrderOfPlaySection(
            tournament: tournament,
            activeStage: 0,
            onChange: () async {},
            onResult: (_) async {},
          ),
        );
        expect(find.text('Geplante Reihenfolge'), findsOneWidget);
        expect(find.text('Als Nächstes'), findsOneWidget);
        expect(find.text('Danach · Block 2'), findsOneWidget);
        expect(find.byTooltip('Starten / vorziehen'), findsNWidgets(5));
        expect(tester.takeException(), isNull);
        await show(
          'statistics',
          LiveTournamentStatisticsSection(tournament: tournament),
        );
        expect(find.byType(LiveTournamentStatisticsSection), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
