# Desktop- und Mobile-Design

Stand: 30.09.2026. Die Vorgaben in `AGENTS.md` gelten fuer alle weiteren UI-Aenderungen.

## Gemeinsame Layouts

`AdaptiveContentList` begrenzt Formular- und Listenansichten auf 1120 logische Pixel, zentriert sie auf Desktop und reduziert seitliche Raender unter 600 Pixel auf maximal 16 Pixel. SafeArea und Scrollen bei eingeblendeter Tastatur sind beruecksichtigt. Brackets und andere raeumliche Arbeitsflaechen behalten ihre eigene Breitensteuerung.

`AdaptiveTileLayout` verteilt Kacheln auf ein bis drei Spalten. Die Mindestbreite richtet sich auch nach der Schriftgroesse. Kacheln haben keine feste Hoehe.

## Pruefung und Verbesserungen

| Bereich | Ergebnis |
| --- | --- |
| Hauptmenue | Mehrspaltige Bereichskacheln auf Desktop; eine Spalte auf Mobile. |
| Autoscore-Tester | Direkte Kamerademo mit Punktestand und scrollbar gehaltenem Verlauf automatisch gezählter Treffer. Menü, automatische Trefferübergabe und Zurücksetzen sowie 360x800, 800x600 und 1440x900 mit 100 und 200 Prozent Schrift sind in `test/autoscore_demo_test.dart` geprüft; die Seite ist zusätzlich in der gemeinsamen Matrix enthalten. |
| Turnierliste, Spieler, Community, Geraete, Dev Tools | Gemeinsame lesbare Inhaltsbreite und mobile Abstaende. |
| Einstellungen, Backups, Updates, Bots | Seitennavigation ab 840 Pixel; kompakte Bereichsauswahl bei kleinen Fenstern oder grosser Schrift. Eingaben bleiben beim Layoutwechsel erhalten. |
| Turniererstellung | Auswahlfelder passen sich der Breite an; lange Texte koennen umbrechen. Formularzeilen beruecksichtigen Schriftvergroesserung. Tie-Breaker-Texte bleiben innerhalb der Flaeche und haben groessere Pfeiltasten. |
| Turnierdurchfuehrung | Kompakte Ansichtsauswahl auf Mobile, beschriftete Segmente auf Desktop. Ansichts-/Etappenwechsel beginnt mit passender neuer Scrollposition. Hauptmenue-Aktion als Icon mit Tooltip. |
| Team Game | Setup, Laufansicht und animierte Zweitmonitor-Anzeige bleiben bei 360x800, 800x600 und 1440x900 mit 200 Prozent Schrift bedienbar. Buttons umbrechen, Namen und Siegermeldung skalieren ohne feste Texthoehe. `test/team_game_responsive_test.dart`. |
| Ergebnisse | Podiumskarten passen ihre Spaltenzahl an Platz und Schriftgroesse an; Spielernamen werden nicht auf zwei Zeilen abgeschnitten. |
| Scorer und Checkout | Lesbare Formularbreite, korrigierte Auswahlfelder bei grosser Schrift. Bestehende zweispaltige Matchansicht und Tastatureingabe bleiben erhalten. |
| Autoscorer | Drei Kamera-Kacheln auf Desktop, gestapelte Ansichten bei wenig Platz. Automatische Kalibrierung mit kamerabezogenen Hinweisen und erkannten Referenzpunkten; Korrekturformular scrollbar. Separate Tests für 360x800, 800x600 und 1440x900 mit 100 und 200 Prozent Schriftgröße. |
| Brackets, Tabellen, Board-Anzeige | Bestehende fachliche Darstellung beibehalten; keine globale Breitenbegrenzung fuer Brackets oder Board-Anzeige eingefuehrt. |

## Wiederholbare Pruefungen

Die gespeicherte Einstellung „Übernahme bestätigen“, die Account-Geräteauswahl und der Bestätigungsdialog werden zusätzlich in `test/remote_settings_widget_test.dart` bei 360x800, 800x600 und 1440x900 mit 100/200 Prozent Schrift geprüft. Vorschauen: `remote_settings_*.png` und `remote_confirmation_*.png` unter `build/layout_previews/`. Netzwerkfälle und Persistenz stehen in `test/remote_account_control_test.dart`.

Fernsteuerung: `test/remote_control_widget_test.dart` prüft Kopplungsformular, Host-Freigabe, Live-Bedienansicht und Texteingabe bei 360x800, 800x600 und 1440x900 mit 100/200 Prozent Schrift. Die Live-Werkzeugleiste begrenzt ihre Höhe anhand der tatsächlich verfügbaren Layout-Höhe und bleibt scrollbar. Fensterwechsel erhalten Eingaben und verwerfen veraltete Remote-Koordinaten. Details und Grenzen: `docs/remote_control.md`.

Der standardmäßige Aktionsmodus verwendet die normalen Scorer-Widgets mit eigenem Layout auf dem Handy. `test/remote_scorer_widget_test.dart` prüft Host-Anbindung, manuelle Eingaben, Autoscoring-Anzeige, Eingabesperren und Verbindungsabbruch bei 360x800, 800x600 und 1440x900 mit 100/200 Prozent Schrift. Mit `LAYOUT_PREVIEW_FONT` entstehen `build/layout_previews/remote_native_360.png` und `remote_native_1440.png`.

```powershell
flutter analyze
flutter test test/adaptive_layout_test.dart test/responsive_pages_test.dart
flutter test test/tournament_simulation_matrix_test.dart
```

