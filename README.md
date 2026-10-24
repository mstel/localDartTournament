# 🎯 DartTournamentPro

**Die zentrale Plattform für Dartturniere, Spielerstatistiken und Ranglisten.**

DartTournamentPro ist eine umfassende Turnierverwaltungsanwendung für den Steeldartsport. Sie vereint die Organisation und Durchführung von Turnieren, eine zentrale Spielerverwaltung, umfangreiche Statistiken und individuell konfigurierbare Ranglistensysteme in einer Anwendung.

Von klassischen Turnieren über mehrstufige Wettbewerbe bis hin zu langfristigen ELO-Ranglisten und saisonalen Turnierserien bietet DartTournamentPro zahlreiche Werkzeuge für einen strukturierten Spielbetrieb.

## ✨ Funktionen im Überblick

- **Turnierverwaltung:** Turniere erstellen, importieren, exportieren und live verwalten.
- **KI-gestützter Turnierformfinder:** Geeignete Turnierformate anhand individueller Vorgaben und einer gewünschten Spieldauer ermitteln.
- **Flexible Turnierformate:** Mehrstufige Turniere mit unterschiedlichen Spielsystemen kombinieren.
- **Spielerverwaltung:** Zentrale Spielerkataloge mit umfangreichen Profilen und Statistiken.
- **Ranglistensysteme:** Individuelle ELO- und Punkteranglisten mit konfigurierbaren Regeln.
- **Statistiken und Jahresrückblicke:** Spielleistungen, Bestleistungen und Entwicklungen analysieren.
- **Live-Dashboard:** Turnierfortschritt, Ergebnisse, Prognosen und organisatorische Hinweise verfolgen.
- **Zwei-Monitor-Modus:** Separate Turnierinformationen auf einem zusätzlichen Bildschirm oder Fernseher anzeigen.
- **Cloud-Synchronisation:** Daten über Supabase zwischen unterstützten Geräten synchronisieren.
- **Website-Schnittstelle:** Ranglisten, Spielerprofile, Statistiken, Bestleistungen und abgeschlossene Turniere authentifiziert und schreibgeschützt bereitstellen. Details: [Supabase-API für die Website](docs/website_supabase_api.md).
- **Updateverwaltung:** Nach neuen Versionen suchen und verfügbare Updates direkt in der Anwendung installieren.
- **Werkzeuge und Integrationen:** Unter anderem Govee-Lichtsteuerung und Entwicklungswerkzeuge für Turnierformate.

---

## 📋 Inhaltsverzeichnis

