import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/dev_tools/domain/tournament_simulation_engine.dart';
import 'package:dart_tournament_manager/features/dev_tools/presentation/simulation_graph.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

void main() {
  final players = List.generate(4, (i) => TournamentPlayer.generated(i + 1));
  SimulationMatchRecord record(
    int number,
    int round,
    int home,
    int away,
    String h,
    String a,
  ) => SimulationMatchRecord(
    number: number,
    bracket: 'Finalrunde',
    homeSource: h,
    awaySource: a,
    match: GroupMatch(
      round: round,
      homePlayer: players[home],
      awayPlayer: players[away],
      homeLegs: 0,
      awayLegs: 2,
    ),
  );
  final records = [
    record(1, 1, 0, 1, 'Teilnehmer 1', 'Teilnehmer 2'),
    record(2, 2, 0, 2, 'Verlierer Spiel 1', 'Teilnehmer 3'),
    record(3, 3, 1, 2, 'Sieger Spiel 1', 'Sieger Spiel 2'),
  ];
  test('winner and loser anchors follow the actual rows and avoid cards', () {
    final layout = SimulationGraphLayout(records);
    expect(layout.edges.length, 3);
    expect(layout.edges[0].start, layout.positions[1]! + const Offset(260, 57));
    expect(layout.edges[1].start, layout.positions[1]! + const Offset(260, 99));
    expect(layout.edges[1].end, layout.positions[3]! + const Offset(0, 57));
    expect(layout.edges[1].lane, isNotNull);
    for (final edge in layout.edges) {
      for (final metric in edge.path.computeMetrics()) {
        for (var distance = 1.0; distance < metric.length; distance += 2) {
          final point = metric.getTangentForOffset(distance)!.position;
          for (final position in layout.positions.values) {
            expect(
              (position & const Size(260, 130)).deflate(1).contains(point),
              isFalse,
            );
          }
        }
      }
    }
  });
  testWidgets('painted endpoints align with rendered player rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: SimulationGraph(records: records),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paintFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is SimulationConnections,
    );
    final painter =
        tester.widget<CustomPaint>(paintFinder).painter!
            as SimulationConnections;
    final origin = tester.getTopLeft(paintFinder);
    for (final entry in painter.layout.positions.entries) {
      for (final home in [true, false]) {
        final center = tester.getCenter(
          find.byKey(ValueKey('graph-player-${entry.key}-$home')),
        );
        expect(
          center.dy,
          closeTo(origin.dy + entry.value.dy + (home ? 57 : 99), .01),
        );
      }
    }
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/tournament_simulation/graph_preview.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