Die Baustein-Tests decken 320x568, 360x800, 800x600 und 1440x900 mit 100 und 200 Prozent Schriftgroesse ab. Seitentests pruefen 360, 800 und 1440 Pixel Breite bei 800 Pixel Hoehe, scrollen durch die Inhalte und testen den Erhalt ungespeicherter Einstellungen beim Fensterwechsel. Sie verwenden einen temporaeren Speicherordner.

Fuer gerenderte Vorschauen mit einer lokal vorhandenen Schrift:

```powershell
flutter test test/responsive_pages_test.dart --dart-define=LAYOUT_PREVIEW_FONT=C:/Windows/Fonts/segoeui.ttf
```

Die PNGs liegen unter `build/layout_previews/`. Dies ist eine optionale Sichtpruefung; die normalen Tests benoetigen keine Windows-Schriftdatei. Die Vorschauen verwenden das App-Theme und Material-Icons.

Abschlusspruefung: `flutter analyze` ohne Befunde; 45 Tests aus elf betroffenen Testsuiten bestanden, einschliesslich Turniermatrix, Scorer, Geraeten, Backups, Etappenformaten, Platzierungen und Order of Play. Gerenderte Hauptmenue-, Einstellungs-, Scorer- und Ergebnisansichten wurden visuell kontrolliert.

## Grenzen der Pruefung

Community-Statistiken: Der Bereich zeigt direkt das ausführliche Cockpit mit Kennzahlenvergleich und Form. Kompakte Aktionen öffnen die Spielerauswahl, Highlights und Trends. Spielerprofile zeigen das ausführliche Cockpit; der bisherige zusätzliche Einstieg und die alte Vergleichsseite entfallen. `test/community_statistics_navigation_test.dart` prüft den neuen Standard, Navigation, Zuordnung, leere Ergebnisse und Größenwechsel bei 360x800, 800x600 und 1440x900 mit 200 Prozent Schrift. Die Ansichten sind zusätzlich in der gemeinsamen Vorschau-Matrix enthalten.

Die Pruefung ersetzt keinen Durchlauf auf einem physischen Smartphone. Betriebssystem-Tastatur, Screenreader, Touch-Gesten und authentifizierte Online-Community-/Netzwerkzustaende wurden nicht vollstaendig auf realen Geraeten geprueft. Die Seitentests decken repraesentative Ausgangszustaende ab, nicht jede Kombination aus Turnierdaten, Dialog und Netzwerkzustand. Fuer neue Ansichten oder gefundene Sonderfaelle die Testmatrix gezielt erweitern.

Persönliches Profil: `test/personal_profile_test.dart` prüft den Editor bei 360x800, 800x600 und 1440x900 mit 100 und 200 Prozent Schriftgröße sowie kontogetrennte lokale Speicherung und Spotify-Linkvalidierung. Der Anzeigename im persönlichen Profil ist unabhängig vom Konto-Anmeldenamen. Profilbilder werden als verkleinerte PNG-Daten lokal und bei angemeldeten Online-Konten in Supabase gespeichert. Details: `docs/personal_profile.md`.




Erkennungs-Overlays des Autoscorers: `test/camera_recognition_view_test.dart` ergänzt die Matrix um echte Kameraaufnahmen und abgelehnte Bull-/Ring-Vorschläge, eine optionale Farbmaske sowie sichtbare Diagnosewerte bei 360x800, 800x600 und 1440x900 mit 100/200 Prozent Schrift. Gerenderte Desktop- und Mobile-Ansichten wurden geprüft.


Dart-Setup im persönlichen Profil: optionale Komponentenfelder in einer mobilen Spalte und mehreren Desktop-Spalten. Profiltests sichern Speicherung und Bedienung bei 360x800, 800x600, 1440x900 und 200 Prozent Schriftgröße ab. `test/dart_setup_widgets_test.dart` prüft den Erhalt von Eingaben beim Fenstergrößenwechsel; mit `--dart-define=LAYOUT_PREVIEW_FONT=C:/Windows/Fonts/segoeui.ttf` entstehen PNG-Vorschauen unter `build/layout_previews/dart_setup_*.png`. Mobile und Desktop-Vorschauen wurden am 03.10.2026 visuell geprüft. Eine Prüfung auf physischen Geräten steht noch aus.

Statistik-Cockpit: Spielerübersicht, Community-Vergleich und Kennzahlen-Detailseiten sind in der gemeinsamen Seitenmatrix enthalten. Zusätzlich prüft `test/statistics_analytics_widget_test.dart` sämtliche 40 Detailseiten mit Messwerten und ohne Daten bei großer Schrift. Mit der bisherigen `LAYOUT_PREVIEW_FONT`-Option werden Vorschauen des Cockpits, Community-Vergleichs und einer Detailseite erzeugt. Mobile und Desktop-Vorschauen wurden am 03.10.2026 visuell geprüft. Details zur Berechnung und Datenbasis stehen in `docs/statistics_analytics.md`.

Personalisierte Checkoutwege: `test/preferred_checkouts_widget_test.dart` prüft das Lieblingsdoppel und den Wechsel zur Standardanzeige beim Gegner bei 360x800, 800x600 und 1440x900 mit 200 Prozent Schrift. Die optionalen Vorschauen `preferred_checkout_360.png` und `preferred_checkout_1440.png` wurden visuell auf Umbruch und vollständige Wege geprüft. Keine Prüfung auf physischen Geräten.

