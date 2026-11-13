# 🎯 DartTournamentPro (Dart Turnierverwaltung)

[![Version](https://img.shields.io/badge/version-2.7.5%2B95-blue.svg)](CHANGELOG.md)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart)](https://dart.dev)
[![Plattformen](https://img.shields.io/badge/Plattformen-Windows%20|%20Android%20|%20Linux%20|%20macOS-success.svg)]()

**Die professionelle Komplettlösung für Dartturniere, Vereinsbetrieb, Spielerstatistiken und Ranglisten.**

DartTournamentPro ist eine moderne, hochflexible Dartturnier- und Vereinsverwaltungsanwendung für den Steeldartsport. Sie vereint die Organisation und Durchführung von Turnieren mit automatischer Board-Zuweisung, Sprachansagen, einer zentralen Spielerverwaltung, detaillierten Statistiken, konfigurierbaren Elo- und Punkteranglisten sowie einem motivierenden Errungenschafts- und Levelsystem.

---

## 📋 Inhaltsverzeichnis

1. [Funktionen im Überblick](#-funktionen-im-überblick)
2. [Menüstruktur & Navigation](#-menüstruktur--navigation)
3. [Turnierverwaltung](#-turnierverwaltung)
   - [Turniererstellung & KI-Formfinder](#turniererstellung--ki-formfinder)
   - [Unterstützte Spielsysteme & Modi](#unterstützte-spielsysteme--modi)
   - [Live-Turnierleitung & Board-Management](#live-turnierleitung--board-management)
   - [Player Insights & Live-Statistiken](#player-insights--live-statistiken)
   - [Sprachausgabe & Audio-Ansagen](#sprachausgabe--audio-ansagen)
   - [Zweitmonitor, TV-Präsentation & Live-Ticker](#zweitmonitor-tv-präsentation--live-ticker)
4. [Spielerverwaltung & Profile](#-spielerverwaltung--profile)
5. [Statistiken & Jahresrückblicke](#-statistiken--jahresrückblicke)
6. [Ranglisten & Wertungssysteme](#-ranglisten--wertungssysteme)
7. [Errungenschaften & Levelsystem (Achievements)](#-errungenschaften--levelsystem-achievements)
8. [Einstellungen & Werkzeuge](#-einstellungen--werkzeuge)
9. [Schnittstellen & Cloud-Synchronisation](#-schnittstellen--cloud-synchronisation)
10. [Entwicklung & Start](#-entwicklung--start)
11. [Dokumentation](#-dokumentation)

---

## ✨ Funktionen im Überblick

- **Vielseitige Spielsysteme:** Kombination von bis zu 3 Etappen (Gruppenphasen, Single KO, Double KO, Triple KO, Kratzer mit Bonusleben, Schweizer System, Ligaspiele und Freundschaftsspiele).
- **KI-gestützter Turnierformfinder:** Berechnet anhand von Spieleranzahl, Scheiben und Zieldauer automatisch das optimale Turniermodell inklusive Leg-Distanzen.
- **Turnierleiter-Dashboard:** Intelligente Scheibenzuweisung, automatisches Nachrücken freier Boards, Prioritätssteuerung bei Spielrückständen und Match-Empfehlungen.
- **Text-to-Speech & Soundeffekte:** Automatische Audio-Ausrufe für aufgerufene Begegnungen ("Spieler A gegen Spieler B an Board X") und Erinnerungen bei freien Boards.
- **Player Insights:** Live-Statistikbadges an Spielpaarungen (Siegesserien, Angstgegner, Rivalen, Decider-Stärke, Formkurven).
- **Zweitmonitor-Modus & Standalone-App:** Vollbild-Präsentationsmodus für Fernseher oder Beamer im Vereinsheim mit aktiven Partien, Scheibenbelegung und QR-Code für Zuschauer.
- **Errungenschaften & XP-System:** Über 8 Kategorien an Erfolgen mit Spieler-Levels, XP-Fortschritt und pro Rangliste individuell anpassbaren Zielwerten.
- **Flexible Ranglisten:** ELO-Ranglisten mit Tiersystem (Divisionen) und interaktiven Trajektorien sowie klassische Punkteranglisten (Serienwertungen) mit Hochformat-PNG-Export.
- **Zentrale Spielerverwaltung:** Spielerprofile mit Averages, aufklappbaren Bestleistungen mit Turnierlink, Monatsstatistiken und Performance-Diagrammen.
- **Challonge-Import:** Nahtloser Import von Challonge-Turnieren inklusive Zuordnung zu Spielerkatalogen und rückwirkender Ranglistenberechnung.
- **Supabase Cloud-Sync & Backups:** Kontobasierte Cloud-Sicherung, versionsbezogene SQLite-Sicherungen und lokaler Sicherheits-Reset.
- **Website Read-Only API (v1 & v2):** Schreibgeschütztes Bereitstellen von Ranglisten, Profilen, Turnieren und Achievements für Vereinshomepages via Supabase Edge Function.
- **Smart-Home-Licht (Govee):** Lichteffekte im Vereinsheim bei Aufrufen, Siegen oder Bestleistungen.
- **In-App-Update:** Direkte Update-Installation für Windows und Android.

---

## 🧭 Menüstruktur & Navigation

Die Navigation passt sich automatisch an das Display an (Sidebar auf Desktop-Monitoren, mobiles Dropdown-Menü auf kompakten Bildschirmen):

| Menüpunkt | Beschreibung |
|---|---|
| **Übersicht** | Startseite mit Schnellstart, Schnellzugriffen, Cloud-Status und dynamischen rotierenden Infokarten (Turniere, Ranglisten, Bestleistungen). |
| **Turniere** | Übersicht gespeicherter Turniere, Schnellsuche, Filter, Neuanlage, Schnellbearbeitung, Challonge-Import und Archivierung. |
| **Spieler** | Zentraler Spielerkatalog, externe Kennungen (Autodarts, Scolia, 3K), Challonge-Links und detaillierte Spielerprofile. |
| **Statistiken** | Ranglisten- und Vereins-Jahresrückblicke, Head-to-Head Spieler-Vergleich und Leistungsdiagramme. |
| **Ranglisten** | Elo- und Punkteranglisten, Tiersystem, chronologische Match-Historien, monatliche Vereinsperformance und PNG-Export. |
| **Einstellungen** | Erreichbar über das Zahnrad oben rechts; unterteilt in *Daten*, *Updates*, *Darstellung* und *Sonstige Einstellungen*. |

---

## 🏆 Turnierverwaltung

### Turniererstellung & KI-Formfinder

Turniere können flexibel für verschiedene Zwecke erstellt werden:
- **Normales Turnier:** Freies Turnier ohne Ranglistenbezug.
- **Ranglistenturnier:** Wertung für eine oder mehrere ausgewählte Ranglisten.
- **Ligaspiel:** Spielbericht-Modus für Vereins-Ligabegegnungen (Einzel, Doppel, Board-Runtime).
- **Freundschaftsspiel:** Schneller Wettkampf zweier Spieler.
- **Turnierformfinder:** Ermittelt nach Angabe von Teilnehmerzahl, Boards und Wunschdauer (z. B. 3 Stunden) das am besten geeignete Format samt Best-of-Distanzen.

### Unterstützte Spielsysteme & Modi

Bis zu **3 Etappen** können kombiniert werden (z. B. Gruppenphase gefolgt von K.-o.-Runde):
- **Gruppenphase:** Round Robin (Einfach-/Mehrfachrunde), Mini-KO, Begrenzung der Spiele pro Spieler, konfigurierbare Tie-Breaker (Matchpunkte, Legdifferenz, gewonnene Legs, direkter Vergleich), Gruppen-Position-Editor.
- **Single Knockout:** Klassischer K.-o.-Baum mit optionalem Spiel um Platz 3.
- **Double Knockout:** Winner- und Loser-Bracket mit Re-Entry-Möglichkeit.
- **Triple Knockout:** Drei Bracket-Ebenen (A-, B- und C-Bracket) für ausgedehnte Turniere.
- **Kratzer-Turnier (Elimination):** Traditionelles Darts-Ausscheidungsverfahren mit Leben ("Kratzern"), Neuauslosung je Runde (3–6 Spieler pro Board), Option "Gleiche Kratzerzahl bevorzugen", Bonusleben bei 180ern und Zeitprognose.
- **Schweizer System (Swiss):** Paarungen nach Zwischenstand mit Buchholz-Feinwertung.

### Live-Turnierleitung & Board-Management

Während des Turniers stehen dem Turnierleiter spezialisierte Ansichten zur Verfügung:
- **Dashboard:** Live-Fortschritt, aktuelle Matches, Podiumsprognose und Gesamtzeitplan.
- **Ergebnisse:** Interaktive Brackets und Tabellen, Bestleistungserfassung (180er, Shortlegs 10–18 Darts, High Finishes bis 170).
- **Turnierleiter-Modus (Director Dashboard):**
  - Schnelle Zuweisung und Überwachung aller Scheiben.
  - Automatisches Nachrücken freier Boards.
  - Prioritätssteuerung: Erkennt Gruppen mit Spielrückständen und empfiehlt Partien zur Vermeidung von Verzögerungen (absolut oder prozentual).
  - Zeitverschiebung: Bei nachträglichen Datumskorrekturen werden Match-Zeitstempel konsistent verschoben, ohne Uhrzeiten oder Reihenfolge zu beeinträchtigen.
  - Spieler-Rückzug (Player Withdrawal) mit konfigurierbarer Wertung (kampflos oder Streichung).

### Player Insights & Live-Statistiken

Direkt an den Spielpaarungen werden situative Badges eingeblendet:
- **Hot Streak / Cold Streak:** Sieg- oder Niederlagenserien.
- **Angstgegner & Rivalen:** Historische Duelle und ausgeglichene Bilanzen.
- **Giant Slayer & Underdog:** Erfolge gegen signifikant höher platzierte Spieler.
- **Decider-Stärke:** Besondere Nervenstärke im letzten Leg.
- **Titelverteidiger & ELO Climber:** Formstarke Spieler im Aufwind.

### Sprachausgabe & Audio-Ansagen

- Automatische Sprachansage (TTS) für aufgerufene Spiele: *„Spieler A gegen Spieler B an Board X“*.
- Anpassbare Namensformate (voller Name oder Vorname + Nachnamenskürzel, Spitznamen bevorzugen).
- Akustische Board-Leerlauf-Erinnerungen bei unbespielten Scheiben (Intervall 1–5 Minuten).
- Ansage organisatorischer Verzögerungshinweise.

### Zweitmonitor, TV-Präsentation & Live-Ticker

- **Zweitmonitor-Modus (`TournamentSecondScreenView`):** Vollbildanzeige für Großbildschirme und Beamer.
- **Standalone-App (`SecondScreenStandaloneApp`):** Kann unabhängig für reine Display-Terminals gestartet werden.
- Zeigt bis zu **4 aktive Partien nebeneinander**, nächste Aufrufe und Brackets.
- Player Insights erscheinen dezent beim Hover über Spielernamen.
- QR-Code zur Anzeige des mobilen Live-Tickers für Besucher.

---

## 👥 Spielerverwaltung & Profile

- **Zentraler Katalog:** Spieler anlegen, suchen, filtern und für alle Turniere wiederverwenden.
- **Externe Verknüpfungen:** Autodarts-Name, Scolia-ID, 3K-Darts-ID und Challonge-Aliases.
- **Detailliertes Spielerprofil:**
  - Gesamtbilanz (Spiele, Legs, Siege, Quoten).
  - Aufklappbare Bestleistungen mit Direktlink zum Turnier.
  - Monatsstatistiken mit Jahresfiltern, Jahressummen und Monatsnamen.
  - Performance-Diagramme (Average-Kurven, Bestleistungen, Leistungsentwicklung).
  - Achievement-Status mit Level und XP-Balken.
  - Head-to-Head Spieler-Vergleichsseite.

---

## 📊 Statistiken & Jahresrückblicke

- **Jahresrückblicke:**
  - Analyse nach Rangliste oder individuellem Spieler.
  - Gespielte Legs, Turnierteilnahmen, Monatsaktivität und Bestleistungen-Zusammensetzung.
- **Historischer Statistik-Import:**
  - Import historischer Monatsstatistiken (z. B. aus Excel-Archiven).
  - Saubere Trennung von importierten Monatsaggregaten und tatsächlichen Einzelspielen.
- **Bestleistungs-Katalog:** Strukturierte Übersicht aller 180er, Shortlegs und High Finishes mit Filter- und Suchfunktionen.

---

## 📈 Ranglisten & Wertungssysteme

### ELO-Ranglisten
- Kontinuierliche Spielstärkeberechnung basierend auf echten Spielergebnissen.
- Konfigurierbarer K-Faktor, Startwert (Standard: 1000) und Rundung.
- **Tiersystem (Divisionen):** Einteilung der Spieler in Ränge (Bronze, Silber, Gold, Platin etc.).
- **Chronologische Korrektheit:** Nachträglich importierte oder eingefügte Turniere berechnen die ELO-Kurve historisch exakt neu.
- Interaktiver Elo-Trajektorien-Chart je Spieler.

### Punkteranglisten (Serienwertungen)
- Punkte für Teilnahmen, gewonnene Sets/Legs und Podestplätze (1., 2., 3. Platz).
- Zusatzpunkte für erfasste Bestleistungen (180er, Shortlegs, High Finishes).
- **Grafik-Export:** Ein-Klick-PNG-Export des Ranglistenstands im optimierten Hochformat zum Teilen auf Social Media oder Vereinsaushängen.

---

## 🎖️ Errungenschaften & Levelsystem (Achievements)

Das integrierte Achievement-System belohnt Aktivität, Spielstärke und Vereinsengagement:
- **8 Kategorien:** *Turniererfolge*, *Spielbetrieb*, *Scoring & Specials*, *Checkout & Präzision*, *Konstanz & Performance*, *Aktivität & Vereinstreue*, *Rivalitäten & Comebacks* sowie *Ranglisten-Awards*.
- **Individuelle Zielwerte:** Jede Rangliste kann eigene Zielvorgaben oder alternative Erfüllungswege definieren (z. B. andere Zielanzahl an 180ern für Hobbyligen).
- **XP & Spieler-Level:** Transparente Erfahrungspunkte mit Levelaufstiegen.
- **Live-Feedback:** Sofortige Freischalt-Benachrichtigungen beim Abschluss der Partie.

---

## ⚙️ Einstellungen & Werkzeuge

Über das Zahnrad-Symbol oben rechts erreichbar:
1. **Daten:** Supabase Cloud-Login, manuelle/automatische Backups, bytegetreue Sicherung und lokaler App-Reset (`ZURÜCKSETZEN`).
2. **Updates:** Integrierter Updater für Windows (mit PowerShell-Prozessüberwachung) und Android.
3. **Darstellung:** Eigenes Vereinslogo hochladen (bis 512 KB), Theme-Auswahl (Vereinsdesign oder Weihnachts-Theme mit Schneefall) und Dark Mode.
4. **Sonstige Einstellungen:**
   - **Player Insight Defaults:** Schwellenwerte für Siegesserien, Angstgegner und Rivalen.
   - **Govee API-Key:** Steuerung vernetzter Vereinsheim-Lichter.
   - **Auslosungsrad (Random Draw Tool):** Eigenständiges Rad für unabhängige Auslosungen.
   - **Turnierformfinder-Parameter:** Anpassung von Leg- und Wurfzeiten für die Zeitkalkulation.
   - **Tie-Breaker-Standardwerte:** Globale Reihenfolge bei Gleichstand.
   - **Dev Tools:** Entwicklerwerkzeuge und Testdaten.

---

## 🔗 Schnittstellen & Cloud-Synchronisation

| Schnittstelle | Funktion |
|---|---|
| **Supabase** | Multi-Device Cloud-Synchronisation und automatisches Backup im Storage-Bucket. |
| **Website Read-Only API (v2)** | Supabase Edge Function zur schreibgeschützten Auslieferung von Ranglisten, Profilen, Turnieren und Achievements für Vereinshomepages. [Details](docs/website_supabase_api.md). |
| **Challonge** | Import von Single KO, Double KO und Round Robin Turnieren inklusive Spieler-Matching. |
| **Govee API** | Lichtsteuerung im Vereinsheim bei Turnierevents. |
| **Autodarts / Scolia / 3K** | Hinterlegung und Verknüpfung externer Spieler-IDs. |

---

## 💻 Entwicklung & Start

### Voraussetzungen
- Flutter SDK (≥ 3.24)
- Dart SDK (≥ 3.5)

### Starten
```powershell
# Abhängigkeiten laden
flutter pub get

# Auf Desktop ausführen
flutter run -d windows
```

### Tests ausführen
```powershell
flutter test
```

---

## 📖 Dokumentation

- Ausführliches Handbuch: [`docs/APP_DOKUMENTATION.md`](docs/APP_DOKUMENTATION.md)
- Architektur-Notiz: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Website-API-Spezifikation: [`docs/website_supabase_api.md`](docs/website_supabase_api.md)
- Prioritätshinweise im Turnierbetrieb: [`docs/tournament_priority_hints.md`](docs/tournament_priority_hints.md)
- Release-Notes & Historie: [`docs/releases/`](docs/releases/) und [`CHANGELOG.md`](CHANGELOG.md)

---

**DartTournamentPro – Dein Spiel. Dein Turnier.**
