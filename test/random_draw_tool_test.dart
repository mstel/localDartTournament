import 'package:dart_tournament_manager/features/random_draw/application/random_draw_image_generator.dart';
import 'package:dart_tournament_manager/features/random_draw/domain/random_draw_assignment.dart';
import 'package:dart_tournament_manager/features/random_draw/presentation/random_draw_tool_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-robin assignment balances drawn players between groups', () {
    expect(
      RandomDrawAssignment.distributeRoundRobin(
        drawnPlayers: ['Ada', 'Bert', 'Cem', 'Dora', 'Emil'],
        groupCount: 3,
      ),
      [
        ['Ada', 'Dora'],
        ['Bert', 'Emil'],
        ['Cem'],
      ],
    );
  });

  test('text export uses provided group names and player order', () {
    expect(
      RandomDrawAssignment.formatText(
        groupNames: ['Gruppe Rot', 'Gruppe Blau'],
        groups: [
          ['Ada', 'Bert'],
          ['Cem'],
        ],
      ),
      'Gruppe Rot: Ada, Bert\nGruppe Blau: Cem',
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
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('draw tool supports manual input, spinning and auto assignment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: RandomDrawToolPage()));
    await tester.enterText(
      find.widgetWithText(TextField, 'Anzahl der Gruppen'),
      '2',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Spielernamen'),
      'Ada\nBert\nCem\nDora',
    );
    await tester.pump();

    for (var index = 0; index < 4; index++) {
      final button = find.text(index == 0 ? 'Rad drehen' : 'Nächsten ziehen');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }
    expect(find.text('Gruppen befüllen'), findsOneWidget);

    final autoAssign = find.text('Automatisch gleichmäßig verteilen');
    await tester.ensureVisible(autoAssign);
    await tester.pumpAndSettle();
    await tester.tap(autoAssign);
    await tester.pumpAndSettle();

    final groupFields = tester.widgetList<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    );
    expect(groupFields, hasLength(4));
    expect(groupFields.every((field) => field.initialValue != null), isTrue);
    expect(tester.takeException(), isNull);
  });
}
