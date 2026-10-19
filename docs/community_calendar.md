# Community-Kalender

Der Menüpunkt „Kalender“ zeigt ein Monatsraster von Montag bis Sonntag mit einer Terminliste darunter. Heute ist umrandet; Tagesfelder zeigen auf breiten Ansichten Turniernamen, auf kleinen Ansichten die Terminanzahl. Ein Klick auf einen Tag filtert die Liste, „Alle Termine im Monat“ hebt den Filter auf. Monatswechsel löschen die Tagesauswahl; „Heute“ wählt den heutigen Tag. Beim Eintragen oder Kopieren wird ein ausgewähltes Datum mit 18 Uhr vorbelegt und bleibt im Formular änderbar. Die Monatsansicht nutzt bereits geladene Daten ohne weitere Serverabfragen.

Mitglieder mit `create_tournaments` können Termine mit Datum, Uhrzeit, Ort und Hinweisen anlegen und kopieren. Änderungen benötigen `edit_tournaments`, Löschen benötigt `delete_tournaments`. Beim Löschen werden Erinnerungen mit entfernt.

„Termin eintragen“ legt zusätzlich freie Termine an, etwa Training, Feiern oder Besprechungen. Das Formular enthält Name, Datum/Uhrzeit, Ort und Beschreibung ohne Turniereinstellungen. Bearbeiten, Kopieren, Löschen und Erinnerungen verwenden dieselben Rechte und Abläufe wie Turniertermine. Freie Termine bieten keine Turniervorlagen oder Turniererstellung an.

Die Terminart liegt in der vorhandenen JSON-Spalte `settings`: `calendarVersion: 2`, `eventType: tournament|appointment`. Das unabhängige Vorlagenschema `version: 1` bleibt erhalten; freie Termine speichern keine Turnierkonfiguration. Bestehende Einträge ohne Kalendermetadaten werden beim Lesen als Turniere übernommen. Die aktuelle Datenbank akzeptiert das additive Format ohne SQL-Migration; ältere App-Versionen kennen die neue Terminart nicht und sollten für die Terminverwaltung aktualisiert werden.

Vorlagen speichern eine versionierte Konfiguration: Boards, geplante Teilnehmerzahl, Modus und Spielformat der ersten Etappe, Ranglistenwertung und Ranglisten-IDs. Keine Teilnehmer, Ergebnisse oder Gerätezuweisungen werden übernommen. Vorlagen lassen sich im Terminformular speichern und auswählen; vorhandene Community-Turniere bieten „Als Kalender-Vorlage speichern“. „Turnier aus Vorlage erstellen“ öffnet die normale Turniererstellung mit diesen Einstellungen. Teilnehmer und zusätzliche Etappen werden dort ergänzt. Ein Termin ist noch kein gestartetes Turnier.

Termine sind UTC-Zeitpunkte und werden lokal im 24-Stunden-Format angezeigt. Kopieren erzeugt eine neue Termin-ID, ohne den Ursprung zu verändern. Bereits geladene Kalenderdaten werden accountbezogen lokal zwischengespeichert. Speichern von Terminen, Vorlagen und Erinnerungen erfordert eine Verbindung; fehlgeschlagene Formulare behalten ihre Eingaben. Dies ist kein Offline-Schreibjournal; das bestehende Turnier-Offline-Journal bleibt unverändert.

## Persönliche Erinnerungen

Jedes Mitglied entscheidet selbst pro Termin: aus, zum Beginn, 15/30 Minuten, 1/2 Stunden, 1 Tag oder 1 Woche vorher. Die Erinnerung geht an die eigenen registrierten Android-Geräte. Beim Kopieren werden persönliche Erinnerungen nicht mitkopiert. Austritt aus der Community entfernt die Abonnements. Windows und andere Plattformen können Termine verwalten, der vorhandene Push-Empfänger unterstützt Android.

