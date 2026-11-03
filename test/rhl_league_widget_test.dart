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
  int estimatedMinutes(WidgetTester tester) {
    final text = tester
        .widget<Text>(find.textContaining('Voraussichtliche Dauer:'))
        .data!;
    final hours =
        RegExp(r'(\d+) (?:Std\.|Stunden)').firstMatch(text)?.group(1) ?? '0';
    final minutes =
        RegExp(r'(\d+) (?:Min\.|Minuten)').firstMatch(text)?.group(1) ?? '0';
    return int.parse(hours) * 60 + int.parse(minutes);
  }

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

    expect(
      find.text('Name des angepassten Liga-/Freundschaftsspiels'),
      findsOneWidget,
    );
    expect(find.text('Einzel je Spieler'), findsOneWidget);
    expect(find.text('Doppel je Mannschaft'), findsOneWidget);
    expect(find.text('X01-Punktzahl'), findsOneWidget);
    expect(
      find.text('Angepasstes Liga-/Freundschaftsspiel anlegen'),
      findsOneWidget,
    );
    expect(find.text('14 Begegnungen'), findsOneWidget);
    expect(find.textContaining('Voraussichtliche Dauer:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adjusted duration refreshes when the game format changes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: LeagueMatchPage(storage: _MemoryStorage())),
    );
    await tester.tap(find.text('Angepasst'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Angepasster Spielplan'));
    await tester.pumpAndSettle();

    final initialDuration = estimatedMinutes(tester);
    final x01Field = find.byKey(const ValueKey('league-x01-501'));
    await tester.tap(x01Field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('901').last);
    await tester.pumpAndSettle();
    final longerX01Duration = estimatedMinutes(tester);
    expect(longerX01Duration, greaterThan(initialDuration));

    final legsField = find.byKey(const ValueKey('league-legs-5'));
    await tester.tap(legsField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('9 Legs').last);
    await tester.pumpAndSettle();
    expect(estimatedMinutes(tester), greaterThan(longerX01Duration));
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