Cockpit-Heatmap: `test/cockpit_heatmap_test.dart` prüft Zuordnung über Spiel-ID/Spielerposition, Zeitraum, Checkout-/Schätzfilter, Detailnavigation und Größenwechsel bei 360x800, 800x600 und 1440x900 mit 100/200 Prozent Schrift. Über `LAYOUT_PREVIEW_FONT` entstehen `cockpit_heatmap_<Breite>_<Skalierung>.png`. Mobile und Desktop wurden am 04.10.2026 visuell geprüft; physische Geräte wurden nicht geprüft. Die allgemeinen Cockpit-/Community-/Responsive-Tests bleiben zusätzlich verbindlich.

## Sportliches App-Design (04.10.2026)

Das gemeinsame Theme in `lib/app/app_theme.dart` definiert Petrol-/Gruenfarben, helle Inhaltsflaechen, Typografie sowie Karten, Eingaben, Aktionen, Dialoge und Tabellen fuer alle Features. Fachliche Farben von Dartboards, Heatmaps und Qualifikationsanzeigen bleiben erhalten.

`SportAppShell` ist eine eigenstaendige Library unter `lib/app/navigation/`. Die Hauptbereiche werden vom Dashboard mit gemeinsamer Bereichsnavigation geoeffnet. Ab 1100 Pixel und geeigneter Textgroesse erscheint die Seitenleiste; sonst liegt das Bereichsmenue oberhalb des Inhalts. Die Elementposition der Inhaltsseite bleibt beim Layoutwechsel gleich, damit Formulare ihren Zustand behalten. Unterseiten und Match-Arbeitsflaechen verwenden weiterhin ihre vorhandene Zuruecknavigation und das gemeinsame Theme.

Die Startseite zeigt direkte Aktionen fuer Turniererstellung und Scorer, vier Bereichskarten sowie Konto und aufklappbare Verwaltungswerkzeuge. Sportliche Bereichsueberschriften fuer Turniere, Spieler und Scorer liegen in `lib/shared/widgets/sport_page_heading.dart`; Dashboard-Bausteine in `lib/features/home/presentation/widgets/sport_dashboard.dart`.

Pruefungen: `flutter analyze` ohne Befunde. Gemeinsame adaptive und responsive Regressionen bei 100/200 Prozent Schrift bestanden; `test/sport_navigation_test.dart` prueft Navigation und Eingabeerhalt bei Fensterwechsel fuer 360x800, 800x600 und 1440x900. Turniermatrix mit 32 Szenarien und Scorer-Widgettests bestanden. Der Scorer-Test scrollt jetzt vor dem Bot-Einstieg zur Aktion und wartet auf die Scrollbewegung.

Gerenderte Desktop- und Mobile-Vorschauen der Startseite sowie Turnier- und Scoreransichten wurden visuell kontrolliert. Keine Pruefung auf einem physischen Smartphone; authentifizierte Netzwerkzustaende sind durch diese Designpruefung nicht vollstaendig abgedeckt.

## Aufgeraeumte Bereichsmenues (04.10.2026)

Die Bereichsmenues nutzen `lib/shared/widgets/sport_menu.dart`: kurze beschriftete Eintraege auf einer gemeinsamen Flaeche pro Aufgabengruppe, dezente Trennlinien und konsistente Icons. Die gesamte Zeile ist bedienbar. Verwaltung und Kamera-Werkzeuge sind aufklappbar; ihr Zustand bleibt beim Fenstergroessenwechsel erhalten. Zusatzaktionen liegen in beschrifteten Popup-Menues, deaktivierte Aktionen bleiben deaktiviert.

Umgestellte Einstiege: Spielzentrale, Scorer (Spielen / Training & Analyse / Kamera & Erkennung), Community (Spieltag / Team & Leistung / Community verwalten), Turniererstellung und Kopplungsaktionen. Doppelte Geraete-/Einstellungslinks im Dashboard-Werkzeugkasten sind entfernt. Die Startseiten-Kopfflaeche ist kuerzer. Bereits ausgewaehlte Hauptbereiche erzeugen beim erneuten Anklicken keine weitere Route.

`lib/shared/widgets/sport_section_navigation.dart` vereinheitlicht die Bereichsauswahl fuer Einstellungen und Turnieransichten. Auf Desktop erscheinen beschriftete Auswahlchips, bei wenig Platz oder grosser Schrift eine Auswahlliste. Die Einstellungen haben keine zusaetzliche Seitenleiste mehr. Die Turnieretappen nutzen auf kleinen Displays ebenfalls eine Auswahlliste statt horizontalem Navigationsscrollen. Im Turniermenue liegen Highlights, Board-Zuordnung und Rueckkehr zum Hauptmenue; die feste Kopfzeile enthaelt keinen separaten Highlight-Button mehr.

Die gemeinsamen Popup- und Aufklappmenue-Styles gelten auch fuer bestehende Kontextmenues. Turnierregeln, Account-Berechtigungen und Persistenz sind unveraendert.

Validierung: 62 Tests aus 13 Suites bestanden, einschliesslich kompletter Community-Menue-Zugaenge, Erhalt aufgeklappter Menues beim Groessenwechsel, deaktivierter Zusatzaktionen, Turniererstellung, Scorer-/Wizard-Navigation, Geraeteseite, Order of Play, adaptiver Seitenmatrix und Turniermatrix. `flutter analyze` ohne Befunde. Vorschauen fuer Startseite, Scorer, Einstellungen und Community-Menue wurden auf Desktop und Mobile visuell kontrolliert. Physische Smartphones und authentifizierte Online-Zustaende wurden nicht vollstaendig geprueft.

## Weitere Menues vereinheitlicht (04.10.2026)

