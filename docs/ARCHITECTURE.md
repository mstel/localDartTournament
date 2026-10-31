# Architektur-Notiz

Stand: 2026-06-28

## Kurzfazit

Die App ist funktional in Feature-Ordner verschoben. `main.dart` ist ein kleiner Bootstrap, die App-Shell liegt unter `lib/app/`. Domain-Modelle, Storage, erste Application-Controller und eine erste testbare Engine sind echte Libraries unter `lib/features/tournaments/`. Die UI- und Mode-Dateien haengen aber noch in einer gemeinsamen Uebergangs-Library `tournament_workspace.dart`, weil viele Dateien weiterhin `part of '../../../../tournament_workspace.dart'` verwenden. Das ist fuer schnelles Wachstum noch unbequem: private Klassen sind ueberall sichtbar, Abhaengigkeiten sind unscharf, und grosse UI-Dateien ziehen Domain- und Persistenzlogik indirekt mit.

Das Ziel ist eine modulare Flutter-App, in der neue Features als eigene Bereiche entstehen und Turnierlogik ohne UI getestet werden kann.

## Aktuelle Hauptbereiche

- `lib/main.dart`: Bootstrap und Export der bisherigen oeffentlichen App-API.
- `lib/app/dart_tournament_app.dart`: App-Shell.
- `lib/app/app_theme.dart`: App-Theme.
- `lib/tournament_workspace.dart`: temporaere Sammel-Library fuer verbleibende `part`-Dateien.
- `lib/home_page.dart`: Hauptmenue und Turnier-Uebersicht.
- `lib/features/tournaments/domain/tournament_models.dart`: Modelle, JSON-Helfer und Serialisierung.
- `lib/features/tournaments/data/tournament_storage.dart`: lokale JSON-Speicherung.
- `lib/features/tournaments/domain/engines/tournament_engine.dart`: erste testbare Domain-Engine.
- `lib/features/tournaments/application/*`: erste Controller fuer Creation und Run-Fortschritt.
- `lib/features/tournaments/domain/rules/tournament_rules.dart`: gemeinsame Turnierregeln, noch als Part.
- `lib/features/tournaments/modes/**`: Regeln/Builder fuer einzelne Turniermodi, noch als Parts.
- `lib/features/tournaments/presentation/pages/**`: Creation- und Run-Seiten, noch als Parts.
- `lib/features/tournaments/presentation/widgets/**`: viele Widgets, Tabellen, Brackets und Dialoge, noch als Parts.
- `lib/features/tournaments/presentation/widgets/run/stage_controls.dart`: erste echte Run-Widget-Library fuer Stage-Navigation, Ansichtsschalter und Footer.
- `lib/features/tournaments/presentation/widgets/run/stage_play_order_section.dart`: echte Widget-Library fuer die Spielreihenfolge-Ansicht.
- `lib/features/tournaments/presentation/widgets/run/result_entry.dart`: echte Run-Widget-Library fuer MatchResultTile und ResultDialog.
- `lib/features/tournaments/presentation/widgets/run/stage_surface.dart`: echtes gemeinsames Layout-Widget fuer Run-Sektionen.
- `lib/features/tournaments/presentation/widgets/run/standings_table.dart`: echte Widget-Library fuer Gruppentabellen.
- `lib/features/tournaments/presentation/widgets/run/group_run_section.dart`: echte Widget-Library fuer Round-Robin-Gruppen im Turnierlauf.
- `lib/features/tournaments/presentation/widgets/run/group_stage_run_section.dart`: echte Widget-Library fuer Gruppenphasen im Turnierlauf.
- `lib/features/tournaments/presentation/widgets/run/mini_knockout_group_run_section.dart`: echte Widget-Library fuer Mini-/Elimination-Gruppen im Turnierlauf.
- `lib/features/tournaments/presentation/widgets/run/best_of_comparison_table.dart`: echte Widget-Library fuer Best-of-Gruppenvergleich.
- `lib/features/tournaments/presentation/widgets/run/knockout_run_section.dart`: echte Widget-Library fuer K.-o.-Etappen im Turnierlauf.
- `lib/features/tournaments/presentation/widgets/run/brackets/knockout_bracket_view.dart`: zusammenhaengendes Bracket-Modul fuer Single-/Double-/Triple-KO-Ansichten.
- `lib/features/tournaments/presentation/widgets/creation/stage_setup_widgets.dart`: echte Widget-Library fuer kleine Creation-Setup-Bausteine wie Spieler-Dialog, Gruppengroessen, Gruppenspieltyp, Round-Robin-Wiederholungen, Matchzaehlung, Tie-Breaker und Qualifikations-Auswahl.
- `lib/features/tournaments/presentation/models/match_result.dart`: erstes echtes Presentation-Model.

## Probleme, die wir beim Weiterbau vermeiden wollen

