# 2.0.6+31

- Gibt der Fortschrittsanzeige und den Bestleistungen im zweiten Monitor mehr
  Platz und zeigt Gruppentabellen dort kompakter nebeneinander an.
- Nutzt die Vorschau der nächsten Etappe in der rechten Monitorhälfte und
  stellt alle acht Qualifikanten auch bei drei Gruppen dar.
- Zeigt Status, Startzeit und Laufzeit der Turnieruhr linksbündig an und
  entfernt die aktuelle Uhrzeit aus dem Dashboard.
- Vergrößert das Turniernamenfeld und beschriftet KO-Folgerunden mit den
  jeweiligen Gewinnern der vorherigen Spiele.

# 2.0.5+30

- Stellt die KO-Vorschau auf lesbare Theme-Farben um und kennzeichnet offene
  Qualifikationsplätze als Qualifikanten statt als Freilose.
- Zeigt Erläuterungen zum Entfernen von Spielern direkt an den jeweiligen
  Wertungsoptionen an und ergänzt die Übernahme eines Turniernamens aus einem
  anderen gespeicherten Turnier.
- Fixiert die Endzeitprognose auf geplante Dauer ab Startzeit und zeigt die
  Turnieruhr-Überschrift wieder an.
- Ergänzt im Spielervergleich die gefilterte Direktbilanz und die einzelnen
  Begegnungen.

# 2.0.3+28

- Zeigt in der Spieler-Detailseite unter „Turnier- und Spielverlauf“ die Elo-Wertung vor und nach jedem Turnier sowie bei jedem einzelnen Spiel auf einen Blick an.
- Fügt in der Turnierübersicht direkt neben dem Turniernamen einen Button zum schnellen Öffnen der zugehörigen Rangliste hinzu.
- Korrigiert das Datum des 3. Spieltags (Vereinsheim Unzenberg 2026) auf den 21.01.2026 für eine exakte chronologische Elo-Berechnung.

# 2.0.2+27

- Renames the dashboard and second-screen match queues to "Empfohlene Partien";
  the second screen now shows up to nine matches in a bounded, scrollable area.
- Explains Elo points lost for missed tournaments and extended inactivity, and
  attributes redistributed points to the inactive player in history and graph
  tooltips.

# 2.0.1+26

- Adds a versioned read-only website data snapshot for authenticated access to
  player profiles, ranking standings, statistics, best performances and
  completed tournaments.
- Publishes the website snapshot as part of the existing account-scoped
  Supabase synchronization without changing or replacing the existing backup.
- Adds a JWT-protected GET Edge Function that uses the caller's Storage RLS
  permissions and never exposes write operations or a service-role key.
- Documents deployment and server-side consumption from the separate Astro
  website project.

# 2.0.0+25

- Removes each drawn name from the wheel and locks the draw setup after the
  first spin.
- Shows fixed group slots beside the wheel on wide screens and fills them in
  draw order, completing each group from top to bottom with no manual
  reassignment.

# 1.2.3+24

- Replaces group-creation wheel assignment with random group distribution and
  adds a standalone draw wheel with manual assignment and text/image exports.
- Stores the Govee API key on-device and adds tournament ambience controls for
  supported colors and rainbow scenes.
- Moves second-screen help into a compact help action.
- Starts the Windows updater through its persisted PowerShell restart script
  with explicit script encoding and execution policy.

# 1.2.2+23

- Recovers accepted group draw assignments from the persisted draw order even
  when the completion flag is stale, repairs the flag, and avoids reopening
  the wheel.

# 1.2.1+22

- Uses the final group's configured tie-breaker order for the completed
  tournament results and podium.
- Moves live group tie-breaker editing into its own settings panel with a
  separate apply action and save feedback.
- Restores accepted wheel assignments from their saved slot order when opening
  an untouched group stage, and persists subsequent manual group-position
  changes in that order.

# 1.2.0+21

- Persists accepted group draws as completed, applies their exact slot order to
  runtime groups, and reports stale draw data instead of reverting to default
  group assignments.
- Adds editable group tie-breakers to the running tournament settings and
  applies the selected order to the active standings and forecasts.
- Allows completed tournaments to be reopened with their results and settings
  intact, the clock paused, and the final completion action available again.
- Uses the regular surface color for the stage match-count preview.

# 1.1.8+20

- Shows only drawn players in the group assignment preview; undrawn group
  slots remain placeholders, and accepted assignments follow the wheel order.
- Adds explicit hour and minute units to actual and estimated tournament
  durations in results and the PNG export.

# 1.1.7+19

- Applies the draw-wheel order consistently when building group assignments and
  editing player positions.
- Gives direct head-to-head results priority over aggregate leg difference by
  default, migrates saved default ordering, and applies the same rule in
  advancement forecasts.