Kontoaktionen, persoenliche Profilverwaltung, Profil-Scorer-Einstieg, Community-Auswertungen, Ranglistenauswahl, Ergebniseinstiege, Backup-Aktionen sowie Push-Sender und Push-Empfang nutzen nun die gemeinsamen SportMenuGroup-Eintraege. Statusinformationen und Berechtigungen bleiben erhalten; beim Anmelden bleibt insbesondere der Hinweis auf Online-Konto oder lokalen Gastmodus sichtbar.

Das Statistik-Cockpit nutzt SportSectionNavigation fuer Scorer-/Turnierergebnisse und Einzel-/Doppelauswahl. Kleine Displays erhalten kompakte Auswahllisten; breite Fenster beschriftete Auswahlchips. Zeitraumfilter bleiben direkt bedienbare Filter, keine weitere Navigationsebene.

SportMenuLabel vereinheitlicht Kontextmenues mit Icons und umbrechenden Beschriftungen fuer Spieler, Team-Zusammenstellung, Community-Mitglieder, Ranglistenaktionen, Turnieraktionen, Highlight-Verwaltung und Order of Play. Vorhandene PopupMenuButton-Typen, Werte, Berechtigungspruefungen und Bestaetigungsdialoge sind erhalten. Deaktivierte Eintraege in SportMenuGroup sind auch visuell deaktiviert.

Validierung: 106 Tests aus 19 Suites bestanden, einschliesslich gemeinsamer Responsive-Matrix, Profil, Statistik, Backup, Push, Ranglisten, Highlights, Teams, Ergebnisse, Order of Play und Turniermatrix. Registrierung und Abmeldung im umgestalteten Kontomenue separat bestanden. Ein aelterer Scorer-Test wurde auf Scrollen zur Rueckgaengig-Aktion und den bereits vorhandenen Zwischenspeichern-Dialog angepasst; SharedPreferences sind im Test isoliert. Keine Aenderung der Scorer-Fachlogik.

flutter analyze ohne Befunde. Gerenderte Desktop-/Mobile-Ansichten von Profil, Ergebnissen und Community-Auswertungen wurden kontrolliert. Physische Smartphones, Linux-Benachrichtigungsdienst und authentifizierte Online-Zustaende wurden nicht auf echten Geraeten geprueft.


## Turnierbetrieb und Scorer auf Mobile (05.10.2026)

Der X01-Scorer zeigt Restpunkte in eigenen Sport-Panels mit hervorgehobenem aktiven Spieler. Auf schmalen Displays nutzt die Punkteingabe drei breite Ziffernspalten; Schnellwerte bleiben separat erreichbar. Bei grosser Schrift wachsen die Elemente und Spieler-Panels wechseln auf eine Spalte. Statistik und Kamera bleiben direkt in der Kopfzeile erreichbar; doppelte Aktionen oberhalb der Tastatur wurden entfernt. Checkout-Hinweise erscheinen im Finish-Bereich. Die Keypad-Instanz und bereits eingegebene Ziffern bleiben beim Wechsel zwischen Mobile und Desktop erhalten.

Die Turnierliste nutzt responsive Status-Karten mit eigenem Aktionsmenue. Kopfbereich, Etappenauswahl, Spiele und Abschlussaktionen im Turnierbetrieb liegen in einer gemeinsamen scrollbaren Flaeche. Mobile Match-Karten trennen Spielernamen und Ergebnisaktionen. Scorer-Einstellungen haben einen eigenen Formularabschnitt. Keine Aenderung an Turnierregeln oder Speicherschema.

Validierung: flutter analyze ohne Befunde; 65 Tests aus 14 Suites einschliesslich Turniermatrix, Scorer-Abschluss/Rueckgaengig, Bots, Doppel, Kamera und Fernsteuerung bestanden. Nach abschliessender Layout-Anpassung 19 Responsive-/Scorer-Tests erneut bestanden. Die Seitenmatrix enthaelt nun die echte TournamentRunPage und prueft auch aufgeklappte Spiele und Scrollen zu Abschlussaktionen. Groessen: 360x800, 800x600, 1440x900 bei 100 und 200 Prozent Schrift; Eingabe-Zustand und Touch-Ziele zusaetzlich bei 320x568 und Fensterwechsel geprueft. Gerenderte Scorer-/Turnieransichten auf Desktop und Mobile visuell kontrolliert. Physische Smartphones und echte Kamera-/Netzwerk-Verbindungen wurden in dieser Designpruefung nicht getestet.


## Mobile Gruppenuebersicht vereinfacht (05.10.2026)

Auf schmalen Gruppenflaechen stehen offene Spiele direkt sichtbar vor der Tabelle. Tabellen/Qualifikation und abgeschlossene Spiele sind getrennte aufklappbare Bereiche. Bei mehreren Gruppen zeigt die mobile Etappenuebersicht eine Gruppenauswahl und nur die ausgewaehlte Gruppe; breite Fenster behalten die Gesamtuebersicht. Gruppenverwaltung ist eingeklappt, eine Etappenauswahl fuer nur eine Etappe entfaellt. Die bestehende Ergebnisbearbeitung und Berechnung bleiben erhalten.

Validierung: flutter analyze ohne Befunde; 18 Tests aus Responsive-, Order-of-Play- und Turniermatrix-Suites sowie ein neuer Gruppen-Test bestanden. Der Gruppen-Test prueft Auswahl-Erhalt bei Mobile/Desktop-Wechsel und aufklappbare abgeschlossene Ergebnisse. Seiten bei 360x800, 800x600 und 1440x900 mit 100/200 Prozent Schrift geprueft. Gerenderte mobile und Desktop-Turnieransichten visuell kontrolliert; keine Sichtpruefung auf physischen Smartphones.


