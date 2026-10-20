# Dart Tournament Manager 1.0.7+8

## Wiederhergestellte Funktionen und Kompatibilität

- Stellt Ranglisten-Navigation, Spielernamen im TV-Modus, interaktive
  Elo-Turnierpunkte, Turniersiege und Turnierquote im Profil sowie die
  Dashboard-Übersicht wieder her.
- Behebt die Ranglisten-Abwahl in laufenden Turnieren und verhindert
  konkurrierende doppelte Speichervorgänge.
- Unterstützt das historisch belegte Einstellungsformat Schema 3. Unbekannte
  Formate bleiben abgelehnt; Laden allein verändert die Quelldatei nicht.
- Unterstützt Turnierspeicher-Schema 24 und verbessert die
  Aktivierungsbestätigung des Windows-Updaters samt Fallback.
- Ergänzt Regressionstests für UI-Parität, Einstellungen, Gruppen-/Swiss-
  Siegerregeln und den Windows-Update-Handoff.

## Datensicherheit

Vor dem Update die vollständige Sicherung von
`%APPDATA%\DartTournamentManager` aufbewahren. Keine Turnierdatei oder
Sicherung löschen oder durch einen älteren Stand ersetzen.

Lokale Gerätebestände werden nicht automatisch zusammengeführt oder gegenseitig
überschrieben. Bei unterschiedlichen Turnierzahlen jede Gerätesicherung
getrennt behalten und den kanonischen Stand vor einem manuellen Abgleich
bewusst festlegen. Unbekannte höhere Speicherformate bleiben geschützt und
werden abgelehnt.

# Dart Tournament Manager 1.0.6+7

## Fehlerbehebung: Schema-24-Turnierdaten

- Stellt die Unterstützung für Turnierspeicher-Schema 24 wieder her. Version
  24 wurde von `v1.0.3+3` geschrieben; `v1.0.4+4` hatte lediglich die
  akzeptierte Versionsgrenze auf 23 zurückgesetzt.
- Erhält beim Laden und erneuten Speichern den expliziten
  `countsForRanking`-Wert aus Schema-24-Datensätzen.
- Benötigt für Schema 24 keine `.v22.bak` aus einem anderen AppData-Pfad.
  Beim ersten späteren Speichern wird die vorhandene Turnierdatei wie üblich
  als `.bak` gesichert.
- Höhere unbekannte Speicherversionen bleiben geschützt und werden abgelehnt.

Vor dem Update die vollständige Sicherung von
`%APPDATA%\DartTournamentManager` aufbewahren. Keine Turnierdatei oder
Sicherung löschen oder durch einen älteren Stand ersetzen.

# Dart Tournament Manager 1.0.5+6

## Fehlerbehebungen

- Turnierspeicher mit Schema-Version 24 werden nur dann wieder lesbar, wenn
  `tournaments.json.v22.bak` vorhanden ist und bis auf das Wurzelfeld
  `schemaVersion` semantisch exakt übereinstimmt. Unbekannte oder nicht
  belegbare Speicherstände bleiben unverändert gesperrt.
- Die Recovery-Prüfung berücksichtigt auch die passende Sicherung bei
  Backup-Vorschau und Update-Backup-Prüfung.
- Die SQLite-Migration von Schema 9 auf 10 ergänzt `custom_order`
  transaktional und erhält Spieler, Ranglisten und Zuordnungen.
- Der Windows-Updater wartet auf das Ende der bisherigen App, prüft die
  Aktivierung des neuen Bundles und startet bei einem Fehlschlag die bisherige
  App als Fallback.

## Datensicherheit und Installation

- Vor dem Update eine vollständige Sicherung des Ordners
  `%APPDATA%\DartTournamentManager` aufbewahren. Keine App-Daten oder
  Sicherungsdateien löschen und keine ältere Sicherung über aktuelle Dateien
  kopieren.
- Das Windows-Release ist ein ZIP-Bundle und kein klassischer Installer.
  Falls eine Datenversion nicht sicher erkannt wird, bleibt die Quelldatei
  erhalten und die App zeigt eine Diagnose statt sie zurückzusetzen.
# DartTournamentPro 1.0.4

Änderungen seit `v1.0.3+3`; Buildnummer 4. Die Release Notes für GitHub
stehen in [`docs/releases/v1.0.4+4.md`](docs/releases/v1.0.4+4.md).

# Dart Turnier 0.2.3

Änderungen seit Version 0.2.2. Der Build trägt die interne Buildnummer 28
(Release-Tag `v0.2.3+28`).

## Ergebnisse & Turnieransicht

