# Supabase-Synchronisierung

Jedes Supabase-Konto erhält einen getrennten privaten Komplett-Datenstand.
Spielerprofile selbst benötigen keine Supabase-Konten. Änderungen werden lokal
gespeichert und nach kurzer Verzögerung als vollständiger Datenstand
hochgeladen. Beim Start, nach Anmeldung und beim Fortsetzen der App wird ein
neuerer Cloud-Stand auf das Gerät geladen, sofern dort keine ungesicherten
lokalen Änderungen vorliegen. Laptop und Handy verwenden damit denselben Pool,
wenn beide mit demselben Supabase-Konto angemeldet sind. Andere Konten erhalten
eigene lokale und Cloud-Daten.

Wenn beide Geräte offline oder gleichzeitig Änderungen vorgenommen haben,
ersetzt die App keinen der beiden Stände automatisch. In **Einstellungen →
Daten** kann dann bewusst der lokale Stand hochgeladen oder der Cloud-Stand
geladen werden. Das ist eine Synchronisierung vollständiger Snapshots, keine
Zusammenführung einzelner Turniere oder Spieler.

## Projekt einrichten

1. Im eigenen Supabase-Projekt unter **SQL Editor** den Inhalt von
   [`fresh_sync_schema.sql`](../supabase/fresh_sync_schema.sql) ausführen.
2. Unter **Authentication → Users** ein Betreiberkonto anlegen und die
   E-Mail-Adresse bestätigen.
3. Beim Flutter-Start die URL und den Publishable Key des eigenen Projekts
   übergeben. Der Key ist ein öffentlicher Client-Key und darf nicht mit einem
   Secret-/Service-Role-Key verwechselt werden:

```powershell
flutter run `
  --dart-define="SUPABASE_URL=https://<projekt-ref>.supabase.co" `
  --dart-define="SUPABASE_PUBLISHABLE_KEY=<PUBLISHABLE_KEY_DES_PROJEKTS>"
```

Die Zugangsdaten im App-Build müssen zum eigenen Supabase-Projekt gehören.
Der GitHub-Actions-Releaseworkflow baut die App für das konfigurierte
Supabase-Projekt und verwendet dafür die Repository-Variable
`SUPABASE_PUBLISHABLE_KEY`. Eine heruntergeladene EXE lässt sich nicht nachträglich
auf ein anderes Supabase-Projekt umstellen; dafür muss sie mit dessen URL und
Publishable Key neu gebaut werden. Ein Service-Role-Key gehört niemals in einen
App-Build.

Ein weiterer Windows-PC benötigt weder Flutter noch einen eigenen Build: Die
EXE kann sich über das Internet mit genau dem Supabase-Projekt verbinden, für
das sie gebaut wurde. Dafür muss dort ein Betreiberkonto unter
**Authentication → Users** manuell angelegt und bestätigt sein; angemeldet wird
sich mit dessen E-Mail-Adresse und Passwort, nicht mit dem Passwort für das
Supabase-Dashboard oder einem API-Key. Die Synchronisierung funktioniert erst,
wenn auch das Schema aus `fresh_sync_schema.sql` samt Storage-Regeln im selben
Projekt eingerichtet ist. Ohne ein dort angelegtes Benutzerkonto gibt es keine
Selbstregistrierung über die App.

Die Backup-Richtlinien beschränken Lesen, Erstellen, Ersetzen und Löschen auf
den Ordner des angemeldeten Betreiberkontos. Es werden keine alten
Community-Tabellen oder Testdaten migriert. Der lokale Export und die
Wiederherstellung verwenden weiterhin die vorhandene Prüfsummen- und
Rollback-Logik. Die Cloud-Sicherung enthält Turniere, lokale Spielerkonten samt
Challonge-Verknüpfungen, Ranglisten, Bestleistungen und Planungseinstellungen.
Beim ersten Start mit dem neuen lokalen SQLite-Schema wird eine vorhandene
alte App-Datenbank vorher als `.bak` gesichert und auf Spieler, Ranglisten und
Challonge-Verknüpfungen reduziert.
