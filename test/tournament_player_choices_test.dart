import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/accounts/domain/account_user.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_player_choices.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/creation/player_profile_picker_dialog.dart';

void main() {
  final date = DateTime.utc(2026);
  final operator = AccountUser(
    id: 'operator-account',
    username: 'operator',
    displayName: 'Vereinsverwaltung',
    email: 'operator@example.test',
    avatarUrl: null,
    createdAt: date,
    updatedAt: date,
    lastLogin: null,
    isActive: true,
  );
  final player = PlayerProfile(
    id: 'player-1',
    displayName: 'Anna Musterfrau',
    country: '',
    city: '',
    dartsSetupJson: '',
    createdAt: date,
    isActive: true,
  );

  test('operator account never becomes a tournament participant', () {
    expect(tournamentPlayerChoices([], operator), isEmpty);
    expect(tournamentPlayerChoices([player], operator), [same(player)]);
  });

  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('local player selection at $size / $scale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        List<PlayerProfile>? selected;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    selected = await showDialog<List<PlayerProfile>>(
                      context: context,
                      builder: (_) => PlayerProfilePickerDialog(
                        profiles: [player],
                        selectedProfileIds: const {},
                      ),
                    );
                  },
                  child: const Text('Teilnehmer auswählen'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Teilnehmer auswählen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Anna Musterfrau'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('1 übernehmen'));
        await tester.pumpAndSettle();
        expect(selected!.single.id, player.id);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
