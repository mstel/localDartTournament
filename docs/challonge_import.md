# Alte Challonge-Turniere in eine App-Community übernehmen

In der Ziel-Community unter **Turniere → Challonge-Turniere importieren**:

1. Den öffentlichen Turnierlink eingeben, beispielsweise `https://challonge.com/de/DCUH202637`. Der API-Schlüssel bleibt leer.
2. **Importvorschau laden** öffnet die öffentliche Seite im eingebauten Browser und liest anschließend die offizielle Rangliste. Eine eventuell angezeigte Browserprüfung selbst abschließen und **Seite erneut prüfen** wählen.
3. Alternativ **Turniere laden** mit dem vorausgefüllten Community-Link verwenden. Auf der Challonge-Seite **PAST** auswählen, die Liste laden lassen und **Seite erneut prüfen** drücken. Erfasst werden die Links auf der aktuell geladenen Seite. Weitere Seiten beziehungsweise fehlende Turniere über einzelne Links ergänzen.
4. Die Vorschau kontrollieren. Gleiche Mitgliedsnamen werden nach Groß-/Kleinschreibung und Leerzeichen abgeglichen. Abweichende Namen bestehenden Mitgliedern zuordnen. Mehrdeutige Namen benötigen eine ausdrückliche Zuordnung.
5. **Turniere und fehlende Mitglieder importieren** übernimmt die Auswahl. Fehlende Teilnehmer werden als Community-Mitglieder ohne Benutzerkonto angelegt. Nach den bestehenden Serverregeln braucht das Anlegen neuer Mitglieder den Community-Eigentümer; der Turnierimport braucht „Turniere erstellen“. Es werden keine Challonge-Konten angelegt und keine Einladungen versendet.

## Ergebnisse und Wiederholung

Neue Importe werden als reguläre Turniere mit eigenen Gruppen-/Swiss- und K.-o.-Etappen gespeichert und in den normalen Turnieransichten geöffnet. Der Import übernimmt historische Paarungen und K.-o.-Startplätze. Tabellen und Qualifikation berechnet die produktive Laufzeit; K.-o.-Ergebnisse werden durch ihre normale Weiterleitung nachgespielt. Die Auslosung und historische Swiss-Paarungserzeugung werden dadurch nicht geprüft.

Bereits importierte Challonge-Archive lassen sich in der Turnierliste über das
Dreipunkt-Menü mit **Zu Dart-Turnier konvertieren** in native, abgeschlossene
Turniere umwandeln. Dafür muss jeder Challonge-Teilnehmer einem eigenen Profil
im lokalen Spielerkatalog zugewiesen sein. Die Konvertierung baut Gruppen,
Spielwiederholungen, KO-Etappen und historische Ergebnisse erneut auf; Gruppen-
und KO-Spiele behalten ihre Quellzeitstempel und werden chronologisch sortiert.
Falls gespeicherte Archivdaten für die Rekonstruktion nicht ausreichen, versucht
die App die fehlenden öffentlichen Daten erneut über den Challonge-Link zu laden
und ordnet Teilnehmer nur anhand eindeutiger Quellkennungen oder Namen zu.
Nach erfolgreicher Konvertierung öffnet sich die normale Abschlussansicht; das
native Turnier kann wie andere abgeschlossene Turniere erneut geöffnet werden.
Die Challonge-Quelldaten bleiben für den Vergleich erhalten. Platzierungs-
abweichungen werden dort ausgewiesen und nicht stillschweigend überschrieben.

Originalspielstände, Sieger, Verlierer, Runden und offizielle Endplatzierungen bleiben daneben als Vergleichsquelle erhalten. Gruppenplätze werden getrennt gespeichert. Der Vergleich prüft ausschließlich veröffentlichte Plätze; die eigene Ergebnisansicht kann weitere Plätze berechnen. Abweichungen werden in der Vorschau und unter **Mit Challonge vergleichen** in den Turnierergebnissen angezeigt. Unterschiedliche Tie-Breaker und geteilte Challonge-Plätze können Abweichungen verursachen. Die historischen K.-o.-Teilnehmer bleiben erhalten, wenn die eigene Gruppenqualifikation abweicht; diese Abweichung wird ausdrücklich dokumentiert.

Unterstützt werden Einzelturniere mit Round Robin, Swiss, Einfach-K.-o. und Doppel-K.-o., einschließlich rekonstruierbarer Gruppenphasen und Spiel um Platz 3. Unvollständig rekonstruierbare Ergebnisse oder K.-o.-Weiterleitungen brechen vor Mitgliederanlage und Speicherung ab. Mehrteilige Spielstände und kampflose Spiele ohne eindeutigen Leg-Stand werden derzeit nicht nativ übertragen.

Einzelne ganzzahlige Spielstände wie `3-1` werden bei passendem Sieger als Legs übernommen. In der Vorschau lässt sich **Für Elo und Community-Ranglisten werten** aktivieren und mindestens eine Rangliste auswählen. Standardmäßig bleibt die Wertung ausgeschaltet. Die Auswahl gilt für neue und umgestellte Turniere. Historische Turniere werden nach ihrem Datum berücksichtigt. Ohne Spielzeitangaben werden Gruppenspiele vor K.-o.-Spielen in stabiler Reihenfolge gewertet; die zeitliche Reihenfolge paralleler Gruppenspiele ist aus der öffentlichen Quelle nicht rekonstruierbar.

