# Turnierspeicher: Schema und Migrationen

Stand: 2026-10-20. Die führende Versionskonstante ist
`TournamentStorage._schemaVersion` in
`lib/features/tournaments/data/tournament_storage.dart` (aktuell **23**).
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

Der veröffentlichte Tag `v1.0.3+3` setzte die Versionskonstante auf 24;
`v1.0.4+4` setzte sie ohne passende JSON-Migration auf 23 zurück. Das ist
kein Beleg, dass beliebige Version-24-Dokumente als Version 23 lesbar sind.
Die eng begrenzte Recovery akzeptiert Version 24 nur, wenn die vollständige
Datei nach Ausklammern ausschließlich des Wurzelfelds `schemaVersion`
semantisch exakt mit der benachbarten `tournaments.json.v22.bak` übereinstimmt.
Fehlt dieser Beleg, ist die Sicherung ungültig/zu groß oder weicht sie ab,
bleibt das Dokument gesperrt und unverändert. Die Sicherungsdatei wird nie
geändert. Beim späteren Speichern werden `.bak` und `.v24.bak` angelegt, bevor
die aktuelle Version 23 geschrieben wird.

Die markierten historischen Lücken sind absichtlich kenntlich gemacht und
sollten bei einer Änderung dieser alten Formate nur anhand nachprüfbarer
Migrationen und Fixtures ergänzt werden. Diese Chronik behandelt ausschließlich
den Turnierspeicher; andere Feature-Speicher besitzen eigene Versionen.
