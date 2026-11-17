import 'package:dart_tournament_manager/features/tournaments/application/order_of_play/order_of_play_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/fixed_schedule_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'order_of_play_test.dart' show fixture;

void main() {
  testWidgets('overall schedule editor offers drag and drop and apply', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tournament = fixture(boards: 2)..directorPlayOrderMode = 'fixed_schedule';
    const OrderOfPlayController().initializeFixedSchedule(tournament);
    var applied = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FixedScheduleEditorDialog(
              tournament: tournament,
              stageIndex: 0,
              scope: FixedScheduleEditorScope.overall,
              onApply: () async => applied++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Spielplan gesamt bearbeiten'), findsOneWidget);
    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.text('Speichern & Anwenden'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);

    await tester.tap(find.text('Speichern & Anwenden'));
    await tester.pumpAndSettle();
    expect(applied, 1);
  });

  testWidgets('per-board schedule editor offers a board selector', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tournament = fixture(boards: 3)..directorPlayOrderMode = 'fixed_schedule';
    const OrderOfPlayController().initializeFixedSchedule(tournament);
    var applied = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FixedScheduleEditorDialog(
              tournament: tournament,
              stageIndex: 0,
              scope: FixedScheduleEditorScope.perBoard,
              onApply: () async => applied++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Spielplan je Board bearbeiten'), findsOneWidget);
    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    expect(find.text('Board 1'), findsOneWidget);

    await tester.tap(find.text('Speichern & Anwenden'));
    await tester.pumpAndSettle();
    expect(applied, 1);
  });
}
