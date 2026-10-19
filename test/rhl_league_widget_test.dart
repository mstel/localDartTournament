import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/league/presentation/league_match_page.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

class _MemoryStorage extends TournamentStorage {
  CreatedTournament? saved;
  @override
  Future<void> saveTournament(CreatedTournament tournament) async {
    saved = CreatedTournament.fromJson(tournament.toJson());
  }
}

void main() {
  testWidgets('adjusted mode exposes fixture and duration settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: LeagueMatchPage(storage: _MemoryStorage())),
    );
    expect(find.text('Traditionell'), findsOneWidget);
    expect(find.text('Angepasst'), findsOneWidget);
    expect(find.text('Geräte zuordnen'), findsNothing);

    await tester.tap(find.text('Angepasst'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Angepasster Spielplan'));
    await tester.pumpAndSettle();

    expect(find.text('Einzel je Spieler'), findsOneWidget);
    expect(find.text('Doppel je Mannschaft'), findsOneWidget);
    expect(find.text('14 Begegnungen'), findsOneWidget);
    expect(find.textContaining('Voraussichtliche Dauer:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creates league and saves a team result', (tester) async {
    final storage = _MemoryStorage();
    await tester.pumpWidget(
      MaterialApp(home: LeagueMatchPage(storage: storage)),
    );
    expect(find.textContaining('Neues Ligaspiel'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('league-name')),
      'Vereinsliga · Spieltag 3',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Ligaspiel anlegen'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ligaspiel anlegen'));
    await tester.pumpAndSettle();
    expect(storage.saved!.leagueMatch!.games.length, 18);
    expect(storage.saved!.name, 'Vereinsliga · Spieltag 3');
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('league-result-0')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ergebnis').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('3:1'));
    await tester.pumpAndSettle();
    expect(storage.saved!.leagueMatch!.homePoints, 1);
    await tester.tap(find.text('Ergebnis').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ergebnis entfernen'));
    await tester.pumpAndSettle();
    expect(storage.saved!.leagueMatch!.homePoints, 0);
    expect(tester.takeException(), isNull);
  });
}
