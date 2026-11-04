import 'package:dart_tournament_manager/features/random_draw/application/random_draw_image_generator.dart';
import 'package:dart_tournament_manager/features/random_draw/domain/random_draw_assignment.dart';
import 'package:dart_tournament_manager/features/random_draw/presentation/random_draw_tool_page.dart';
import 'package:dart_tournament_manager/shared/utils/group_assignment_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('group slots fill top-to-bottom before moving to the next group', () {
    expect(
      RandomDrawAssignment.groupSlots(
        drawnPlayers: ['Ada', 'Bert', 'Cem', 'Dora', 'Emil'],
        groupCount: 3,
        totalPlayerCount: 8,
      ),
      [
        ['Ada', 'Bert', 'Cem'],
        ['Dora', 'Emil', null],
        [null, null],
      ],
    );
  });

  test('group slot capacities divide players evenly in group order', () {
    final slots = RandomDrawAssignment.groupSlots(
      drawnPlayers: const [],
      groupCount: 8,
      totalPlayerCount: 32,
    );

    expect(slots, hasLength(8));
    expect(slots.map((group) => group.length), everyElement(4));
    expect(slots.expand((group) => group), everyElement(isNull));
  });

  test('text export uses provided group names and player order', () {
    expect(
      GroupAssignmentText.format(
        groupNames: ['Gruppe Rot', 'Gruppe Blau'],
        groups: [
          ['Ada', 'Bert'],
          ['Cem'],
        ],
      ),
      'Gruppen: 2\n\nGruppe Rot:\nAda\nBert\n\nGruppe Blau:\nCem',
    );
  });

  test('group slots preserve imported uneven group sizes', () {
    expect(
      RandomDrawAssignment.groupSlots(
        drawnPlayers: ['Ada', 'Bert'],
        groupCount: 2,
        totalPlayerCount: 5,
        groupSizes: [2, 3],
      ),
      [
        ['Ada', 'Bert'],
        [null, null, null],
      ],
    );
  });

  test('group assignment text parses group names and player names', () {
    final parsed = GroupAssignmentText.parse(
      'Gruppen: 2\n\nGruppe Rot:\nAda\nBert\n\nGruppe Blau:\nCem',
    );

    expect(parsed.groupNames, ['Gruppe Rot', 'Gruppe Blau']);
    expect(parsed.groups, [
      ['Ada', 'Bert'],
      ['Cem'],
    ]);
  });

  test('group assignment text rejects mismatched or duplicate entries', () {
    expect(
      () => GroupAssignmentText.parse('Gruppen: 2\n\nGruppe A:\nAda'),
      throwsFormatException,
    );
    expect(
      () => GroupAssignmentText.parse('Gruppen: 1\n\nGruppe A:\nAda\nada'),
      throwsFormatException,
    );
  });

  test('image export produces a PNG containing all groups', () async {
    final bytes = await const RandomDrawImageGenerator().generate(
      title: 'Auslosung',
      groupNames: ['Gruppe A', 'Gruppe B', 'Gruppe C'],
      groups: [
        ['Ada'],
        ['Bert', 'Cem'],
        ['Dora'],
      ],
    );

    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
  });

  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('standalone draw tool fits $size with large text', (
      tester,
    ) async {
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
          home: const RandomDrawToolPage(),
        ),
      );
      await tester.pump();

      expect(find.text('Anzahl der Gruppen'), findsOneWidget);
      expect(find.text('Spielernamen'), findsOneWidget);
      expect(
        find.byKey(
          ValueKey(
            size.width >= 900
                ? 'random-draw-workspace-wide'
                : 'random-draw-workspace-stacked',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Gruppenzuweisung'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('draw fills locked group slots in draw order', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: RandomDrawToolPage()));
    await tester.enterText(
      find.widgetWithText(TextField, 'Anzahl der Gruppen'),
      '8',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Spielernamen'),
      List.generate(32, (index) => 'Spieler ${index + 1}').join(', '),
    );
    await tester.pump();

    expect(find.text('Gruppe H'), findsOneWidget);
    expect(find.byKey(const ValueKey('draw-slot-Gruppe A-3')), findsOneWidget);
    expect(find.text('Spieler 4'), findsWidgets);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);

    final drawnOrder = <String>[];
    for (var index = 0; index < 32; index++) {
      final button = find.text(index == 0 ? 'Rad drehen' : 'Nächsten ziehen');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      if (index < 5) {
        final selected = tester
            .widget<Text>(
              find.byKey(const ValueKey('random-draw-last-selected')),
            )
            .data!
            .replaceFirst('Zuletzt gezogen: ', '');
        drawnOrder.add(selected);

        if (index == 0) {
          expect(
            find.bySemanticsLabel(
              'Im Rad: ${List.generate(32, (playerIndex) => 'Spieler ${playerIndex + 1}').where((name) => name != selected).join(', ')}',
            ),
            findsOneWidget,
          );
        }
      }
    }

    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Spielernamen'))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<TextField>(
            find.widgetWithText(TextField, 'Anzahl der Gruppen'),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('draw-slot-Gruppe A-0')))
          .data,
      drawnOrder[0],
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('draw-slot-Gruppe A-1')))
          .data,
      drawnOrder[1],
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('draw-slot-Gruppe A-2')))
          .data,
      drawnOrder[2],
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('draw-slot-Gruppe A-3')))
          .data,
      drawnOrder[3],
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('draw-slot-Gruppe B-0')))
          .data,
      drawnOrder[4],
    );
    expect(find.text('Text kopieren'), findsOneWidget);
    expect(find.text('Grafik exportieren'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('imports groups and participant names from the clipboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return {
            'text':
                'Gruppen: 2\n\nGruppe Rot:\nAda\nBert\n\nGruppe Blau:\nCem\nDora',
          };
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: RandomDrawToolPage()));
    await tester.tap(find.text('Zuweisung aus Zwischenablage übernehmen'));
    await tester.pumpAndSettle();

    final groupCount = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Anzahl der Gruppen'),
    );
    final players = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Spielernamen'),
    );
    expect(groupCount.controller!.text, '2');
    expect(players.controller!.text, 'Ada\nBert\nCem\nDora');
    expect(find.text('Gruppe Rot'), findsOneWidget);
    expect(find.text('Gruppe Blau'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
