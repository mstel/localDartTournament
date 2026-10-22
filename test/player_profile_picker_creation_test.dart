import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/creation/player_profile_picker_dialog.dart';

PlayerProfile profile(String id, String name) => PlayerProfile(
  id: id,
  displayName: name,
  country: '',
  city: '',
  dartsSetupJson: '',
  createdAt: DateTime(2026),
  isActive: true,
);

class PlayerPickerCreationPreview extends StatelessWidget {
  const PlayerPickerCreationPreview({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: PlayerProfilePickerDialog(
      profiles: [profile('old', 'Alexandra mit langem Spielernamen')],
      selectedProfileIds: const {'old'},
      createPlayer: (firstName, lastName) async =>
          profile('new', '$firstName $lastName'.trim()),
    ),
  );
}

void main() {
  testWidgets('without creation authorization there is no create action', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlayerProfilePickerDialog(profiles: [], selectedProfileIds: {}),
        ),
      ),
    );
    expect(find.text('Neuen Spieler anlegen'), findsNothing);
  });
  testWidgets(
    'failed creation retains input; successful retry selects new and existing players',
    (tester) async {
      var reject = true;
      List<PlayerProfile>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Öffnen'),
                onPressed: () async {
                  result = await showDialog<List<PlayerProfile>>(
                    context: context,
                    builder: (_) => PlayerProfilePickerDialog(
                      profiles: [profile('old', 'Alex')],
                      selectedProfileIds: const {'old'},
                      createPlayer: (firstName, lastName) async {
                        if (reject) throw StateError('denied');
                        return profile('new', '$firstName $lastName'.trim());
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Öffnen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Neuer Spieler');
      await tester.tap(find.text('Neuen Spieler anlegen'));
      await tester.pumpAndSettle();
      expect(find.text('Neuer Spieler'), findsOneWidget);
      expect(
        find.textContaining('Verbindung und Berechtigung'),
        findsOneWidget,
      );
      reject = false;
      await tester.tap(find.text('Neuen Spieler anlegen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 übernehmen'));
      await tester.pumpAndSettle();
      expect(result!.map((p) => p.id), ['old', 'new']);
    },
  );
  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('create player at $size with large text', (tester) async {
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
          home: const PlayerPickerCreationPreview(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
