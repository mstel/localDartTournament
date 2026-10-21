# Turnierspeicher: Schema und Migrationen

Stand: 2026-10-20. Die führende Versionskonstante ist
`TournamentStorage._schemaVersion` in
`lib/features/tournaments/data/tournament_storage.dart` (aktuell **25**).
Änderungen an gespeicherten Turnierdaten müssen die Version dort, diese
Chronik und die Migrations-/Backup-Tests gemeinsam aktualisieren. Ältere
Speicherstände werden beim nächsten Schreiben auf die aktuelle Version
gesetzt; vor einem Versionswechsel legt `TournamentStorage` eine
versionsgebundene Sicherung an. Höhere unbekannte Versionen werden abgelehnt.

| Version | Änderung | Verhalten für ältere Daten |
| --- | --- | --- |
| 1 | Ursprüngliches JSON-Turnierdokument | Ausgangsformat |
| 2 | Boardanzahl sowie Matchstart- und Abschlusszeit | Standardwerte: ein Board, keine Zeiten |
| 3 | Sets pro Etappe und optionale Satzergebnisse | Ein Set; Satzergebnisse bleiben leer |
| 4 | Outbox und kontobezogene Lesecaches | Fehlen bei Altständen |
| 5 | Finale Regeln und Leben | Legacy-Finale bleiben erhalten |
| 6 | Platzierungs-Auswahl und Klassifikations-Match-IDs | Felder bleiben optional |
| 7 | Kontobezogene Scorerhistorien | Historischer Bereich; nicht Teil neuer Tournierrunden |
| 8 | Keine Änderung in den verfügbaren Quellkommentaren dokumentiert | Bestehende optionale Felder bleiben erhalten |
| 9 | Optionale RHL-Spielpläne | `leagueMatch` bleibt leer |
| 10 | Mannschaftskader | Alte Teilnehmende bleiben Einzelspieler |
| 11 | Liga-Board- und Scorerfortschritt | Keine Zuordnungen für alte Ligen |
| 12 | Turnierzeiten und ursprüngliche Planungsbasis | Felder bleiben optional |
| 13 | Geplanter Matchabschluss-Zeitverlauf | Keine Historie bei Altständen |
| 14–15 | In den verfügbaren Quellkommentaren nicht dokumentiert | Bestehende Model-Defaults gelten |
| 16 | Aufgelöste Botprofile | Fehlende Profile bedeuten menschliche Teilnehmende |
| 17 | Versionierte Challonge-Archive | `null` bei Altständen |
| 18 | Gespeicherte Boardausschlüsse | Keine gesperrten Boards |
| 19 | Turnierbezogene Leitung und Ergebniseingaberechte | Rechte werden über Model-Defaults ergänzt |
| 20 | Optionale Matchstarts von zugeordneten Boardgeräten | Funktion bleibt standardmäßig aus |
| 21 | Spielerausstieg und Folgezustand | Kein Ausstieg für ältere Turniere |
| 22 | Begrenzte Round-Robin-Konfiguration | Bestehende Etappen behalten ihre bisherige Konfiguration |
| 23 | Kein eigenständiger JSON-Schemawechsel in der Release-Historie belegt | Bekannte Felder bleiben erhalten |
| 24 | In `v1.0.3+3` als Versionsstand verwendet; die Serialisierung enthält zusätzlich explizit `countsForRanking` | Nur mit exakt übereinstimmender v22-Sicherung als belegter Recovery-Fall lesbar |
| 25 | Strukturell unveränderte Serialisierung; neue Leser-Grenze verhindert ungeprüftes Schreiben in v24-Dateien | Normales Lesen und Schreiben |

Der veröffentlichte Tag `v1.0.3+3` setzte die Versionskonstante auf 24;
`v1.0.4+4` senkte sie ohne eine entsprechende JSON-Migration auf 23 zurück.
Das war eine Lesergrenzen-Regression, nicht ein belegter Schema-Rückschritt:
`CreatedTournament`-Serialisierung blieb strukturell kompatibel; v1.0.3 schrieb
`countsForRanking` explizit und die v1.0.5-Leser erhält dieses Feld. Die
v1.0.7-Lesergrenze wurde auf 24 zurückgesetzt, obwohl eine sichere Recovery für
diesen eng belegten Fall eine passende `.v22.bak` voraussetzt. Schema-24-Dateien
werden daher nur akzeptiert, wenn `tournaments.json.v22.bak` existiert, selbst
Schema 22 ausweist und nach strukturellem JSON-Vergleich (nur
`schemaVersion` ausgenommen) exakt übereinstimmt. Größenlimits gelten für beide
Dateien; Backup-Dateien werden nicht verändert. Ohne passende Sicherung oder
bei jeder Abweichung bleibt die Originaldatei unverändert und wird mit klarer
Diagnose abgelehnt. Der Backup-Export enthält diese Proof-Datei ebenfalls.
Ein belegter v24-Speicher wird beim nächsten Schreibvorgang auf Schema 25
angehoben, nachdem die bisherige Originaldatei zusätzlich als `.bak` gesichert
wurde.

Die markierten historischen Lücken sind absichtlich kenntlich gemacht und
sollten bei einer Änderung dieser alten Formate nur anhand nachprüfbarer
Migrationen und Fixtures ergänzt werden. Diese Chronik behandelt ausschließlich
den Turnierspeicher; andere Feature-Speicher besitzen eigene Versionen.
