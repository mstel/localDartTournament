import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/creation/team_participant_list.dart';

void main() {
  testWidgets('catalog players cannot be renamed in tournament creation', (
    tester,
  ) async {
    final players = [
      TournamentPlayer(
        profileId: 'catalog-player',
        name: 'Katalogspieler',
        isGenerated: false,
      ),
      TournamentPlayer(name: 'Gastspieler', isGenerated: false),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TeamParticipantList(
            players: players,
            onRename: (_) {},
            onRemove: (_) {},
            onSplit: (_) {},
            onMerge: (_, _) {},
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Katalogspieler'),
          matching: find.byType(Card),
        ),
        matching: find.byTooltip('Umbenennen'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Gastspieler'),
          matching: find.byType(Card),
        ),
        matching: find.byTooltip('Umbenennen'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('dragging one entrant onto another merges them', (tester) async {
    final players = List.generate(2, (i) => TournamentPlayer.generated(i + 1));
    List<int>? merged;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TeamParticipantList(
            players: players,
            onRename: (_) {},
            onRemove: (_) {},
            onSplit: (_) {},
            onMerge: (source, target) => merged = [source, target],
          ),
        ),
      ),
    );
    final start = tester.getCenter(find.text('Spieler 1'));
    final end = tester.getCenter(find.text('Spieler 2'));
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(30, 0));
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(merged, [0, 1]);
  });
  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('team actions at $size with large text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final players = List.generate(
        3,
        (i) => TournamentPlayer.generated(i + 1),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(2),
              ),
              child: StatefulBuilder(
                builder: (context, setState) => SingleChildScrollView(
                  child: TeamParticipantList(
                    players: players,
                    onRename: (_) {},
                    onRemove: (_) {},
                    onMerge: (source, target) => setState(() {
                      players[target] = TournamentPlayer.team([
                        players[target],
                        players[source],
                      ]);
                      players.removeAt(source);
                    }),
                    onSplit: (i) => setState(() {
                      final members = players.removeAt(i).members;
                      players.insertAll(i, members);
                    }),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byTooltip('Team bearbeiten').first);
      await tester.tap(find.byTooltip('Team bearbeiten').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mit Spieler / Team verbinden'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SimpleDialogOption, 'Spieler 2'));
      await tester.pumpAndSettle();
      expect(players.length, 2);
      expect(players.first.isTeam, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
