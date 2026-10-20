# Infrastruktur und Update-Sicherheit

Prüfstand: 20.10.2026. Backup/Wiederherstellung und Speichersperren sind implementiert. Der erste signierte Android-Release über GitHub ist veröffentlicht. Backup und Datenerhalt beim APK-Upgrade wurden im Android-Emulator geprüft; ein physischer Gerätetest steht noch aus. Siehe `android-releases.md`.

## Speichervertrag

- Windows: Turniere und SQLite liegen weiterhin unter `%APPDATA%/DartTournamentManager`, außerhalb des Installationsordners. Bestehende Pfade wurden nicht verschoben.
- Planungseinstellungen und Geräteidentität liegen im bisherigen Application-Support-Verzeichnis von path_provider. Dieses muss bei Updates ebenfalls erhalten bleiben.
- Mobile/macOS: Turniere und Datenbank verwenden Application Support. Fehler bei der Pfadauflösung werden weitergegeben; es wird kein zufälliger temporärer Ersatzspeicher angelegt.
- Ohne APPDATA wird auf Desktop kein Arbeitsverzeichnis als Ersatz verwendet. Für Linux ist vor Auslieferung ein expliziter XDG-Pfad mit Migration vorhandener Daten erforderlich.
- JSON wird über eine temporäre Datei mit flush und anschließendem rename ersetzt. Turniere, Planung, Geräte, SQLite-Zugriffe und Backups nutzen die gemeinsame Warteschlange `StorageAccess`.
- Vor dem Ersetzen wird der bisherige gültige Stand als `.bak` gesichert. Bei einem Turnier-Schemawechsel bleibt zusätzlich `.vN.bak` erhalten. Beschädigte und unbekannte neuere Formate blockieren Schreibzugriffe.
- SQLite-Migrationen laufen in einer Transaktion. Vor einer Migration bestehender versionierter Datenbanken erstellt `VACUUM INTO` eine konsistente Sicherung. Neuere Datenbankschemata werden abgewiesen.
- Der App-Bootstrap hält vor dem ersten Datenzugriff eine Betriebssystem-Dateisperre auf `app.lock`. Eine zweite Instanz wird blockiert; bei Prozessende wird die Sperre freigegeben. Die Lockdatei darf nicht manuell gelöscht werden.

## Datensicherung in der App

Unter **Einstellungen → Datensicherung** stehen Export und Wiederherstellung bereit. Das versionierte `.dartbackup`-Format enthält die vier lokalen Speicher mit Prüfsummen; SQLite wird beim Export über `VACUUM INTO` konsistent kopiert. Cloud-Anmeldetokens und entfernte Cloud-Daten sind ausdrücklich nicht Bestandteil des Backups. Gerätekopplungen sind enthalten, die Datei ist nicht verschlüsselt.

Vor dem Import werden Prüfsummen, Dateinamen, Versionen und die Lesbarkeit der Inhalte geprüft. SQLite-Migrationen werden dabei nur an einer temporären Kopie getestet. Eine Vorschau und Bestätigung gehen der vollständigen Ersetzung voraus; fehlende Bereiche werden zurückgesetzt. Der aktuelle Stand wird vorher als `backups/before_restore_*.dartbackup` gesichert. Ein Journal sichert das Zurückrollen bei Fehlern und beim nächsten Start nach einem unterbrochenen Import. Erst nach dem Ersetzen aller Dateien wird der Abschluss atomar markiert.

Nach erfolgreicher Wiederherstellung blockiert die App weitere Zugriffe und verlangt einen Neustart. Dadurch können alte Controller den importierten Stand nicht überschreiben. Normale Sicherungen werden nie ohne Nutzerentscheidung zurückgespielt; nur eine unvollständige Importtransaktion wird automatisch zurückgerollt.

Das Dateiauswahl-Modul verwendet native Dialoge. Die Verifikation erfolgte für Windows; vor Releases auf anderen Plattformen sind die Dialogfunktionen und Speicherpfade gesondert zu prüfen. Größenlimit des Archivs: 128 MB. Lokale automatische Sicherungen ersetzen kein Backup auf einem anderen Datenträger.

## Architektur

Bootstrap, Feature-Ordner, Domain-Engines und Persistenz sind getrennt angelegt. Die Übergangs-Library `tournament_workspace.dart` koppelt jedoch weiterhin UI und Laufzeit über Parts. Die produktive Runtime sollte als Application-Service extrahiert werden; der Entwicklungstester muss weiterhin dieselbe Engine verwenden. Dieser Refactor ist keine Voraussetzung für den reinen Austausch der App-Dateien.

## Desktop-Updates und Schema-Kompatibilität

- Windows-Releases werden als ZIP-Bundle (`dart-turnier-windows-x64.zip`), nicht als klassischer Installer, veröffentlicht. Der Updater prüft Größe und SHA-256, entpackt in `%APPDATA%` unter `desktop_updates`, validiert Manifest und Programmdateien und erstellt vor dem Neustart ein `.dartbackup`.
- Beim Windows-Neustart wartet ein eigener PowerShell-Prozess auf das Ende der bisherigen App. Er startet das neue Bundle mit Aktivierungs-ID und wartet auf dessen `active.json`-Bestätigung. Schlägt der Start fehl, protokolliert `restart.log` den Grund und der bisherige Programmstart wird als Fallback versucht. Benutzerdateien werden nicht ersetzt oder gelöscht.
- Release `v1.0.4+4` verwendet SQLite-Schema 10 und Turnier-JSON-Schema 23. Das Upgrade von SQLite 9 auf 10 fügt `custom_order` innerhalb einer Transaktion hinzu, behält Profile, Ranglisten und Zuordnungen und legt vorher eine `.v9.*.bak`-Kopie an.
- `v1.0.3+3` schrieb Turnier-JSON-Schema 24; `v1.0.4+4` setzte nur die akzeptierte Versionsgrenze auf 23 zurück, ohne eine Datenmigration. v1.0.6 stellt deshalb die belegte Schema-24-Kompatibilität wieder her. Die Schema-24-Serialisierung schrieb `countsForRanking` explizit; dieser Wert wird von der aktuellen Model-Serialisierung erhalten. Beim ersten Speichern wird die alte Datei als `.bak` gesichert. Die schema-24-Vorprüfung benötigt keine `.v22.bak`: bei angemeldeten Konten liegen Turnierdateien unter `supabase_accounts/<Konto-ID>/`, getrennt vom Root-Speicher.
- App-Version und SQLite-/JSON-Speicherversion bleiben getrennte Nummern. Ein Build aus `main` darf kein veröffentlichtes neueres Speicherschema abweisen; jede künftige Schemaänderung braucht eine gezielte Migration sowie einen Upgrade-Test mit repräsentativen Bestandsdaten.

## Verifikation

Die automatischen Tests decken die Wiederherstellung aller vier Speicher inklusive Matchergebnissen, Vorschau/Abbruch/Bestätigung, Versions- und Prüfsummenfehler, fehlerhafte Datenbanken, fehlende Bereiche, Fehler nach dem ersten Dateitausch, unterbrochene und abgeschlossene Transaktionen sowie konkurrierende Zugriffe ab. Zusätzlich werden Schema-24-Lesen/Schreiben mit Erhalt von `countsForRanking` und der `.bak`-Sicherung, die v9→v10-Migration mit erhaltenen Spieler-/Ranglisten-Datensätzen und der Windows-PowerShell-Handoff für Aktivierungsbestätigung und Fallback geprüft. Ein echter Installer-/Upgrade-Lauf mit den Nutzerdaten eines Zielgeräts ist weiterhin separat zu prüfen.
