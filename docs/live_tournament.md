# Live-Turnier (URL-Ansicht)

## Ziel

Ein laufendes Turnier kann über eine stabile HTTPS-URL und einen QR-Code für
Zuschauer freigeschaltet werden. Die Ansicht ist bewusst schlank, enthält
ausschließlich Turnierinformationen und verwendet anonymisierte Namen.

## Freigabe

- Schalter in den Turniereinstellungen unter **Zeit und Uhr Einstellungen**:
  **„Turnier Live sichtbar machen?“**
- Ohne aktiven Schalter wird nichts veröffentlicht und keine URL angezeigt.
- Die URL enthält einen festen Kanal, nicht die Turnier-ID. Der QR-Code bleibt
  daher über mehrere Turniere hinweg gültig.
- Stabile Zuschauer-URL:
  `https://rbcsrqisbuutnnxpmcvp.supabase.co/storage/v1/object/public/live-tournament/verein-live/index.html?channel=verein-live`
- Druckbarer QR-Code: `docs/live_tournament_qr.png` (828 × 828 px, hohe
  Fehlerkorrektur). Erzeugbar mit `dart run tool/generate_live_qr.dart`.

## Namensregel

- Veröffentlicht wird immer **Vorname + Nachnameinitial**, z. B. `Lena M.`.
- Vollständige Nachnamen und Spitznamen erscheinen nie.
- Die Regel gilt für Teilnehmerlisten, Tabellen, Brackets, Bestleistungen und
  alle Ergebnislisten gleichermaßen.

## Erlaubte Inhalte

- Tabellen & Zwischenstände
- KO-Baum
- Spielernamen mit abgekürztem Nachnameninitial
- Standings
- Bestleistungen
- Laufende Partien
- Offene und abgeschlossene Begegnungen
- Kurze Formatbeschreibung, z. B. `501 Double Out Best of 3 Legs`,
  `Gruppen`, `Top 8 weiter`, `Single KO Finale 501 Best of 3 Legs`,
  `Spiel um Platz 3`, Tie-Breaker
- Uhr mit Start und voraussichtlichem Ende
- Statischer End-Screen mit Ergebnisübersicht

## Ausgeschlossene Inhalte

- Insights
- Elo / Rangliste
- Achievements
- Board-Zuweisungen
- Interne Turniereinstellungen
- Hinweise
- Tonausgabe
- Vollständiger Turnierlog
- Spielerstatistiken
- Jahresrückblicke
- Vergangene Turniere

## Technische Randbedingungen

- Die Daten werden als kleines versioniertes JSON-Dokument in einen
  zweckgebundenen Supabase-Storage-Bucket geschrieben.
- Die Ansicht ist eine statische Seite, die das Dokument alle 30 Sekunden
  neu lädt. Bei 5–10 Zuschauern ist der Verbrauch vernachlässigbar.
- Es wird keine zweite Turnierlogik eingebaut: Tabellen, Brackets,
  Weiterkommen und Formattexte stammen aus den bestehenden Engines.
- Push-Benachrichtigungen sind ein separater späterer Schritt und nicht Teil
  dieser ersten Umsetzung.

## Einmalige Auslieferung

1. Migration `supabase/migrations/202611230001_live_tournament_bucket.sql` im
   Supabase-Projekt `rbcsrqisbuutnnxpmcvp` ausführen. Sie erzeugt den
   öffentlichen, nur lesbaren Bucket `live-tournament`. Der private Bucket
   `dart-app-backups` bleibt unverändert.
2. Die App lädt `assets/live/live_viewer.html` beim ersten Aktivieren des
   Live-Schalters unter `verein-live/index.html` hoch. Danach ist die stabile
   URL auch ohne erneutes Veröffentlichen aufrufbar.
3. Solange der Schalter aktiv ist, schreibt die App `verein-live/latest.json`
   alle 30 Sekunden neu. Beim Deaktivieren wird das JSON entfernt; die leere
   Viewer-Seite bleibt unter der festen URL erreichbar.

Die QR-URL ist bereits dauerhaft gültig. Bevor Migration und erster Upload
erfolgt sind, zeigt sie noch keine Turnierdaten an.
