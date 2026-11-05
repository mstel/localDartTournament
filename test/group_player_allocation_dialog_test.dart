import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/creation/group_player_allocation_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('custom groups fit at $size with large text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => GroupPlayerAllocationDialog(
                    initialGroups: [
                      [
                        TournamentPlayer.generated(1),
                        TournamentPlayer.generated(2),
                      ],
                      [
                        TournamentPlayer.generated(3),
                        TournamentPlayer.generated(4),
                      ],
                    ],
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('players can be swapped between custom groups', (tester) async {
    final players = [
      for (var index = 1; index <= 4; index++)
        TournamentPlayer.generated(index),
    ];
    List<List<TournamentPlayer>>? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<List<List<TournamentPlayer>>>(
                  context: context,
                  builder: (_) => GroupPlayerAllocationDialog(
                    initialGroups: [
                      players.take(2).toList(),
                      players.skip(2).toList(),
                    ],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('group-player-0-0')));
    await tester.tap(find.byKey(const ValueKey('group-player-1-0')));
    await tester.tap(find.byKey(const ValueKey('apply-custom-groups')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result![0].map((player) => player.name), ['Spieler 3', 'Spieler 2']);
    expect(result![1].map((player) => player.name), ['Spieler 1', 'Spieler 4']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('players can be moved with drag and drop', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final players = [
      for (var index = 1; index <= 4; index++)
        TournamentPlayer.generated(index),
    ];
    List<List<TournamentPlayer>>? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<List<List<TournamentPlayer>>>(
                  context: context,
                  builder: (_) => GroupPlayerAllocationDialog(
                    initialGroups: [
                      players.take(2).toList(),
                      players.skip(2).toList(),
                    ],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final source = find.byKey(const ValueKey('group-player-0-0'));
    final target = find.byKey(const ValueKey('group-player-1-0'));
    final gesture = await tester.startGesture(tester.getCenter(source));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-custom-groups')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result![0].first.name, 'Spieler 3');
    expect(result![1].first.name, 'Spieler 1');
    expect(tester.takeException(), isNull);
  });
}