- **Neue 2/3 + 1/3 Spaltenansicht:** Spiele links (2/3) und Tabellen rechts (1/3) dauerhaft nebeneinander sichtbar – ohne horizontales Hin- und Herspringen.
- **Kategorisierte Spiele:** Schneller Wechsel zwischen „Bereits gespielt", „Offene Spiele" und „Alle Spiele". Die offenen Partien sind beim Öffnen standardmäßig aktiv und aufgeklappt.
- **Rundensystem entfernt:** Alle Begegnungen einer Etappe sind direkt auf einen Blick kompakt ersichtlich.
- **Aufgeräumte Arbeitsfläche:** Steuerungsfunktionen wie Turnieruhr pausieren, Etappen vorzeitig beenden oder Turnier abschließen wurden aus den Ergebnissen entfernt (zentral im Dashboard und in den Einstellungen verankert).
- **Dark-Mode Lesbarkeit:** Weiterkommende Plätze in den Tabellen nutzen nun ein kontrastreiches, dezentes Dunkelgrün (`#144D34`) statt greller Überstrahlungen.

## TV-Info-Tafel & 2-Monitor-Modus

- **Eigenständiges Windows-Zweitfenster:** Über „TV-Anzeige in separatem Fenster öffnen" wird ein nativer Zweitbildschirm-Prozess gestartet. Der Hauptbildschirm bleibt für die Turnierleitung frei bedienbar.
- **Hintergrund-Live-Synchronisation:** Das Zweitfenster synchronisiert sich alle 2 Sekunden automatisch mit den Turnierdaten – ganz ohne manuelles Neuladen.
- **Informativere Slides:**
  - **Slide 1 (Tabellen & Zwischenstände):** Integrierte **KO-Prognose** mit automatischer Wahrscheinlichkeitsberechnung basierend auf ELO und Siegesquoten.
  - **Slide 2 (Aktuelle & nächste Begegnungen):** Anzeige von Spielfluss-Hinweisen (priorisierte Partien) und kompakter Tabelle.
  - **Slide 3 (Zuletzt beendete Matches):** Direkte ELO-Veränderungen der Ranglisten-Matches live einsehbar.
  - **Slide 4 (Turnierfortschritt & Bestleistungen):** Prozentuale Fortschrittsbalken getrennt nach Phasen (Gespielt / Offen) sowie aktuelle Bestleistungen.

## Statistik & Spieler

- **Reiner Statistik-Bereich:** Keine störenden Steuerungsknöpfe (Turnierdetails / Etappe beenden) mehr im Statistik-Menü.
- **Einheitliche Farbpalette:** Große Hero-Kacheln in Statistik und Spielerprofilen nutzen dieselbe elegante Farbpalette wie die Spielzentrale auf dem Dashboard.
- **Jahresrückblick:** Die erste Rangliste wird nun automatisch ausgewählt, wenn mindestens eine Rangliste vorhanden ist.
- **Strukturierte Bestleistungen:** 180er, 170er-Finishes, Shortlegs (9–18 Darts) und High Finishes (100–170) werden übersichtlich gruppiert und mit Häufigkeitszählern dargestellt statt als unendliche Einzelliste.
- **Ranglisten-Tiers:** Wenn das Auf-/Abstiegssystem deaktiviert ist, werden Tier-Chips im Spielerprofil konsequent ausgeblendet.
- **Ranglisten-Änderungen am Turnierende:** Animierte Übersicht der Top-3-Gewinner, Bottom-3-Verlierer und aller Tier-Auf- und Abstiege unter dem Podium.

## Turnierformfinder & Werkzeuge