## Expertenmodus strukturieren (07.10.2026)

Die freie Turniererstellung nutzt drei nummerierte, aufklappbare Bereiche: Name/Teilnehmer, Turnierablauf und Pruefen/Anlegen. Der erste Bereich ist anfangs offen. Kurzinfos zeigen Teilnehmerzahl, gespeicherte Etappen und Boards auch im geschlossenen Zustand. Spielregeln, individuelle Gruppenoptionen, detaillierte Qualifikation und Gleichstandskriterien oeffnen sich nur bei Bedarf. Eine beschriftete Etappenaktion ergaenzt den bisherigen Icon-Zugang. Felder und vorhandene Berechnungen/Callbacks bleiben erhalten; kein neues Persistenzschema.

ExpertSetupSection ist eine eigene Widget-Library. Untergeordnete Scrollflaechen haben einen separaten PageStorage-Bereich, damit ihre Scrollposition nicht mit dem booleschen Aufklappzustand kollidiert.

Validierung: 23 Tests aus Creation-Entry-, Adaptive-, Responsive- und Turniermatrix-Suites bestanden; sechs Creation-Entry-Faelle nach Verwendung des App-Themes erneut bestanden. Groessen 360x800, 800x600 und 1440x900 bei 100/200 Prozent Schrift; Gruppenzahl bleibt nach Zuklappen/Aufklappen erhalten, Geraetevorbereitung erreichbar. Gerenderte Mobile- und Desktop-Vorschauen unter build/layout_previews/ExpertCreation_* visuell kontrolliert. Keine Pruefung auf physischen Smartphones. flutter analyze meldet zuletzt einen bestehenden Stilhinweis in test/manual_update_card_test.dart:35, keine Befunde in der geaenderten Turniererstellung.


## Scorer-Partie als Wizard (07.10.2026)

Die Partieerstellung hat drei Schritte: Teilnehmer, Spielregeln und Pruefen/Starten. ScorerSetupWizard ist eine eigene Widget-Library mit begrenzter Desktop-Breite, scrollbar angeordneten Inhalten, Fortschrittsanzeige und umbrechenden Aktionen. Schrittwechsel setzen die Scrollposition zurueck. Textcontroller und Teilnehmerentwurf bleiben im Seiten-State; Zurueck per Button, Kopfzeile oder Systemnavigation und Rotation behalten Eingaben. Online-Einladungen, individuelle Startpunkte sowie In-Regel/Set-Spiel sind optionale Aufklappbereiche. Anwurf-Auswahl und Zusammenfassung zeigen Spielernamen. Ungueltige Eingaben und doppelte Spieler blockieren das Weitergehen; die bestehende vollstaendige Startvalidierung bleibt erhalten.

Validierung: 52 Tests aus Wizard-, Scorer-, Theo-, Doppel-, Fernsteuerungs- und Responsive-Suites bestanden. Nach finaler Text-/Validierungsanpassung weitere 30 Tests aus Wizard, Audio und Turniermatrix bestanden. Die neue Wizard-Matrix prueft alle Schritte bei 360x800, 800x600, 1440x900 und 100/200 Prozent Schrift, inklusive Rotation, Zurueck, ungueltigen Startpunkten sowie Erhalt von Namen/Punkten. Ein Remote-Start-Test prueft individuelle Punkte, Double In und Best-of-Sets im uebergebenen ScorerSettings. Gerenderte Schritte unter build/layout_previews/ScorerWizard_* auf Mobile/Desktop visuell kontrolliert; keine physischen Smartphones getestet.

Die Responsive-Matrix nutzt injizierbare stille Audioausgaben fuer Autoscorer-, Erkennungs-, Demo- und Scorer-Ansichten. So benoetigt der reine Layout-Test keine nativen Audio-Plugins; die Standardausgabe im Produkt bleibt erhalten. Die Einladungs-Aufklappflaeche hat einen getrennten PageStorage-Bereich fuer untergeordnete Scroll-/Auswahltexte. flutter analyze meldet zuletzt drei Stilhinweise ausserhalb dieser Aenderung: scorer_heatmap_repository.dart:56/120 und test/manual_update_card_test.dart:35.


## App-weite Menüprüfung (7. Oktober 2026)

Die Presentation-Bereiche wurden auf lange Formulare, viele gleichzeitige Aktionen,
fehlende mobile Gruppierung und auf bereits vorhandene kompakte Navigation untersucht:
Home, Turniere/Planung/Ergebnisse, Scorer/Lobby/Bots/Monitor, Autoscorer/Kamera,
Spieler/Profil/Statistik, Communities/Ranglisten/Rollen, Kalender/Highlights,
Geräte/Fernsteuerung, Einstellungen/Backups/Updates, Push und Entwicklungstester.
Bestehende Sport-Menüs, Bereichsnavigation, fachlich notwendige Tabellen und
Kamera-Arbeitsflächen bleiben erhalten. Neue Gruppen betreffen folgende Ansichten:

- Bots: Stärke bleibt direkt erreichbar; Streuung sowie Anzeige/Kamera sind optional.
- Planung: Turnieraufbau offen; Leg-Dauern, Bewertung und Erklärung kompakt.
  Geöffnete Parameter nutzen auf Desktop mehrere Spalten.
- Profil: Name/Nationalität direkt; Walk-on/Favoriten und Dart-Komponenten optional.
- Autoscorer: Kamera-Einstieg vor Statistik; Prüfung und Erfassungsvorgaben gefaltet.
- Liga: getrennte Heim-/Gastaufstellungen mit Zusammenfassung, Geräte optional.
- Kalender: optionale Ortsangaben, separates Spielformat; Terminverwaltung im
  beschrifteten Aktionsmenü, Erinnerung und Turnierstart direkt erreichbar.
