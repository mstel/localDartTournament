import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/creation/configuration_duration_bar.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_planning_parameters.dart';
import 'package:dart_tournament_manager/shared/widgets/adaptive_content.dart';

void main() {
  const previewFont = String.fromEnvironment('LAYOUT_PREVIEW_FONT');
  setUpAll(() async {
    if (previewFont.isNotEmpty) {
      await (FontLoader('Roboto')..addFont(
            File(
              previewFont,
            ).readAsBytes().then((b) => ByteData.sublistView(b)),
          ))
          .load();
    }
  });
  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('duration controls $size scale $scale', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        var boards = 1;
        final previewKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, update) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(
                  key: previewKey,
                  child: Scaffold(
                    body: AdaptiveContentList(
                      children: [
                        ConfigurationDurationBar(
                          stages: const [
                            TournamentStage(
                              name: 'Liga',
                              type: 'groups',
                              groupCount: 1,
                              groupSizes: [4],
                              gameFormat: TournamentGameFormat(bestOfLegs: 3),
                            ),
                          ],
                          boards: boards,
                          parameters: const TournamentPlanningParameters(),
                          onBoardsChanged: (value) =>
                              update(() => boards = value),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('ca. 1 h 35 min'), findsOneWidget);
        expect(find.text('6 Spiele insgesamt'), findsOneWidget);
        expect(
          find.textContaining('ca. 20 min (Leerstand 4 min je Boardwechsel)'),
          findsOneWidget,
        );
        expect(
          find.text('Garantiert mindestens 3 Spiele je Teilnehmer'),
          findsOneWidget,
        );
        final plus = find.byTooltip('Ein Board mehr');
        await tester.ensureVisible(plus);
        await tester.pumpAndSettle();
        await tester.tap(plus);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(boards, 2);
        expect(find.text('ca. 46 min'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (previewFont.isNotEmpty) {
          await tester.runAsync(() async {
            final picture =
                await (previewKey.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/layout_previews/ConfigurationCounts_${size.width}_$scale.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            picture.dispose();
          });
        }
      });
    }
  }
}