- **Spieldistanz fixieren:** Option zum Fixieren des Satz-/Leg-Formats (z. B. Best of 3 beibehalten) verhindert ungewolltes Downgrade auf Best of 1.
- **Manuelle Anzahl Weiterkommender:** Beliebige Zielgrößen für die KO-Phase (z. B. Top 6 bei 12 Teilnehmern mit Freilosen für Gruppensieger) frei konfigurierbar.
- **Präzise Zeitberechnung:** Korrektur der Runden- und Dauerberechnung bei doppelter Gruppenphase („2× Jeder gegen jeden").
- **Werkzeuge-Bereich:** Kachel „Passende Turnierform" im einheitlichen Kachel-Design (Govee/Dev-Tools) wiederhergestellt mit direkter Navigation in den Planer.

# Dart Turnier 0.2.1

Änderungen seit Version 0.2.0. Der Build trägt die interne Buildnummer 26
(Release-Tag `v0.2.1+26`).

## Turnierbetrieb – Dashboard-Umbau

- **Neue Dashboard-Ansicht:** Boards, Spiele und Statusübersicht sind direkt
  sichtbar – keine separaten Tabs mehr nötig.
- **Spielfluss-Hinweise:** Das Dashboard warnt automatisch, wenn ein Spieler
  deutlich mehr offene Partien hat als andere, damit priorisiert werden kann.
- **Fehler-Banner:** Speicherfehler werden als roter Banner oben angezeigt
  mit einem „Speichern erneut versuchen"-Button.
- **Aufgeräumte Navigation:** Menüpunkte „Boards & Spiele" und die veralteten
  Ansichten `overview`/`playOrder` wurden entfernt.

## 2-Monitor-Modus (TV-Info-Tafel)

- **Neue eigenständige `TournamentSecondScreenView`:** Turnieruhr, Tabellen,
  Gruppen-Spiele und Spielfluss-Hinweise auf einem separaten TV-Bildschirm.
- **Dynamische Slideshow:** Final-Vorschau, Gruppenübersicht und neueste
  Ergebnisse mit ELO-Auswirkung wechseln automatisch durch.
- **Vollständig responsiv:** Kein Overflow bei 200 % Schrift oder kleinen
  Displays – alle Titel und Badges sind Flex-sicher.
- In der mobilen Ansicht deaktivierbar; alle Infos bleiben im Dashboard sichtbar.

## Turnieruhr

- Die Uhr startet automatisch beim Turnierstart.
- **Pause/Resume-Button** im laufenden Betrieb direkt im Timing-Panel.
- Pausiert-Status visuell erkennbar (orange).
- Timer-Aktualisierung jede Sekunde (statt alle 15 Sekunden).
- Turnierdauer in der Turnierübersicht einsehbar für nachträgliche Auswertung
  (Dauer pro Match, Anzahl der Matches).

## Spieler-Umbenennen

- Spieler umbenennen aktualisiert jetzt korrekt alle Etappen, Gruppen und
  Matches (statt zuvor nur das Player-Objekt).

## Tabellen

- Gruppen- und Beste-N-Tabellen zeigen eine sichtbare horizontale Scrollbar.
- Kompaktere Spaltenabstände (`columnSpacing: 16`, `horizontalMargin: 12`)
  für mobile Nutzung.

## Spielreihenfolge

- Aktionsbuttons umbrechen jetzt korrekt auf kleinen Displays (Wrap statt Row).
- Die Ansicht wandert in den Bereich „Ergebnisse" (kein eigener Menüpunkt mehr).

## Betreiberkonto / Cloud-Backup

- **Registrieren-Funktion** im Anmeldedialog ergänzt (Toggle Login ↔ Registrieren).
- **Passwort vergessen:** E-Mail-Feld und Reset-Link-Versand direkt im Dialog.
- Rückmeldungen: „Konto erstellt. Bitte E-Mail-Bestätigung prüfen." /
  „Betreiberkonto verbunden."

## Backup-Export

- Ranglisten, Statistiken, Spieler und Turniere sind jetzt einzeln oder
  gesamt sicherbar und importierbar.

## Ranglisten & Jahresrückblick

- Alle Spieler in den Leaderboard-Karten sind anklickbar und öffnen das Spielerprofil.
- „Profil öffnen"-Button im Jahresrückblick entfernt (war redundant).
- Kategorien im Jahresrückblick sind visuell besser von Spielerlisten abgesetzt.
- Neuer Auswahlpunkt „Gesamter Zeitraum" zeigt Jahre statt Monate.
- Rangliste: Spieler anklickbar mit aufklappbarem Turnierverlauf
  (Turnier → ±Wertung → einzelne Spiele und deren Einfluss).

## Spielerliste

- Suchfeld in der Spielerliste ergänzt.

## Turnierübersicht

- **Sortierung einstellbar:** Turnierdatum (Standard), letzte Änderung, alphabetisch.
- Sortierung bleibt nach Ergebniseintrag erhalten (kein ungewolltes Hochrutschen).

## Turnierform-Planer

- **Neue Turnierform:** „Gruppen: Jeder gegen jeden (zweimal)"
  (`groups:double_round_robin`).
- Standard-aktivierte Modi überarbeitet: Round Robin, Doppel-RR und Limited RR
  sind aktiv; Mini-KO-Varianten wurden aus den Defaults entfernt.
- **Neue Einstellung „Gewünschte letzte Etappe":** Standard ist Einfaches KO,
  wählbar sind: Egal, Einfaches KO, Doppel-KO, Triple-KO, Kratzer, Jeder gegen jeden.
- Der Algorithmus berücksichtigt die gewünschte letzte Etappe.
- Vorschlagstitel zeigen jetzt Gruppengrößen:
  z.B. „2 Gruppen à 4 Spieler (Jeder gegen jeden)" statt „2 × Jeder gegen jeden".

## Text-Korrekturen

- „menue" → „Menü", „hinzugefuegt" → „hinzugefügt".
- „Spielerstatistik" klar von „Ranglisten-Statistik" abgegrenzt.

## Technische Qualität

- Veraltete Enum-Werte (`overview`, `playOrder`, `orderOfPlay`) aus
  `StageViewMode` entfernt.
- `SportSectionNavigation`: sicheres `firstOrNull`-Lookup (kein Bad-state-Crash).
- Unused imports und Felder entfernt.
- `flutter analyze`: 0 Fehler, 0 Warnungen.
- Alle verbindlichen Tests grün: Matrix-Simulation, Adaptive Layout,
  Responsive Pages, Director, Views Overhaul.
