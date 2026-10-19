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
Release-Builds benötigen dieselben Werte als Build-Konfiguration; der eigene
Release-Workflow ist noch nicht eingerichtet.

Die Backup-Richtlinien beschränken Lesen, Erstellen, Ersetzen und Löschen auf
den Ordner des angemeldeten Betreiberkontos. Es werden keine alten
Community-Tabellen oder Testdaten migriert. Der lokale Export und die
Wiederherstellung verwenden weiterhin die vorhandene Prüfsummen- und
Rollback-Logik. Die Cloud-Sicherung enthält Turniere, lokale Spielerkonten samt
Challonge-Verknüpfungen, Ranglisten, Bestleistungen und Planungseinstellungen.
Beim ersten Start mit dem neuen lokalen SQLite-Schema wird eine vorhandene
alte App-Datenbank vorher als `.bak` gesichert und auf Spieler, Ranglisten und
Challonge-Verknüpfungen reduziert.