- Rollen: Rechte nach Turnier, Community und weiteren Bereichen gruppiert;
  bestehende Rollen zeigen eine kompakte Rechte-Zusammenfassung.
- Highlights: Leistung/Datum direkt; Zuordnung/Notiz optional.
- Push: durchsuchbare Empfängerauswahl; Auswahl bleibt beim Filtern erhalten.
- Fernsteuerung: Verbindung zuerst; Verbindungsmodus separat.

`SportSettingsSection` ist eine echte Shared-Widget-Library mit natürlichen Höhen,
`maintainState`, KeepAlive und eigenem PageStorage für den Inhalt. Dadurch bleiben
Eingaben und Öffnungszustand beim Scrollen/Resize erhalten und Scroll-Offsets
kollidieren nicht mit Expansion-Zuständen. Formulare öffnen bei ungültigen Angaben
betroffene Optionsbereiche; Fachregeln und Speicherformate bleiben unverändert.

Prüfung: `test/menu_declutter_test.dart` ergänzt die vorhandene responsive Matrix
um kompakte und geöffnete Menüs auf 360×800, 800×600 und 1440×900, jeweils mit
100/200 % Text. Dazu Scroll-/Resize-Erhalt und bestehende Speicher-/Berechtigungs-
und Workflow-Tests. Optionale Render-Vorschauen liegen unter
`build/layout_previews/menu_<Bereich>_<Breite>.png` (Font-Define wie oben).
Desktop-/Mobil-Renderings geprüft; keine Prüfung auf physischen Geräten.


## Turniere: mobile Runde im Vordergrund (7. Oktober 2026)

Turnierkarten zeigen Name, Umfang und Status kompakter. In der Turnierleitung
stehen Ansicht/Etappe und Partien zuerst; Uhr, Regeln und Elo liegen in
„Turnierdetails“ unter dem Spielbereich. Gruppenverwaltung folgt den Partien.
Mobile Gruppenspiele, K.-o., Mini-K.-o. und Spielansicht verwenden eine gemeinsame
`RoundMatchList`: eine ausgewählte Runde, zuerst eine spielbereite offene Runde,
mit weiterhin erreichbaren späteren Runden und Ergebnissen. Gruppen-Spieltabelle
und abgeschlossene Spiele bleiben separat erreichbar. K.-o.-Bäume und Setzung
sind auf Mobile optional aufklappbar, auf breiten Ansichten direkt sichtbar.
Die Rundenauswahl wird im PageStorage isoliert gespeichert und über Resize
wiederhergestellt. Ergebniszeilen verzichten auf zusätzliche Boxen um jeden Namen.
Order of Play gruppiert fertige/wartende Matches und Erklärung separat.

`test/tournament_mobile_focus_test.dart` prüft die echte Turnierseite mit mehreren
Runden, Wechsel zur Spielansicht, Resize-Erhalt, mobile K.-o.-Ergebniseingabe,
optionale Bäume und Mini-K.-o. Zusammen mit den gemeinsamen Layouttests werden
360×800, 800×600, 1440×900 und 200 % Text abgedeckt. Renderings unter
`build/layout_previews/tournament_focus_<Breite>_<Skalierung>.png` wurden auf
Desktop und Mobile visuell geprüft. Physische Geräte wurden nicht geprüft.


### Turnieransichten und Form-Finder (08.10.2026)

Spielansicht: offene Spiele und Ergebnisse getrennt, eine gewählte Runde mit adaptiven Match-Spalten. Order of Play: laufende Boards und nächster Block im Fokus; weitere Blöcke, Ergebnisse und Hinweise aufklappbar. Live-Statistik: Kennzahlen, Spieler-/Highlights-Auswahl, Suche, Sortierung und aufklappbare Spielerdetails. Der Form-Finder stellt Teilnehmer, Boards und Dauer vor die optionalen Bereiche Turnierformen, Aufbau/Gruppen und Spielregeln; Berechnen bleibt im Dialog-Fuß erreichbar. Eingaben und Auswahl bleiben beim Auf-/Zuklappen erhalten. Fehlerhafte Gruppengrenzen öffnen den zuständigen Bereich.

`test/tournament_views_overhaul_test.dart` prüft alle vier Ansichten bei 360x800, 800x600 und 1440x900 mit 100/200 Prozent Schrift. Ergebnisfilter, weitere Spielblöcke, Erhalt der Statistik-Suche und der Form-Auswahl werden interaktiv geprüft. Optional entstehen mit `LAYOUT_PREVIEW_FONT` die Bilder `build/layout_previews/views_<Bereich>_<Breite>_<Skalierung>.png`. Mobile-/Desktop-Vorschauen visuell geprüft; keine physischen Geräte geprüft. Responsive-, Order-of-Play-, Live-Statistik-, Gruppenpflicht- und Turniermatrix-Tests ergänzen die Prüfung.


### Turnierleitungsübersicht (08.10.2026)

Laufende klassische Turniere öffnen standardmäßig „Turnierleitung“. Bestehende
Bracket-, Spielplan- und Statistikansichten bleiben über die Turniernavigation
erreichbar; Liga- und importierte Archivansichten behalten ihre eigenen Abläufe.
Die Übersicht nutzt die aktive Etappe unabhängig von der zuletzt betrachteten
Bracket-Etappe. Bekannte offene/erledigte Paarungen, Laufzeit und geschätztes Ende,
Boards mit Gerätenamen und Übertragungsstatus sowie nächste Spiele und Spielersuche
verwenden die bestehende Order-of-Play- und Timing-Logik. Zukünftige Qualifikanten
werden nicht vorhergesagt. Die Suche berücksichtigt auch Teammitglieder.