- Keine neuen Monsterdateien.
- Keine neue Fachlogik direkt in Widgets, wenn sie als Service/Engine testbar waere.
- Keine weitere Kopplung ueber globale private Helfer in `part`-Dateien.
- Keine unversionierten Speicherformat-Aenderungen.

## Prioritätshinweise

Die geräteweiten Schwellen und die relative Gruppenfortschrittslogik sind unter
[`tournament_priority_hints.md`](tournament_priority_hints.md) dokumentiert.
Die Einstellungswerte werden mit versionierten `SharedPreferences`-Schlüsseln
gespeichert und bei fehlenden Werten mit den bisherigen Defaults geladen.
- Keine neuen Features direkt in bestehende Turnierseiten pressen, wenn ein eigener Feature-Bereich sinnvoll ist.

## Zielstruktur

```text
lib/
  main.dart
  app/
    dart_tournament_app.dart
    app_theme.dart
    navigation/
  features/
    home/
      presentation/
    tournaments/
      data/
        tournament_storage.dart
        tournament_json_codec.dart
      domain/
        models/
        rules/
        engines/
      application/
        tournament_creation_controller.dart
        tournament_run_controller.dart
      presentation/
        pages/
        widgets/
      modes/
        groups/
        knockout/
        double_ko/
        triple_ko/
  shared/
    widgets/
    utils/
```

## Empfohlene Refactor-Reihenfolge

1. `DartTournamentApp` und Theme aus den Modellen loesen. Erledigt am 2026-06-28.
   - App-Root liegt in `lib/app/dart_tournament_app.dart`.
   - Theme liegt in `lib/app/app_theme.dart`.
   - `main.dart` ist Bootstrap.

2. Domain-Modelle aus `tournament_workspace.dart` extrahieren. Erledigt am 2026-06-28.
   - Ziel: reine Modelle ohne Flutter-Importe.
   - JSON-Code ist noch in den Modellen und kann spaeter weiter in `data/tournament_json_codec.dart` getrennt werden.

3. Persistenz isolieren. Erledigt am 2026-06-28.
   - Ziel: `TournamentStorage` kennt Dateiablage und Codec, aber keine UI.
   - Schema-Version sichtbar halten und Migrationen vorbereiten.

4. Erste Tournament-Engine einfuehren. Erledigt am 2026-06-28.
   - `TournamentEngine` kapselt Round-Robin, Matchzaehlung und Basis-Seeding.
   - Weitere Mode-Logik soll folgen.

5. Run-Presentation schrittweise entkoppeln. Begonnen am 2026-06-30.
   - Stage-Controls, StagePlayOrderSection, MatchResult, MatchResultTile, ResultDialog, StageSurface, StandingsTable, GroupRunSection, GroupStageRunSection, MiniKnockoutGroupRunSection, BestOfComparisonTable und KnockoutRunSection sind echte Libraries.
   - Bracket-Widgets liegen bewusst gemeinsam in einem Bracket-Modul. Erst weiter splitten, wenn die Datei fachlich auseinanderwaechst oder konkrete Wartungsprobleme entstehen.

6. Creation-Presentation schrittweise entkoppeln. Begonnen am 2026-06-30.
   - StageSetupWidgets sind eine echte Library fuer kleine, wiederverwendbare Creation-Bausteine inklusive QualificationRuleSummary, QualificationErrorBanner und QualificationGroupPreview.
   - `tieBreakerLabel` liegt in der Domain, damit neue Widgets nicht mehr an alte Mode-Parts gekoppelt werden.
   - Die Eliminations-/KO-Vorschauen bleiben vorerst im alten Creation-Part, weil sie noch an private KO-Helfer gekoppelt sind.

7. Turnierlogik aus Seiten extrahieren.
   - Ziel: Engines fuer Gruppen, Knockout, Double-KO, Triple-KO.
   - Unit-Tests fuer Builder, Weiterkommen, Tie-Breaker, Platzierungsspiele.

8. UI in kleinere Feature-Widgets zerlegen.
   - Creation-UI: Spieler, Etappenformular, Gruppenoptionen, KO-Setup, Vorschauen.
   - Run-UI: Stage-Navigation, Gruppenansicht, Bracketansicht, Ergebnisdialog, Tabellen.

## Regeln fuer neue Features

- Erst entscheiden, ob es ein neuer Bereich, ein Turniermodus, eine Storage-Erweiterung oder nur ein Widget ist.
- Neue Bereiche unter `features/<feature-name>/` anlegen.
- Neue Turniermodi mit Engine plus Tests beginnen, danach UI anschliessen.
- Bei Aenderungen am gespeicherten JSON `schemaVersion` und Migration mitdenken.
- Nach jedem Refactor mindestens `flutter analyze` und `flutter test` laufen lassen.