1. [Hauptmenü](#-hauptmenü)
2. [Turniere](#-turniere)
3. [Spielerverwaltung](#-spielerverwaltung)
4. [Statistiken und Jahresrückblicke](#-statistiken-und-jahresrückblicke)
5. [Ranglisten](#-ranglisten)
6. [Einstellungen und Verwaltung](#️-einstellungen-und-verwaltung)
7. [Datenverwaltung und Synchronisation](#-datenverwaltung-und-synchronisation)
8. [Integrationen und Schnittstellen](#-integrationen-und-schnittstellen)

---

## 🧭 Hauptmenü

Das Hauptmenü ist in fünf zentrale Bereiche unterteilt:

| Bereich | Beschreibung |
|---|---|
| **Turniere** | Turniere erstellen, importieren, durchführen und auswerten |
| **Spieler** | Spielerkatalog und individuelle Spielerprofile verwalten |
| **Statistiken** | Spielerstatistiken und Jahresrückblicke analysieren |
| **Ranglisten** | ELO- und Punkteranglisten konfigurieren und auswerten |
| **Einstellungen** | Daten, Synchronisation, Darstellung, Updates und Werkzeuge verwalten |

## 🏆 Turniere

Der Turnierbereich bildet den zentralen Bestandteil der Anwendung. Er umfasst die Erstellung, Durchführung, Überwachung und nachträgliche Auswertung von Dartturnieren.

### Turniere erstellen

Turniere können individuell angelegt und unterschiedlichen Kategorien zugeordnet werden:

- Normale Turniere
- Ranglistenturniere
- Ligaspiele
- Freundschaftsspiele

Bei der Erstellung stehen flexible Konfigurationsmöglichkeiten für den Ablauf und die Zusammensetzung des Turniers zur Verfügung.

### KI-gestützter Turnierformfinder

Der integrierte Turnierformfinder unterstützt bei der Auswahl eines geeigneten Turnierformats. Auf Basis der vom Nutzer eingegebenen Vorgaben und der gewünschten Gesamtdauer ermittelt er eine passende Turnierstruktur und übernimmt die ermittelten Einstellungen direkt in die Turniererstellung.

Dabei können unter anderem organisatorische Anforderungen und zeitliche Rahmenbedingungen berücksichtigt werden.

### Flexible Turnierformate

Ein Turnier kann aus bis zu drei aufeinanderfolgenden Etappen bestehen. Die einzelnen Etappen lassen sich mit unterschiedlichen Formaten konfigurieren und miteinander kombinieren.

Unterstützte Formate umfassen unter anderem:

- Gruppenphasen
- Kratzerturniere
- Schweizer System (Swiss)
- K.-o.-Phasen

Dadurch lassen sich sowohl einfache Turniere als auch komplexere Wettbewerbe mit Vorrunden und anschließenden Finalphasen abbilden.

Turniere können außerdem einer Rangliste zugeordnet werden, sodass ihre Ergebnisse in die entsprechende Wertung einfließen.

### Spieler zuweisen

Für die Teilnehmerverwaltung stehen zwei Möglichkeiten zur Verfügung:

- Spieler direkt für ein Turnier anlegen.
- Bereits vorhandene Spieler aus dem zentralen Spielerkatalog auswählen.

Dadurch können Spielerdaten über mehrere Turniere hinweg wiederverwendet und Statistiken langfristig zusammengeführt werden.

### Turnierimport und -export

Turniere können importiert und exportiert werden. Zusätzlich steht ein Import für Challonge-Turniere zur Verfügung.

Beim Challonge-Import können importierte Spielernamen mit Einträgen aus dem lokalen Spielerkatalog verknüpft werden. Auf diese Weise lassen sich historische Turnierergebnisse bestehenden Spielerprofilen zuordnen und rückwirkend in die Statistiken und Ranglisten integrieren.

### Live-Turnierverwaltung

Während eines laufenden Turniers stehen drei zentrale Ansichten zur Verfügung:

- **Dashboard**
- **Ergebnisse**
- **Einstellungen**

#### Dashboard

Das Dashboard bietet einen zentralen Überblick über den aktuellen Turnierverlauf und unterstützt sowohl die sportliche als auch die organisatorische Durchführung.

Je nach Turnierkonfiguration werden unter anderem folgende Informationen dargestellt:

- Zuletzt absolvierte und bevorstehende Begegnungen
- Aktuelle Tabellenstände innerhalb der Gruppen
- Veränderungen der ELO-Werte und Auswirkungen auf Ranglisten
- Turnierbestleistungen
- Turnieruhr und zeitlicher Verlauf
- Prozentualer Turnierfortschritt
- Prognosen zum Turniersieger und zur voraussichtlichen Turnierdauer
- Organisatorische Hinweise zur Unterstützung eines möglichst reibungslosen Turnierablaufs

#### Zwei-Monitor-Modus

Über einen separaten Anzeigemodus können ausgewählte Turnierinformationen auf einem zweiten Bildschirm oder Fernseher dargestellt werden.

Dadurch lassen sich Informationen für Zuschauer und Teilnehmer bereitstellen, während die eigentliche Turnierverwaltung auf dem Hauptgerät geöffnet bleibt.

#### Einstellungen während des Turniers

Auch nach Turnierbeginn können wichtige Einstellungen angepasst werden. Dazu gehören beispielsweise:

- Turniernamen ändern
- Spieler aus dem Turnier entfernen
- Gruppen bearbeiten
- Weitere Turniereinstellungen anpassen

Beim Entfernen von Spielern stehen zusätzliche Optionen zur Verfügung, mit denen festgelegt werden kann, ob ihre bisherige Wertung verloren gehen soll und ob ihre Begegnungen mit 0:0 gewertet werden sollen.

### Turnierübersicht und Auswertung

Nach einem Turnier bleiben die Ergebnisse und Auswertungen abrufbar.

Die Turnierübersicht umfasst unter anderem:

- Sämtliche Spielergebnisse und Begegnungen
- Podium und Platzierungen
- Auswirkungen auf zugeordnete Ranglisten
- Turnierstatistiken
- Bestleistungen
- Exportmöglichkeiten

Damit dient jedes abgeschlossene Turnier zugleich als Grundlage für die langfristige Dokumentation der sportlichen Entwicklung.

---

## 👥 Spielerverwaltung

Die Spielerverwaltung bietet einen zentralen Katalog aller hinterlegten Spieler. Die gespeicherten Informationen können für Turniere, Statistiken und Ranglisten wiederverwendet werden.

### Spielerdaten

Für jeden Spieler können unter anderem folgende Informationen hinterlegt werden:

- Name
- Spitzname
- Geburtsdatum
- Autodarts-Name
- Scolia-ID
- 3K-Darts-ID
- Challonge-Verknüpfungen

Die externen Kennungen ermöglichen die Zuordnung zu den jeweiligen Systemen und unterstützen die Zusammenführung von Spielerinformationen.

### Individuelle Spielerprofile

Jeder Spieler verfügt über eine umfangreiche Statistikseite, auf der seine bisherige sportliche Entwicklung nachvollzogen werden kann.

Die Profile enthalten unter anderem:

- Bisherige Turnierteilnahmen
- Gespielte Legs und Ergebnisse
- Erzielte Bestleistungen
- Aktuelle Platzierungen und Wertungen in zugeordneten Ranglisten
- Weitere verfügbare Leistungsstatistiken

Durch die Verknüpfung importierter Turniere mit dem Spielerkatalog können auch historische Daten in die langfristige Spielerstatistik einfließen.

---

## 📊 Statistiken und Jahresrückblicke

Der Statistikbereich bietet einen Überblick über die sportlichen Leistungen und Entwicklungen innerhalb des Vereins oder einer ausgewählten Rangliste.

Er gliedert sich in Spielerstatistiken und Jahresrückblicke.

### Spielerstatistiken

Die Spielerstatistiken ermöglichen die Auswertung individueller Leistungen auf Grundlage der erfassten Turnier- und Spielergebnisse.

### Jahresrückblicke für Ranglisten

Bei den Ranglisten-Jahresrückblicken kann zwischen einzelnen Jahresranglisten und dem gesamten verfügbaren Zeitraum unterschieden werden.

Dadurch lassen sich sowohl einzelne Saisons als auch die langfristige Entwicklung einer Rangliste analysieren.

Die Auswertungen umfassen beispielsweise:

- Anzahl der gespielten Legs
- Anzahl der absolvierten Turniere
- Entwicklung der Turnieraktivität nach Monat und Jahr
- Anzahl und Zusammensetzung der Bestleistungen
- Weitere verfügbare Kennzahlen der jeweiligen Rangliste

Bestleistungen werden nach Kategorien aufgeschlüsselt. Dazu gehören beispielsweise:

- 180er
- 170er
- Shortlegs
- High Finishes

Ein beispielhafter Rückblick könnte 3.000 gespielte Legs und 90 Bestleistungen ausweisen, aufgeteilt in 30 maximale 180er, 20 Ergebnisse mit 170 Punkten, 30 Shortlegs und 10 High Finishes.

Die Jahresrückblicke verfügen außerdem über Exportfunktionen, sodass Auswertungen außerhalb der Anwendung weiterverwendet werden können.

### Jahresrückblicke für Spieler

Zusätzlich können die Profilstatistiken einzelner Spieler nach Jahren gefiltert betrachtet werden.

Dadurch lassen sich persönliche Entwicklungen und Leistungswerte über mehrere Spielzeiten hinweg vergleichen, ohne sämtliche Turniere einzeln öffnen zu müssen.

---

## 📈 Ranglisten

DartTournamentPro unterstützt unterschiedliche Ranglistensysteme, die an die Anforderungen verschiedener Wettbewerbe und Turnierserien angepasst werden können.

### ELO-Ranglisten

ELO-Ranglisten ermöglichen eine fortlaufende Bewertung der Spielstärke anhand der Ergebnisse.

Bei der Erstellung einer Rangliste können unter anderem folgende Parameter konfiguriert werden:

- K-Faktor für die Berechnung der ELO-Veränderungen
- Einstufung beziehungsweise Kennzeichnung ab einem definierten Pro-Wert
- Gültigkeits- oder Startdatum der Rangliste
- Optionales Auf- und Abstiegssystem mit Rangstufen (Tiers)

Das Tiersystem orientiert sich konzeptionell an Rangsystemen aus kompetitiven Spielen wie League of Legends. Es ermöglicht eine zusätzliche Einteilung der Spieler in definierte Leistungsstufen.

### Punkteranglisten

Neben ELO-Systemen können klassische Punkteranglisten angelegt werden, beispielsweise für Turnierserien oder Vereinsmeisterschaften.

Die Punktevergabe lässt sich an die Anforderungen der jeweiligen Rangliste anpassen. Mögliche Bestandteile sind:

- Punkte für die Teilnahme an Turnieren
- Zusatzpunkte für Siege
- Bonuspunkte für Bestleistungen
- Weitere individuell definierte Wertungsbestandteile

Damit lassen sich unterschiedliche Wettbewerbe abbilden, ohne für jede Turnierserie ein eigenes Verwaltungssystem zu benötigen.

### Spieler und Turniere zuweisen

Innerhalb einer Rangliste können Spieler und Turniere zugeordnet werden. Die Ergebnisse der zugewiesenen Turniere bilden die Grundlage für die jeweilige Ranglistenberechnung.

### Chronologische Berechnung und historische Korrektheit

Die ELO-Entwicklung wird chronologisch anhand der zugeordneten Turniere und Ergebnisse berechnet.

Werden Turniere nachträglich importiert oder zeitlich zwischen bereits vorhandene Spieltage eingefügt, kann die Rangliste unter Berücksichtigung der zeitlichen Reihenfolge neu berechnet werden. Dadurch lassen sich auch historische Ranglistenstände nachvollziehen.

### Detaillierter Ranglistenverlauf

Beim Öffnen einer Rangliste werden die zugehörigen Spieler mit ihren aktuellen Wertungen angezeigt. Eine dedizierte Ansicht für die Punkteentwicklung nach einzelnen Spieltagen/Turnieren ist ebenfalls vorhanden.

Für einzelne Spieler steht ein detaillierter Verlauf zur Verfügung, der unter anderem folgende Informationen umfasst:

- ELO- beziehungsweise Punkteentwicklung über die Spieltage
- Wertungsveränderungen durch einzelne Begegnungen
- Verlauf über den ausgewählten Zeitraum
- Interaktiver Graph zur visuellen Analyse der Entwicklung

Damit können sowohl langfristige Trends als auch Veränderungen nach einzelnen Turnieren und Spielen untersucht werden.

---

## ⚙️ Einstellungen und Verwaltung

Die Einstellungen sind über das Zahnradsymbol im Hauptmenü erreichbar und in mehrere Bereiche unterteilt.

### Daten

Der Datenbereich bündelt wichtige Funktionen zur Verwaltung und Absicherung der Anwendungsdaten.

Dazu gehören:

- Backups erstellen
- Supabase-Synchronisation aktivieren oder deaktivieren
- Einloggen und Registrieren
- Daten zurücksetzen

### Updates

Die integrierte Updateverwaltung bietet Zugriff auf das Git-Repository und ermöglicht die Suche nach neuen Versionen.

Verfügbare Updates können direkt aus der Anwendung heruntergeladen und installiert werden.

### Darstellung

Im Darstellungsbereich können visuelle Einstellungen angepasst werden.

Dazu gehören:

- Seitenlogo auswählen beziehungsweise ändern
- Theme auswählen
- Dark Mode aktivieren

### Werkzeuge und Verwaltung

Dieser Bereich bündelt zusätzliche Integrationen und Funktionen für Administration, Entwicklung und Tests.

#### Govee-Lichthub

Über eine API-Integration können unterstützte smarte Beleuchtungssysteme von Govee gesteuert werden.

Die Funktion ist insbesondere für den Einsatz in Vereinsheimen vorgesehen, in denen Beleuchtung zentral über die Anwendung bedient werden soll.

#### Entwicklertools

Die Anwendung enthält Werkzeuge zum Testen und Durchspielen von Turnierformaten. Damit lassen sich Konfigurationen überprüfen und Abläufe unter kontrollierten Bedingungen nachvollziehen.

#### Konfiguration des Turnierformfinders

Die Parameter des Turnierformfinders können angepasst werden, um die Berechnung der Turnierdauer und die Auswahl geeigneter Turnierformate auf unterschiedliche Anforderungen abzustimmen.

Dazu gehören insbesondere Einstellungen für die zeitliche Kalkulation und die Formfindung.

---

## ☁️ Datenverwaltung und Synchronisation

DartTournamentPro unterstützt eine lokale Datenverwaltung sowie eine optionale Synchronisation über Supabase.

Bei aktivierter Synchronisation werden unterstützte Daten zwischen verbundenen Geräten abgeglichen. Dadurch können beispielsweise Turniere, Spielerinformationen und Ranglisten mit demselben Benutzerkonto auf mehreren Geräten verwendet werden.

Die Synchronisation kann in den Einstellungen aktiviert oder deaktiviert werden.

Backups und die Möglichkeit zum Zurücksetzen der Daten sind ebenfalls im Datenbereich integriert.

**Hinweis:** Welche Daten lokal oder über Supabase gespeichert werden und welche Funktionen ohne Verbindung verfügbar sind, hängt von der jeweiligen Implementierung und Konfiguration der Anwendung ab.

---

## 🔗 Integrationen und Schnittstellen

DartTournamentPro verbindet die Turnierverwaltung mit weiteren Diensten und Werkzeugen aus dem Darts- und Vereinsumfeld.

| Integration | Verwendungszweck |
|---|---|
| **Supabase** | Cloud-Datenbank und Synchronisation |
| **Challonge** | Import von Turnieren und Zuordnung historischer Spielergebnisse |
| **Autodarts** | Hinterlegung von Spielernamen und Kennungen |
| **Scolia** | Verwaltung von Spielerkennungen |
| **3K Darts** | Hinterlegung von Spielerkennungen |
| **Govee** | Steuerung kompatibler Beleuchtung über eine API |
| **Git-Repository** | Zugriff auf den Quellcode und Bereitstellung von Updates |

Die Verfügbarkeit einzelner Funktionen hängt von der Konfiguration, den erforderlichen Zugangsdaten und den jeweiligen Schnittstellen ab.

---

## 🚀 Projektziel

DartTournamentPro verfolgt das Ziel, die Organisation des Dartspielbetriebs in einer zentralen Anwendung zu bündeln.

Statt Turniere, Spielerdaten, Ranglisten und Statistiken getrennt verwalten zu müssen, verbindet die Anwendung diese Bereiche miteinander. Ergebnisse aus Turnieren können dadurch langfristig für Spielerprofile, Ranglisten und statistische Auswertungen genutzt werden.

Der modulare Aufbau ermöglicht sowohl den Einsatz bei einzelnen Hobbyturnieren als auch die kontinuierliche Verwaltung eines Vereins mit regelmäßigen Turnieren, unterschiedlichen Ranglistensystemen und langfristigen Spielerdaten.

**DartTournamentPro – von der Turnierplanung bis zur langfristigen Leistungsanalyse.**