Ab 1000 Pixel Inhaltsbreite stehen Boards und nächste Spiele nebeneinander;
schmalere Fenster und große Schrift nutzen „Übersicht“, „Boards“ und „Spiele“.
Suche und Bereichsauswahl bleiben beim Größenwechsel erhalten. Timer aktualisieren
Spieldauern alle 15 Sekunden; Gerätestatus folgt dem bestehenden Dispatcher.
Speicherfehler bieten Wiederholen; der Community-Uploadstatus ist ausdrücklich
appweit gekennzeichnet. Ohne zugeteiltes Gerät bleibt manuelle Eingabe möglich.

Boardsperren werden in Speicherversion 18 als optionales `blockedBoards` gespeichert.
Altdaten erhalten eine leere Menge; die vorhandene Migration sichert das vorherige
Dokument. Spielplanung, manuelle Starts und Spielervorschläge beachten die Sperren,
auch wenn alle Boards gesperrt sind. Laufende Boards lassen sich nicht sperren.
Community-Boardsperren benötigen wie andere Turnierkonfiguration das bestehende
Recht „Turniere bearbeiten“; die lokale und serverseitige Prüfung bleibt erhalten.
Bei fehlgeschlagener Speicherung wird die Sperränderung zurückgenommen.

`test/tournament_director_test.dart` prüft Planung, Neustart/Migration, Suche,
Ergebniseingabe, Spielstart, Freigabe, Fehler/Wiederholen und alle drei Bereiche
bei 360x800, 800x600 und 1440x900 mit 100/200 Prozent Schrift. `DirectorPreview`
ist zusätzlich Teil der gemeinsamen responsiven Matrix. Renderings unter
`build/layout_previews/Director_*` wurden auf Desktop und Mobile geprüft.
Turniermatrix-, Order-of-Play-, Geräte- und Speicherregressionen bestehen.
Echte verbundene Geräte und physische Smartphone-/Steam-Deck-Tests stehen aus.

### Order of Play: sichtbare Reihenfolge (08.10.2026)

Die geplanten Partien sind jetzt durchgehend in nummerierten Spielblöcken sichtbar. Der erste offene Block ist als „Als Nächstes“ hervorgehoben; weitere Blöcke folgen vertikal mit „Danach“. Parallel geplante Partien bleiben innerhalb eines gemeinsamen Blocks. Spätere Partien haben die beschriftete Aktion „Vorziehen“. Kompakte Match-Zeilen auf breiten Displays und umgebrochene Paarungen auf Mobile ersetzen die ungeordnete Kartenübersicht. Kennzahlen stehen in einer kurzen Statuszeile. Die Reihenfolge und Board-Zuordnungen stammen weiterhin unverändert aus dem BoardSchedulingEngine.

`test/order_of_play_widget_test.dart` prüft zusätzlich die Übereinstimmung aller sichtbaren Paarungen mit der Engine, parallele Spiele auf zwei Boards und die aktualisierte nächste Gruppe nach dem Start beider Boards sowie beim Größenwechsel. Die sechs Größen-/Schriftkombinationen in `test/tournament_views_overhaul_test.dart` prüfen die jederzeit sichtbaren folgenden Blöcke. Mobile und Desktop gerendert und visuell geprüft; physische Geräte nicht geprüft.

Eigene Community-Spiele: `test/community_profile_reports_test.dart` prüft Herkunft, Aliaszuordnung, eigene Teilnehmer, doppelte Snapshots sowie Community-Auswahl und Größenwechsel bei 360x800, 800x600 und 1440x900 mit 200 Prozent Schrift. PNG-Vorschauen sind mit `LAYOUT_PREVIEW_FONT` unter `build/layout_previews/community_profile_filter_<Breite>.png` verfügbar. Authentifizierte Live-Community-Abfragen und physische Geräte sind durch diese Fixturetests nicht geprüft.

### Swiss (08.10.2026)

Swiss-Rundenzahl, Hinweise zur Rundensperre und Tabelle mit Buchholz werden in test/swiss_widget_test.dart bei 360x800, 800x600 und 1440x900 mit 100/200 Prozent Schrift geprüft. Mobile-/Desktop-Renderings unter build/layout_previews/swiss_*.png wurden visuell geprüft. Keine Prüfung auf physischen Geräten.



### Scorer: Desktop-Höhe nutzen (08.10.2026)

Die Spielansicht wertet Breite und Höhe gemeinsam aus. Bei breiten, ausreichend hohen Fenstern wachsen die Spielstand-Panels und die Eingabetasten mit der verfügbaren Höhe; die Schreibertafel bleibt direkt sichtbar. Kleine Fenster, Querformat und große Schrift verwenden weiterhin natürliche, scrollbar bleibende Inhalte. `ScorerPlaySizing` übermittelt ausschließlich Layout-Maße an Scoreboard und Keypad. Stabile Subtree-Keys erhalten angefangene Zifferneingaben und den Leg-Verlauf beim Wechsel zwischen Desktop und Mobile.

`test/scorer_play_space_test.dart` prüft 360x800, 800x600, 1440x900 und die gemeldete Screenshot-Größe 2537x1301 jeweils bei 100/200 Prozent Schrift. Es prüft die tatsächlichen Panel-/Tastenhöhen, die sichtbare Schreibertafel und Eingabeerhalt beim Größenwechsel. Gerenderte Vorschauen `build/layout_previews/scorer_space_<Breite>_<Skalierung>.png` auf Mobile und Desktop visuell kontrolliert. Keine Prüfung auf physischen Geräten.

