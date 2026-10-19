# Android-Updates in mstel/localDartTournament

Die Update-Suche und der manuelle Release-Link der App zeigen auf
`mstel/localDartTournament`. Tag-Releases veröffentlichen Windows-, Linux- und
signierte Android-Pakete. Das Android-APK heißt `dart-turnier-android.apk`;
seine Prüfsumme ist in `SHA256SUMS` enthalten.

Für ein bestehendes GitHub-Release kann der Android-Workflow manuell mit dessen
Tag gestartet werden. Er baut den APK aus genau diesem Tag und ergänzt das
Asset sowie die aktualisierte Prüfsummendatei, ohne Desktop-Assets neu zu
veröffentlichen.

## Voraussetzungen für einen späteren Release

- Der Android-Upload-Keystore wird in Actions-Secrets gehalten
  (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
  `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`). Keystore und Passwörter gehören
  nicht in Git, Issues oder Release-Assets.
- Der neu eingerichtete Upload-Keystore ist nicht der bisherige
  Signaturschlüssel. Android kann dieses APK daher nicht über eine Installation
  mit der alten Signatur installieren. Die alte App muss zuerst deinstalliert
  und das neue APK anschließend frisch installiert werden; dabei wird lokaler
  App-Speicher gelöscht.
- Die Android-Buildnummer nach `+` muss mit jeder Veröffentlichung steigen.
  Veröffentlichte Tags verwenden das Format `vX.Y.Z+N`; das APK-Asset heißt
  `dart-turnier-android.apk`.
- Der Android-Build verwendet die Supabase-Konfiguration aus dem Ziel-Repository
  und nicht die des früheren Repositories. Mit derselben Supabase-URL und
  demselben Konto bleiben dort gespeicherte Daten erreichbar; lokale Anmeldung
  kann nach der Neuinstallation erneut erforderlich sein.
- Vor einer Installation ein externes Backup erstellen. Android muss die
  APK-Signatur, Asset-Größe und SHA-256-Prüfsumme prüfen.

Vor dem produktiven Einsatz APK-Installation, Anmeldung und Cloud-Datenzugriff
auf dem Zielgerät manuell prüfen.
