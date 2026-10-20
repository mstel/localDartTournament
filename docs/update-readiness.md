# Infrastruktur und Update-Sicherheit

Prüfstand: 24.09.2026. Backup/Wiederherstellung und Speichersperren sind implementiert. Der erste signierte Android-Release über GitHub ist veröffentlicht. Backup und Datenerhalt beim APK-Upgrade wurden im Android-Emulator geprüft; ein physischer Gerätetest steht noch aus. Siehe `android-releases.md`.

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

## Vor dem ersten automatischen Update noch erforderlich

1. Festen Release-Kanal, Paketidentitäten und Signierung festlegen. Beispiel-Bundle-IDs vor Veröffentlichung kontrolliert ersetzen; Application-Support-Pfade dürfen dabei nicht ohne Migration wechseln.
2. App-Version/Buildnummer bei Releases erhöhen (aktuell `1.0.4+4`). App-Version und Speicherschema getrennt behandeln.
3. Updater lädt und prüft signierte Pakete, beendet die App nach abgeschlossenen Schreibvorgängen und ersetzt ausschließlich Installationsdateien. Benutzerverzeichnisse sind vom Löschen/Aufräumen ausgeschlossen.
4. Installations-Upgrade und Rollback mit realen alten Spielständen auf jeder Zielplattform testen. Alte bereits veröffentlichte Binärdateien besitzen den neuen Versionsschutz und die Instanzsperre noch nicht und dürfen neue Daten nicht öffnen.

## Verifikation

Die automatischen Tests decken die Wiederherstellung aller vier Speicher inklusive Matchergebnissen, Vorschau/Abbruch/Bestätigung, Versions- und Prüfsummenfehler, fehlerhafte Datenbanken, fehlende Bereiche, Fehler nach dem ersten Dateitausch, unterbrochene und abgeschlossene Transaktionen sowie konkurrierende Zugriffe ab. Die Instanzsperre wird mit einem echten zweiten Dart-Prozess geprüft. Windows-Debug-Build erfolgreich; native Dateidialoge wurden nicht interaktiv bedient.

Die Änderungen verbessern den Speicherschutz, stellen aber noch keine Ende-zu-Ende-Garantie eines bislang nicht vorhandenen Installers/Updaters dar.