### Spielstatistik abgeschlossener Partien (08.10.2026)

Antippen abgeschlossener Ergebniszeilen, Order-of-Play-Karten oder KO-Matches öffnet eine lesende Spielstatistik. Stift-Aktionen bearbeiten weiterhin Ergebnisse. Adaptive Kennzahlenkarten bei 360x800, 800x600 und 1440x900 mit 100/200 Prozent Schrift getestet; Handy und Desktop gerendert und visuell geprüft, keine physischen Geräte. Tests: test/tournament_match_statistics_test.dart; Renderings: build/layout_previews/match_statistics_*.png.



### Mini-Triple-KO: Rotation absichern (08.10.2026)

Der Mini-Gruppenbaum bleibt beim Wechsel zwischen kompakter und breiter Ansicht im selben Stateful-Subtree. Horizontale und vertikale Scrollpositionen haben getrennte PageStorage-Schlüssel. Die Gruppenbaum-Ausklappwahl bleibt beim Zurückdrehen erhalten. Die Bracket-Spalten und Karten wachsen mit der Textskalierung, statt bei großer Schrift aus ihren festen Match-Flächen überzulaufen.

Zwei produktive Mini-Triple-KO-Regressionen in `test/tournament_mobile_focus_test.dart` öffnen den echten Gruppenbaum, scrollen darin und drehen mehrfach zwischen 360x800, 900x400, 800x600 und 1440x900 bei 100/200 Prozent Schrift. Sie prüfen Fehlerfreiheit, Erhalt des Scroll-State und unveränderte Teilnehmer. Optional entstehen `build/layout_previews/mini_triple_rotation_<Skalierung>.png`. Der konkrete graue Fehlerbereich aus dem Android-Screenshot konnte ohne Geräte-Log nicht eindeutig zugeordnet werden; die Rotation und der reproduzierte Text-Überlauf sind abgesichert. Keine Prüfung auf dem betroffenen physischen Handy.

### Challonge: native Turnierprüfung (08.10.2026)

ChallongeNativeComparisonPreview ergänzt die gemeinsame Seitenmatrix. test/challonge_native_import_test.dart prüft native Ergebnisnavigation und Vergleich bei 360x800, 800x600 und 1440x900 mit 200 Prozent Schrift. Die Matrix kann mit --dart-define=LAYOUT_PAGE=Challonge auf diese Seiten begrenzt werden; --dart-define=LAYOUT_TRACE=true nennt jede geprüfte Seite. Gefilterte Matrix und adaptive Layouttests bestehen; Mobile-/Desktop-Vorschauen wurden geprüft. Die ungefilterte Matrix bleibt derzeit bei TournamentImportPreview vor den Challonge-Seiten stehen. Keine Prüfung auf physischen Geräten.


### Mobile Scorer: Punkte und vollständige Eingabe (08.10.2026)

Die kompakte Handy-Ansicht zeigt nur Format, Spieler/Punkte und Leg-/Set-Stand über dem vollständigen Rechner. Doppelte „Am Wurf“-Hinweise, Average, Heatmap-Ziel, Eingabeerklärung und Speicherhinweise entfallen in diesem Bereich. Verlauf, Heatmap-Wurfziel, Statistik und Monitor-Modus bleiben über „Partie-Details“ in der Kopfzeile erreichbar. Mobile verwendet vier Tastenreihen mit Bestätigen in der untersten Reihe; Schnellpunkte und Überworfen stehen im Eingabemenü. Bei ausreichend Platz bleiben die Punkte oben und die Eingabe unten; bei großer Schrift oder sehr geringer Höhe bleiben natürliche Inhalte scrollbar. Autoscoring blendet den Rechner weiterhin aus.

`test/mobile_scorer_layout_test.dart` prüft ohne Scrollen beide Spieler und alle Rechnertasten bei 320x568, 360x800 und 412x892 mit den Namen ProfGans/Yannick sowie Schnellpunkte und Erhalt angefangener Eingaben beim Drehen. Vorschauen `build/layout_previews/scorer_phone_complete_<Breite>.png` auf dem Handy-Layout visuell geprüft. Die allgemeine Scorer-/Responsive-Matrix sichert 200 Prozent Schrift und Desktop ab. Keine Prüfung auf einem physischen Handy.

### Scorer-Schnellpunkte und Checkout (08.10.2026)

Die mobile Eingabe folgt direkt auf die Punktekarten. Sechs Schnellpunkte (26, 41, 60, 81, 100, 140) stehen im Tastenfeld, daneben bleiben 180/OK und Check sichtbar. Check ist oberhalb von 180 Rest deaktiviert. Checkout-Wege werden bei bis zu 180 Rest kompakt zwischen Punkten und Eingabe angezeigt. Bei großer Schrift wechselt die Eingabe auf drei Spalten und zusätzliche Schnellpunkt-Reihen; geringe Höhe bleibt scrollbar.

Gezielte Tests prüfen alle Schnellpunkte ohne Scrollen bei 320x568, 360x800 und 412x892 sowie Checkout bei 170 Rest und den Erhalt der Eingabe bei Rotation. Gerenderte Handy- und Desktop-Vorschauen wurden kontrolliert. Kein physisches Handy verfügbar. Die allgemeine responsive_pages-Prüfung hängt beim ersten Testfall und wurde abgebrochen.
