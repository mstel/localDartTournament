# Dart Tournament Manager (DartTournamentPro) – Gesamtdokumentation

**Version:** 2.6.3+83  
**Stand:** November 2026  
**Zielgruppe:** Turnierleiter, Vereinsadministratoren, Spieler und Entwickler

---

## Inhaltsverzeichnis

1. [Überblick & Systemarchitektur](#1-überblick--systemarchitektur)
2. [Menüstruktur & Navigation](#2-menüstruktur--navigation)
3. [Hauptbereiche im Detail](#3-hauptbereiche-im-detail)
   - [3.1 Startseite & Spielzentrale (Home)](#31-startseite--spielzentrale-home)
   - [3.2 Turniere (Erstellung, Durchführung, Auswertung)](#32-turniere-erstellung-durchführung-auswertung)
   - [3.3 Spielerverwaltung & Spielerprofile](#33-spielerverwaltung--spielerprofile)
   - [3.4 Statistiken, Performance & Jahresrückblicke](#34-statistiken-performance--jahresrückblicke)
   - [3.5 Ranglisten, Elo-System & Punkteranglisten](#35-ranglisten-elo-system--punkteranglisten)
   - [3.6 Errungenschaften & XP-System (Achievements)](#36-errungenschaften--xp-system-achievements)
   - [3.7 Zweitmonitor, TV-Präsentation & Live-Ticker](#37-zweitmonitor-tv-präsentation--live-ticker)
4. [Einstellungen & Verwaltung](#4-einstellungen--verwaltung)
   - [4.1 Daten & Backups](#41-daten--backups)
   - [4.2 Updates (Windows & Android)](#42-updates-windows--android)
   - [4.3 Darstellung & Themes](#43-darstellung--themes)
   - [4.4 Sonstige Einstellungen & Administration](#44-sonstige-einstellungen--administration)
5. [Schnittstellen, Synchronisation & externe Dienste](#5-schnittstellen-synchronisation--externe-dienste)
   - [5.1 Supabase Cloud-Sync & Workspace-Sicherung](#51-supabase-cloud-sync--workspace-sicherung)
   - [5.2 Website Read-Only API (v1 & v2)](#52-website-read-only-api-v1--v2)
   - [5.3 Challonge-Import & Spieler-Matching](#53-challonge-import--spieler-matching)
   - [5.4 Govee Smart-Lighting](#54-govee-smart-lighting)
6. [Tastatursteuerung & Barrierefreiheit](#6-tastatursteuerung--barrierefreiheit)

---

## 1. Überblick & Systemarchitektur

Der **Dart Tournament Manager** ist eine modulare Flutter-Anwendung für Steeldart-Turniere, Vereinswettbewerbe, Ligen und Spielerserien. Kernziel ist die nahtlose Verbindung von:
- flexibler **Turnierorganisation** (1 bis 3 Etappen mit unterschiedlichen Spielmodi),
- **Echtzeit-Turnierleitung** mit automatischer Board-Zuweisung, Prioritätssteuerung und Sprachausgabe,
- langfristiger **Spielerverwaltung** mit Elo-Wertungen, Bestleistungen und Monatsstatistiken,
- einem **Achievement- & Levelsystem** mit individuellen Zielwerten,
- und externer **Präsentation** über Zweitmonitore, Live-Ticker sowie eine Supabase Website-API.

### Technologie-Stack
- **Framework:** Flutter 3.x / Dart 3.x
- **Lokale Persistenz:** SQLite (Schema Version 15) & JSON-Dateispeicher für Turniere
- **Cloud-Backend:** Supabase (Auth, PostgreSQL, Storage, Edge Functions)
- **Audio:** Lokale Text-to-Speech (TTS) & Soundeffekte (`audioplayers`)
- **Unterstützte Betriebssysteme:** Windows, Android, macOS, Linux, iOS

---

## 2. Menüstruktur & Navigation

Die Navigation basiert auf der responsiven `SportAppShell`:
- **Desktop / Breitbild (≥ 1100 px):** Feste Seitenleiste links mit Vereins-Branding, Navigationselementen und Slogan (*„Dein Spiel. Dein Turnier.“*).
- **Mobil / Tablet (< 1100 px):** Kompakte obere Leiste mit Schnellzugriffs-Menü (Dropdown) zur Umschaltung der Bereiche.

```
├── Übersicht (Home)
│   ├── Schnellstart "Turnier erstellen"
│   ├── Spielzentrale (Kacheln zu allen Bereichen)
│   ├── Dynamisches Infopanel (rotierende Übersicht alle 5s)
│   └── Einstellungen (Zahnrad-Symbol)
├── Turniere
│   ├── Turniersuche & Sortierung (Datum, Änderung, Alphabet)
│   ├── Turnier erstellen (Wizard / Schnellmodi)
│   ├── Challonge-Turniere importieren / exportieren
│   └── Turnierkarten mit Schnellaktionen (Öffnen, Kopieren, Endzeit ändern, Löschen)
├── Spieler
│   ├── Spielerkatalog & Suche (Name, Spitzname, IDs)
│   ├── Spieler anlegen & bearbeiten (inkl. Autodarts, Scolia, 3K-Darts)
│   ├── Challonge-Verknüpfungen verwalten
│   └── Spielerprofil (Statistiken, Bestleistungen, Formkurven, Achievements)
├── Statistiken
│   ├── Jahresrückblick (Filter nach Rangliste, Spieler, Jahr)
│   ├── Spieler-Vergleich (Head-to-Head Gegenüberstellung zweier Spieler)
│   └── Direkte Profilstatistiken
├── Ranglisten
│   ├── Übersicht bestehender Ranglisten (Elo- & Punkteserien)
│   ├── Rangliste erstellen / konfigurieren (K-Faktor, Tiers, Punkte)
│   ├── Spieler- & Turnierzuweisung
│   ├── Ranglistenstand mit Hochformat-PNG-Export
│   ├── Elo-Trajektorien & Matchhistorie je Spieler
│   └── Ranglisten-Achievements & monatliche Vereinsperformance
└── Einstellungen (Zahnrad oben rechts)
    ├── 1. Daten (Cloud-Sync, Backups, lokaler Reset)
    ├── 2. Updates (In-App-Update Windows & Android)
    ├── 3. Darstellung (Vereinslogo, Themes, Dark Mode)
    └── 4. Sonstige Einstellungen (Push, Insights, Govee, Auslosungsrad, Turnierformfinder, Tie-Breaker, Dev-Tools)
```

---

## 3. Hauptbereiche im Detail

### 3.1 Startseite & Spielzentrale (Home)
- **SportHero:** Direkter Einstieg zur Erstellung eines neuen Turniers.
- **Schnellnavigation:** Vier Schnellzugriffskarten (Turniere, Spieler, Statistiken, Ranglisten).
- **HomeActivityPanel:**
  - Zeigt aktuell laufende Turniere sofort oben an.
  - Läuft kein Turnier, wechselt eine Übersicht alle 5 Sekunden automatisch zwischen:
    - *Aktueller Ranglistenführer & Top-Platzierte*
    - *Zuletzt gespielte Turniere & Sieger*
    - *Aktuelle Bestleistungen (180er, Shortlegs, High Finishes)*
  - Live-Statusanzeige der Supabase-Cloud-Synchronisation.

---

### 3.2 Turniere (Erstellung, Durchführung, Auswertung)

#### Turniererstellung
1. **Turnier-Kategorien:**
   - *Normales Turnier:* Unabhängiges Turnier ohne Wertung.
   - *Ranglistenturnier:* Ergebnisse fließen in eine oder mehrere zugeordnete Ranglisten ein.
   - *Ligaspiel:* Team-Spielbericht mit Einzel- und Doppelbegegnungen sowie Board-Zuweisung.
   - *Freundschaftsspiel:* Schneller Einzelwettkampf.
   - *KI-gestützter Turnierformfinder:* Ermittelt basierend auf Spielerzahl, Scheibenanzahl und Zieldauer (z. B. 3 Stunden) automatisch das optimale Format inklusive Best-of-Distanzen.
2. **Unterstützte Turniermodi (bis zu 3 Etappen kombinierbar):**
   - **Gruppenphase (Round Robin / Mini-KO):**
     - Konfigurierbare Gruppengrößen, einfache oder mehrfache Runden.
     - Begrenzung der Spiele pro Spieler (Game Limits).
     - Tie-Breaker-Reihenfolge (Matchpunkte, Legdifferenz, gewonnene Legs, direkter Vergleich).
     - Gruppen-Position-Editor zur manuellen Setzung vor Beginn.
   - **Single Knockout:** Klassisches K.-o.-System mit optionalem Spiel um Platz 3.
   - **Double Knockout:** Gewinner- und Verlierer-Bracket für eine zweite Chance.
   - **Triple Knockout:** Drei Bracket-Ebenen (A, B, C) mit voller Bracket-Übersicht.
   - **Kratzer-Turnier (Elimination):**
     - Traditioneller Modus: Spieler scheiden nach Verbrauch ihrer Leben ("Kratzer") aus.
     - 3 bis 6 Spieler pro Board, automatische Board-Neuauslosung je Runde.
     - Option "Gleiche Kratzerzahl bevorzugen".
     - Bonusleben bei besonderen Leistungen (z. B. 180er).
     - Integrierte Spielzeit- und Runden-Vorschau.
   - **Schweizer System (Swiss):** Paarungen nach Rundenscores mit Buchholz-Feinwertung.
3. **Teilnehmer & Seeding:**
   - Auswahl aus dem zentralen Spielerkatalog oder Schnellanlage lokaler Spieler.
   - Seeding über Drag-and-Drop, Zufallsauslosung oder Leistungsstufen.

#### Live-Turnierdurchführung (`TournamentRunPage`)
- **Etappen-Navigation:** Fortschrittsleiste der Etappen mit Statusindikator.
- **Ansichtsmodi:**
  - **Dashboard:** Live-Turnierfortschritt, aktuelle Partien, Podiumsprognose, Gesamtzeitleiste.
  - **Ergebnisse:** Interaktive Brackets und Tabellen, Ergebniseingabe mit Bestleistungen-Dialog.
  - **Turnierleiter (Director Dashboard):**
    - Board-Status (Belegt, Frei, Wartend).
    - Automatische Board-Empfehlungen ohne Blockade gleicher Gruppen.
    - Gruppen-Prioritätslogik: Bevorzugt Partien aus Gruppen mit absolutem oder prozentualem Spielrückstand.
    - Sprachansagen (TTS): Automatisches Ausrufen aufgerufener Spiele an der Scheibe.
    - Akustische Board-Leerlauf-Meldung (einstellbar nach 1–5 Minuten).
  - **Spielplan (Order of Play):** Geordnete Abfolge anstehender Matches je Board.
  - **Spielerliste:** Umbenennen von Spielern und Spielerrückzug (Player Withdrawal: kampflose Wertung oder Streichung).
  - **Einstellungen:** Board-Namen, Schwellenwerte, Audio-Einstellungen live im laufenden Turnier anpassbar.
- **Zeitverwaltung:**
  - Nachträgliches Verschieben des Turniertags: Passt Match-Zeitstempel konsistent an das gewählte Datum an, ohne Uhrzeiten oder Abfolge zu verfälschen.

#### Turnierabschluss & Auswertung
- Siegerpodest und Abschlussplatzierungen.
- Detaillierte Matchstatistiken und Bestleistungen.
- Hochformat-PNG-Bildexport der Abschlussgrafik für Vereinsaushänge und Social Media.

---

### 3.3 Spielerverwaltung & Spielerprofile

- **Spielerkatalog:** Zentrale Erfassung mit Such- und Filterfunktionen.
- **Profilfelder:** Vorname, Nachname, Spitzname, Geburtsdatum, externe System-IDs (Autodarts, Scolia, 3K-Darts).
- **Challonge-Verknüpfungen:** Beliebig viele Challonge-Aliases können einem Spielerprofil zugeordnet oder wieder getrennt werden.
- **Statistik-Profil:**
  - Spiele, Legs, Siege, Niederlagen, Siegquote.
  - Aufklappbare Bestleistungen mit Direktlink zum entsprechenden Turnier.
  - Monatsstatistiken (aggregierte Spiele, Averages, Checkouts) mit Jahresfiltern und Summen.
  - Interaktive Performance-Diagramme (Average-Entwicklung, 180er, Shortlegs, High Finishes).
  - Errungenschaften-Fortschrittsbalken und Spieler-Level.

---

### 3.4 Statistiken, Performance & Jahresrückblicke

- **Jahresrückblicke:**
  - Auswertung nach Rangliste oder einzelnem Spieler für beliebige Jahre.
  - Kennzahlen: Absolvierte Turniere, gespielte Legs, Monatsaktivität und Bestleistungs-Kategorien.
  - Exportfunktion für die Jahresübersicht.
- **Spieler-Vergleich (Head-to-Head):**
  - Direkter Vergleich zweier ausgewählter Spieler: Direkte Duelle, Siegquoten, Bestleistungen und Elo-Historie.
- **Historischer Statistik-Import:**
  - Import historischer Monatsstatistiken (z. B. aus Excel-Archiven).
  - Werden sauber von Live-Spielen getrennt in Profilen und Jahresrückblicken berücksichtigt.

---

### 3.5 Ranglisten, Elo-System & Punkteranglisten

- **Elo-Ranglisten:**
  - Mathematische Spielstärke-Bewertung mit konfigurierbarem K-Faktor und Start-Elo (Standard: 1000).
  - Tiersystem (Divisionen wie Bronze, Silber, Gold, Platin etc.) mit definierbaren Wertebereichen.
  - Chronologische Neuberechnung: Bei nachträglich eingefügten oder importierten Turnieren wird die Elo-Historie zeitlich exakt rekonstruiert.
  - Interaktiver Elo-Trajektorien-Chart je Spieler.
- **Punkteranglisten (Serienwertungen):**
  - Frei definierbare Punkte für Turnierteilnahme, gewonnene Sets/Legs, Podestplätze (1., 2., 3. Platz).
  - Bonuspunkte für Bestleistungen (180er, Shortlegs, High Finishes).
- **Grafik-Export:** Ein-Klick-PNG-Export des aktuellen Ranglistenstands im optimierten Hochformat.

---

### 3.6 Errungenschaften & XP-System (Achievements)

Das integrierte Achievement-System motiviert Spieler langfristig über Ranglisten hinweg:
- **Kategorien:**
  - *Turniererfolge* (Teilnahmen, erste Siege, Mehrfachtriumphe)
  - *Spielbetrieb* (Meilensteine an absolvierten Spielen und gewonnenen Legs)
  - *Scoring & Specials* (180er, Maximum-Serien)
  - *Checkout & Präzision* (High Finishes, Bull-Finishes, Shortlegs)
  - *Konstanz & Performance* (Siegesserien, Decider-Erfolge, Average-Hürden)
  - *Aktivität & Vereinstreue* (Regelmäßige Teilnahmen über Monate hinweg)
  - *Rivalitäten & Comebacks* (Siege nach Rückstand, Angstgegner schlagen)
  - *Ranglisten-Awards* (Tier-Aufstiege, Top-Platzierungen)
- **Konfigurierbare Zielwerte:**
  - Jede Rangliste kann Standard-Zielwerte oder alternative Anforderungen definieren.
  - Die Texte passen sich live den konfigurierten Zielen an.
- **Live-Benachrichtigungen:**
  - Bei Freischaltung während eines Turniermatches wird der Erfolg sofort mit Badge an der Spielpaarung signalisiert.

---

### 3.7 Zweitmonitor, TV-Präsentation & Live-Ticker

- **Zweitmonitor-Modus (`TournamentSecondScreenView` / `SecondScreenStandaloneApp`):**
  - Eigener Vollbildmodus für Fernseher und Beamer im Vereinsheim.
  - Zeigt bis zu 4 aktive Partien nebeneinander mit großen Spielständen.
  - Übersicht über Board-Belegungen und als nächstes aufgerufene Partien.
  - Player Insights (Formkurven, Serien, Angstgegner) werden dezent beim Hover angezeigt.
  - QR-Code-Einblendung für den mobilen Live-Ticker der Zuschauer.
  - Flexible Platzierung der Widgets konfigurierbar.

---

## 4. Einstellungen & Verwaltung

Erreichbar über das Zahnrad-Symbol oben rechts. Gegliedert in 4 Hauptbereiche:

### 4.1 Daten & Backups
- **Supabase-Cloud-Konto:** Login / Registrierung und automatischer Datenabgleich.
- **Datenbanksicherung:** Lokale manuelle und automatische Backups der SQLite-Datenbank.
- **Lokale App-Daten zurücksetzen:** Bytegetreue Sicherung gefolgt vom Zurücksetzen aller lokalen Daten bei Eingabe von `ZURÜCKSETZEN`.

### 4.2 Updates (Windows & Android)
- Integrierte Prüfung gegen das GitHub-Repository.
- **Windows:** PowerShell-basiertes Update-Programm mit bis zu 120 Sekunden Prozessüberwachung und Exitcode-Logging.
- **Android:** Direkter Download und Installation der neuesten APK.

### 4.3 Darstellung & Themes
- **Vereinslogo:** Eigenes Logo (PNG, JPG, WebP bis 512 KB) hochladbar.
- **Farbthemen:** Vereinsdesign (DC Unzenberg/Heinzenbach) oder saisonales **Weihnachts-Theme** mit Schnee- und Dekorationsanimationen.
- **Theme-Modus:** Hell, Dunkel (Dark Mode) oder Systemeinstellung.

### 4.4 Sonstige Einstellungen & Administration
- **Push-Benachrichtigungen:** Sender- und Gerätekonfiguration für Spielaufrufe.
- **Player Insight Defaults:** Globale Schwellenwerte für Hot Streaks, Angstgegner, Rivalen und Underdogs.
- **Govee API-Key:** Hinterlegung des Schlüssels zur Steuerung von Vereinsheim-Lichtern.
- **Auslosungsrad (Random Draw Tool):** Eigenständiges Glücksrad zur unabhängigen Gruppenauslosung.
- **Turnierformfinder-Parameter:** Anpassung von Leg-Dauern, Wurfzeiten und Pufferzeiten für die KI-Kalkulation.
- **Tie-Breaker-Standardwerte:** Festlegung der globalen Standardreihenfolge bei Punktegleichstand.
- **Dev Tools:** Werkzeuge für Entwickler, Simulationen und Testdaten.

---

## 5. Schnittstellen, Synchronisation & externe Dienste

### 5.1 Supabase Cloud-Sync
- Verschlüsselte Sicherung aller Turniere, Spieler, Ranglisten, Statistiken und Achievements im Bucket `dart-app-backups/<user-id>/`.
- Multi-Device-Fähigkeit: Mehrere Geräte können denselben Datenbestand nutzen.

### 5.2 Website Read-Only API (v1 & v2)
- Supabase Edge Function `website-read-model`.
- Stellt Ranglisten, Elo-Historien, Turnierzusammenfassungen, Spielerprofile, Bestleistungen und Achievements schreibgeschützt für Vereinshomepages oder Info-Screens bereit.
- Version 2 unterstützt paginiertes Laden einzelner Ressourcen (`tournaments`, `rankings`, etc.).

### 5.3 Challonge-Import
- Import von Turnieren im JSON-Format aus Challonge.
- Unterstützt Single KO, Double KO und Round Robin.
- Intelligente Zuordnung von Challonge-Teilnehmern zu Profilen im Spielerkatalog oder Übernahme als Gastspieler.
- Konvertierung in native, voll editierbare Turniere.

### 5.4 Govee Smart-Lighting
- Steuerung vernetzter Govee-Lampen über HTTP-API.
- Automatische Lichteffekte bei Turnierereignissen (z. B. Aufruf, Sieg, 180er).

---

## 6. Tastatursteuerung & Barrierefreiheit

- **Dropdown-Navigation per Pfeiltasten:** Alle Auswahldialoge unterstützen die Navigation mit Pfeil-oben/Pfeil-unten und Bestätigung mit Enter (`ArrowKeyDropdownNavigation`).
- **Touch- & Maus-Scrolling:** Flüssiges Scrollen auf Laptops, Touchscreens und klassischen Desktop-PCs.
- **Semantische Labels:** Optimiert für Screenreader bei Ladebalken, Löschvorgängen und Statusmeldungen.
