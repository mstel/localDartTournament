import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/stage_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('in-tournament navigation omits the statistics tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StageViewModeSwitch(
            selectedMode: StageViewMode.dashboard,
            onModeChanged: _ignoreMode,
          ),
        ),
      ),
    );

    expect(find.text('Statistik'), findsNothing);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Ergebnisse'), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);
  });
}

void _ignoreMode(StageViewMode _) {}
