# Android-Push

Der Hauptmenü-Button **Push-Nachricht senden** wird nur angezeigt, wenn der
angemeldete Supabase-Account serverseitig als Sender freigeschaltet ist.
Anzeigenamen sind keine Berechtigungen. Android kann Push empfangen; Desktop
kann die Versandseite bedienen. Windows-, iOS- und Web-Empfang sind nicht
implementiert.

## Projektkonfiguration

Die Empfänger, Berechtigungen und Zustellreservierungen liegen im konfigurierten
Supabase-Projekt. Für Android benötigt die App zusätzlich eine
`google-services.json`, die nicht eingecheckt wird. Die aktuelle Implementierung
prüft die Firebase-Projekt-ID `darttunier-6f866`; die Edge Function
`send-app-push` erwartet dieselbe ID. Eine andere Firebase-Instanz muss sowohl
in der App als auch in der Edge Function angepasst werden.

Für das konfigurierte Firebase-Projekt müssen Cloud Messaging und ein
berechtigter Service-Account eingerichtet sein. Den privaten Schlüssel als
Supabase-Edge-Secret `FIREBASE_SERVICE_ACCOUNT_JSON` hinterlegen, niemals in
Git, App-Builds oder Issues. Die Datenbankmigration
`202610020003_app_push.sql` muss im eigenen Supabase-Projekt ausgeführt und die
gewünschten Sender-IDs müssen dort explizit freigeschaltet werden.

Die Release-Automatisierung für `mstel/localDartTournament` ist noch nicht
eingerichtet. Ohne Firebase-App-Konfiguration bleibt die App startfähig, Push
ist dann aber nicht verfügbar.

## Ablauf und Grenzen

Die Empfänger wählen auf Android **Push-Empfang aktivieren**, vergeben einen
Gerätenamen und erlauben Benachrichtigungen. Dafür ist eine Online-Anmeldung
erforderlich. Android-Force-Stop in den Systemeinstellungen verhindert Push bis
zum nächsten manuellen App-Start.

Auswahl einzelner registrierter Geräte; höchstens 100 pro Anfrage. Titel bis
80, Nachricht bis 1000 Zeichen. Die Anzeige unterscheidet Übergabe an FCM von
tatsächlicher Anzeige auf dem Gerät. Registrierungen älter als 90 Tage werden
ausgeblendet; beim App-Start bzw. Wiederaufnehmen werden sie erneuert.

Die App übergibt ausschließlich Geräte-IDs; Tokens bleiben serverseitig. Nur
Serverrollen verwalten die Senderliste. Ungültige FCM-Tokens werden entfernt.
Die Datenbankreservierung verhindert doppelte Sendungen bei Wiederholung. Bei
einem Serverabbruch nach der Reservierung bleibt die Anfrage auf `processing`;
automatische Wiederholung wird vermieden, da ein Teil bereits zugestellt sein
kann.

## Prüfung

`flutter test test/app_push_test.dart` prüft Sichtbarkeit, große Schrift,
responsive Breiten und Wiederholungen. Ein echter Firebase-/Supabase-
Zustelltest muss nach der Einrichtung mit einem ausdrücklich ausgewählten
Testgerät erfolgen.