- Remembers the configured group tie-breaker order on the device and explains
  each criterion in the tournament setup.
- Labels actual tournament duration and shows the estimated range midpoint with
  its minimum and maximum in the results view and PNG export.

# 1.1.6+18

- Improves second-screen match layouts, stage progress, and recent-result cards.
- Shows ranking changes more compactly in tournament results and the PNG
  export.
- Adds first and last names to player profiles, with compact match-card names.
- Fixes random group assignments when using the draw wheel.
- Restores safe automatic sync resumption and queues sync requests that arrive
  during an active synchronization.
- Migrates player profiles to store last names and updates tournament archive
  schema to support compact player names.

# 1.1.5+17

- Refines player comparison with centered category labels and separators, and
  removes the Elo history chart from that view.
- Aligns tournament dashboard and second-screen colors with the dark blue and
  subtle gold display palette; constrains upcoming match suggestions to two
  lines and shows only as many as fit.
- Shows only actual ranking-place changes in tournament results and exports.
  The tournament PNG uses the dark blue palette, groups point gains and losses,
  and reports the expected duration range.
- Keeps random draw assignments consistent with configured group sizes.
- Improves tournament settings with a compact name/save layout and a visible
  running or paused clock time.
- Reuses and focuses an already-open Windows second-screen window, and closes
  it when the main application exits.
- Makes Elo tier names and rating boundaries configurable per ranking while
  retaining default tiers for existing rankings.
- Hides self-service registration and Google sign-in; operator accounts are
  managed manually in Supabase.
- Preserves existing tournament database schema and backup formats.

# 1.1.4+16

- Replaces the player Elo comparison graph with a side-by-side comparison
  table, and adds named ranking-position changes to tournament results.
- Adds a portrait PNG export for completed tournaments, including podium,
  Elo/ranking changes, league moves, and named highlights.
- Refines dashboard and second-screen match cards, limits the visible latest
  results to two cards with scrolling, and uses configured group sizes for
  random group assignments.
- Improves desktop update diagnostics: failed activation details and the log
  location remain visible in the Updates panel.
- Adds app auth callback redirects for registration, Google sign-in, and
  password reset. Google provider credentials, redirect allowlisting, and
  email delivery still require Supabase project configuration.
- Keeps existing tournament database and backup formats unchanged.

# Dart Tournament Manager 1.1.0+12

## Daten sicher neu aufsetzen und Synchronisierung bewusst aktivieren

- Sichert beim lokalen Zurücksetzen alle aktiven Stores und Sidecars
  bytegetreu und verifiziert die Kopien vor dem Entfernen der aktiven Dateien.
- Pausiert automatische Cloud-Synchronisierung nach einem lokalen Neustart mit
  frischem Datenstand.
- Verlangt eine ausdrückliche Bestätigung, bevor der lokale Stand den Cloud-
  Datenstand des Kontos ersetzt.
- Übernimmt den Schema-24-Kompatibilitätsbeleg nur bei exakter Übereinstimmung
  des Turnierbestands; vorhandene Belege werden nie überschrieben.
- Enthält die wiederhergestellte Feature-Parität sowie Regressionstests für
  Dashboard, Turnierablauf, Ranglisten, Statistiken, Einstellungen und
  responsive Ansichten.

# Dart Tournament Manager 1.0.8+11 preview

## Preserve schema-24 proof during account migration

- Carries a legacy v22 proof file into an account-scoped workspace when copying
  the corresponding tournament file.
- For an already existing account workspace, copies a missing proof only when
  the schema-22 document exactly matches the schema-24 data. Never overwrites
  an existing proof or applies a proof for a different dataset.
- Makes the local reset flow preserve a verified byte-for-byte snapshot and
  pause automatic cloud synchronization; uploading a replacement cloud
  snapshot requires explicit confirmation.

# Dart Tournament Manager 1.0.8+10 preview

## Startup recovery fix

- Fixes the backup-store path mapping that blocked every Windows startup in
  v1.0.8+9. The app now includes the schema-22 proof backup, SQLite database,
  and planning settings at their correct paths.
- Recovery startup errors now show the underlying exception and transaction
  directory instead of presenting every setup failure as a failed restore.

No local data files are deleted or replaced by this fix.

# Dart Tournament Manager 1.0.8+9 preview

## Feature parity and data safety

- Restores the requested dashboard, tournament/TV, statistics, ranking-history,
  tournament-results, and planning behavior with regression tests.
- Rejects unknown SQLite and settings formats without modifying their files;
  documented migrations and schema-24 recovery remain supported.
- Improves the Windows update handoff and verifies the packaged update bundle.

This preview does not merge device data. Back up each device separately before
testing; preserve storage files if an unsupported-format warning appears.

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