Die öffentliche Seite liefert häufig nur das Startdatum. Es wird als Startdatum und historisches Erstellungsdatum übernommen; ein fehlender Abschlusszeitpunkt bleibt leer. JSON/API-Exporte benötigen weiterhin ihre historischen Erstellungs- und Abschlussdaten. Unvollständige Daten, unbekannte Spielerkennungen und Teamturniere werden abgewiesen.

Die Importkennung ist pro Ziel-Community und Challonge-ID eindeutig. Wiederholungen überspringen bereits native Importe und verwenden Mitglieder wieder. Alte reine Archivimporte werden beim erneuten Import in native Turniere umgestellt; dabei gilt die aktuelle Elo-Auswahl. Das Archivformat Version 3 ergänzt den Prüfbericht und liest weiterhin Versionen 1 und 2. Ohne erneuten Import bleiben alte Archive unverändert lesbar. Der lokale Speicher und die Community-Synchronisierung speichern Etappen, Spiele und Vergleichsdaten gemeinsam.

## Zugriff und Prüfung

Der normale Browserzugriff benötigt keinen API-Schlüssel. Die Challonge-Seite führt ihre üblichen Seitenskripte im Browser aus; der Parser liest ausschließlich DOM und eingebettetes JSON und führt dessen Inhalt nicht aus. Browserdaten liegen im normalen lokalen Browserprofil, unter Windows im App-Datenordner. Sie werden nicht mit dem Turnier gespeichert. Hauptnavigation bleibt auf HTTPS-Challonge-Seiten beschränkt. Windows benötigt Microsoft Edge WebView2. Browserprüfungen werden nicht automatisiert umgangen.

Der reine HTTP-Zugriff auf die Beispielseite antwortete mit HTTP 403; die Seite war im normalen Browser öffentlich lesbar. Am 8. Oktober 2026 wurden die echten Strukturen von [DCUH202637](https://challonge.com/de/DCUH202637) geprüft: sieben Teilnehmer, 21 Gruppenspiele und vier K.-o.-Spiele einschließlich Spiel um Platz 3. Endplätze: Max_Re, Jan_Wa, Mike_Ro, Marvin_S. Alle sieben Gruppenplätze werden gesondert erhalten. Die übrigen drei Spieler erhalten keine erfundene Gesamtplatzierung.

Der automatisierte Test `test/challonge_public_bracket_test.dart` bildet diese beobachteten Spieldaten ohne Bild-/Kontometadaten nach und prüft auch abweichende Gruppen-Spielerkennungen. Import-, Speicher-, Turniermatrix- und responsive Tests ergänzen die Prüfung. Ein authentifizierter Import in eine echte Ziel-Community und eine Sichtprüfung auf physischen Smartphones wurden nicht durchgeführt.

Der optionale API-Zugang und vollständige JSON-Dateien bleiben verfügbar. Der API-Schlüssel wird nur vorübergehend an `api.challonge.com` gesendet und nicht gespeichert.

Die laufende App wird nicht beendet oder ersetzt. Ein Browser-Durchlauf in der Windows-App und ein Schreibimport in die echte Community sind noch nicht geprüft. `test/challonge_native_import_test.dart` prüft Round-Robin-Abweichungen, Swiss-Unentschieden, Doppel-K.-o.-Reset, Abbruch vor Schreibzugriffen, Archivumstellung und native Ergebnisnavigation bei drei Displaygrößen mit 200 Prozent Schrift. `test/challonge_public_bracket_test.dart` prüft die native Übertragung aller 25 Spiele und übereinstimmende Plätze des Spieltags 37.

Namensabgleich: Challonge kann einen Turniernamen zusammen mit einem abweichenden Kontonamen in Klammern anzeigen, etwa Tom_Dc (Tom_Ba) auf Spieltag 29. Der Parser übernimmt den Turniernamen für Gruppen- und Endplatzierungen. Falls die Tabellenanzeige abweicht, wird nur eine eindeutige Zuordnung über die Spielhistorie akzeptiert. Fehlermeldungen nennen andernfalls Teilnehmer und Quellturnier.


Swiss- und Round-Robin-Turniere: Die offizielle Platzierungstabelle mit Teilnehmerzellen wird zusätzlich zur K.-o.-Rangliste unterstützt. Gruppenplatzierungen werden weiterhin getrennt behandelt. Die Community-Linkliste übernimmt den Titel der Turnierkarte ohne angehängte Format-, Spielerzahl- und Datumsangaben; API- und Übersetzungslinks werden herausgefiltert.

Prüfstand native Einbindung: Analyse ohne Befunde; Import-/Elo-Tests, native Ergebnisnavigation, Ergebnisstatistik-Regressionsprüfung und Turniermatrix erfolgreich. Adaptive Layouts und die gefilterte Challonge-Seitenmatrix bei 360x800, 800x600 und 1440x900 mit 100/200 Prozent Schrift bestehen; Desktop-/Mobile-PNGs wurden geprüft. Die ungefilterte gemeinsame Seitenmatrix bleibt bei `TournamentImportPreview` (vor den Challonge-Seiten) stehen und konnte nicht abgeschlossen werden. Keine Sichtprüfung auf physischen Geräten und kein authentifizierter Community-Schreibimport.
