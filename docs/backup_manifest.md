# Lokales Backupmanifest

Stand: 2026-11-07. Das Backupformat von `BackupService` ist Version 1 und
verwendet eine feste Dateiliste. Ein Eintrag enthält entweder `null` für eine
Datei, die auf dem Gerät noch nicht angelegt wurde, oder Base64-Daten mit
SHA-256-Prüfsumme. Restore prüft alle Einträge und migriert Datenbankkopien
isoliert, bevor Live-Dateien ersetzt werden.

| Datei | Inhalt | Eigene Version |
| --- | --- | --- |
| `tournaments.json` | Lokale Turniere, Ergebnisse, Rechte-/Outboxdaten und Turniercaches | JSON-Schema 22 |
| `app_database.sqlite` | Lokales Konto, Spielerprofile, Ranglisten, Achievements und Monatsstatistiken | SQLite user_version 15 |
| `planning_settings.json` | Dauerannahmen des Turnierformat-Finders | JSON-Schema 2 |
| `devices.json` | Gekoppelte Geräte und Verbindungseinstellungen | JSON-Schema 2 |

Zugangstokens und Authentifizierungsgeheimnisse werden nicht in das Backup
aufgenommen. Die Dateiliste ist absichtlich eine Allowlist, damit ein Backup
keine beliebigen Pfade überschreiben kann.

Beim Upgrade von SQLite-Version 14 auf 15 ergänzt die App fehlende
Achievement-Alternativwert-Spalten innerhalb einer Transaktion. Vorher wird
die Datenbank als `app_database.sqlite.v14.<Zeitstempel>.bak` gesichert;
vorhandene Fortschritts- und Statistikdaten werden beibehalten. Schlägt die
Migration fehl, wird sie zurückgerollt und die Sicherung nicht verändert.
Installiere Updates regulär über die App, exportiere vorab zusätzlich ein
Backup über **Einstellungen → Daten**, und lösche weder die App-Daten noch
die `.bak`-Sicherung. Eine ältere App-Version kann Schema 15 ablehnen; bei
einem Rollback zuerst die Daten über die Sicherungs-/Restore-Funktion mit
einer kompatiblen Version wiederherstellen, nicht die Datenbank manuell
bearbeiten.

Die vier registrierten Dateien sind der aktuelle Vertrag, keine vollständige
Erfassung jedes App-Preferences-/Feature-Speichers. Weitere Turnierverwaltungs-
Speicher müssen vor einer Erweiterung des Manifests inventarisiert und mit
Altversions-/Teilfehler-Restoretests abgesichert werden. Scorer- und
Autoscoring-Drafts bleiben außerhalb dieses Turnierverwaltungs-Backups.