`202610030003_community_calendar.sql` ist am 03.10.2026 in Supabase eingespielt. RLS schützt Termine, Vorlagen und persönliche Einstellungen; Push-Tokens und Zustellreservierungen bleiben serverseitig. Die Edge Function `calendar-reminders` ist bereitgestellt. Sie benötigt `FIREBASE_SERVICE_ACCOUNT_JSON` mit dem berechtigten Service-Account des in App
und Edge Function konfigurierten Firebase-Projekts. Dieses Secret fehlt zum
Implementierungszeitpunkt weiterhin im Projekt. Private Schlüssel direkt in
den Supabase Edge Function Secrets hinterlegen, niemals in Git oder in den
App-Build.

`calendar_reminder_schedule.sql` richtet einen minütlichen Cron-Job ein. Beim Einspielen wird `__PUBLIC_ANON_JWT__` durch den bestehenden öffentlichen Legacy-Anon-JWT dieses Projekts ersetzt, NICHT durch einen Service-Role-Schlüssel. Die Gateway-JWT-Prüfung bleibt aktiv. Zusätzlich prüft die Funktion den internen Scheduler-Schlüssel, der ausschließlich in der geschützten Datenbanktabelle liegt. Die automatische Freigabeprüfung lehnte das Abschalten der Gateway-Prüfung ab; die realisierte Lösung behält sie bei und erfüllt beide Authentifizierungsprüfungen.

Der Cron ruft die Funktion nur bei fälligen Abonnements mit registrierten Geräten auf. FCM-Authentifizierung erfolgt vor der Zustellreservierung, damit fehlende Konfiguration keine Erinnerung verbraucht. Reserviert werden maximal 50 Zustellungen pro Aufruf, atomar gegen Doppelversand. Vor dem Senden werden Termin, Abonnement, Mitgliedschaft und Gerätebesitzer erneut geprüft. Überholte Termine werden spätestens 15 Minuten nach Beginn nicht mehr versendet. FCM-Nachrichten verfallen spätestens zu diesem Zeitpunkt. `accepted` bedeutet von FCM angenommen, nicht eine bestätigte Anzeige am Handy. Bei unklaren Provider-Zeitüberschreitungen wird nicht automatisch erneut gesendet; damit werden mögliche Doppelbenachrichtigungen vermieden. Bei sehr großen Communities kann die 50er-Batchgröße zu Verzögerungen führen.

Kein echter Zustelltest an Nutzergeräten wurde ausgeführt. Die Android-Empfangsberechtigung und Firebase-Einrichtung bleiben Voraussetzungen.

Der Zeitplan ist auf dem Server eingerichtet. Ein direkter Serveraufruf mit beiden Authentifizierungsprüfungen lieferte HTTP 503 mit `push_not_configured`; damit ist der fehlende Firebase-Service-Account als verbleibender Zustellblocker bestätigt. Bei dieser Prüfung wurden keine Nachrichten versendet.

## Prüfung

- `node tool/test_community_calendar.mjs`: RLS, persönliche Abonnements, Zeitpunkt, Deduplizierung, Verschieben, Austritt und Löschen.
- `node tool/test_calendar_worker.mjs`: Worker-Authentifizierung, fehlende Konfiguration, Providerfehler, Versand-Payload und Abbruch bei gelöschtem Termin; alle Providerzugriffe simuliert.
- `flutter test test/community_calendar_test.dart test/community_menu_test.dart test/tournament_simulation_matrix_test.dart test/adaptive_layout_test.dart test/responsive_pages_test.dart`.
- Responsive Tests einschließlich 360×800, 800×600, 1440×900 und 200 % Schrift; gerenderte Vorschauen unter `build/layout_previews/CalendarPreview_*`.

Technische Referenzen: [Supabase – zeitgesteuerte Funktionen](https://supabase.com/docs/guides/functions/schedule-functions), [Firebase – Gültigkeitsdauer einer Nachricht](https://firebase.google.com/docs/cloud-messaging/customize-messages/setting-message-lifespan).
