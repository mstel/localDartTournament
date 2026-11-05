import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/app/app_theme.dart';
import 'package:dart_tournament_manager/features/statistics/presentation/tournament_match_statistics_page.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/result_entry.dart';
import 'support/recorded_match.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/order_of_play_section.dart';

void main() {
  testWidgets('completed Order of Play entry opens statistics', (tester) async {
    final match = recordedMatch();
    final tournament = CreatedTournament(
      name: 'Test',
      players: [match.homePlayer!, match.awayPlayer!],
      stages: const [TournamentStage(name: 'Finale', type: 'single_knockout')],
      runStages: [
        KnockoutTournamentRunStage(
          name: 'Finale',
          rounds: [
            [match],
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OrderOfPlaySection(
              tournament: tournament,
              activeStage: 0,
              onChange: () async {},
              onResult: (_) => fail('Must not edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abgeschlossene Matches'));
    await tester.pumpAndSettle();
    final name = find.text('Anna Musterfrau');
    await tester.ensureVisible(name);
    await tester.tap(name);
    await tester.pumpAndSettle();
    expect(find.text('Spielstatistik'), findsOneWidget);
  });
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
      testWidgets(
        'completed match opens read-only statistics at $size / $scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final match = GroupMatch.fromJson(recordedMatch().toJson());
          final boundary = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: buildDartTournamentTheme(),
              builder: (context, child) => RepaintBoundary(
                key: boundary,
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: MatchResultTile(
                    match: match,
                    onEditResult: (_) => fail('Must not edit'),
                    canEditResult: false,
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.textContaining('Anna Musterfrau'));
          await tester.pumpAndSettle();
          expect(find.text('Spielstatistik'), findsOneWidget);
          expect(find.textContaining('3-Dart-Average'), findsNothing);
          expect(find.text('Ergebnis: 1:0'), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (font.isNotEmpty) {
            await tester.runAsync(() async {
              final render =
                  boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await render.toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'build/layout_previews/match_statistics_${size.width.toInt()}_$scale.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
        },
      );
    }
  }
  testWidgets('score edits results while tapping the row opens match details', (
    tester,
  ) async {
    final match = recordedMatch();
    var edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchResultTile(
            match: match,
            onEditResult: (_) => edits++,
            canEditResult: true,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Ergebnis bearbeiten'));
    expect(edits, 1);
    expect(find.byType(TournamentMatchStatisticsPage), findsNothing);
    await tester.tap(find.text('Anna Musterfrau'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ergebnis:'), findsOneWidget);
    expect(find.textContaining('Scorer'), findsNothing);
  });
  testWidgets('unfinished match still edits its score', (tester) async {
    final match = recordedMatch()
      ..homeLegs = null
      ..awayLegs = null;
    var edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchResultTile(
            match: match,
            onEditResult: (_) => edits++,
            canEditResult: true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('-:-'));
    await tester.pumpAndSettle();
    expect(edits, 1);
    expect(find.byType(TournamentMatchStatisticsPage), findsNothing);
  });
}
