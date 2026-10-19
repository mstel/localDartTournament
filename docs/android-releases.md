# Android-Updates in mstel/localDartTournament

Die Update-Suche und der manuelle Release-Link der App zeigen auf
`mstel/localDartTournament`. Aus diesem Repository wurden noch keine Tags oder
Releases veröffentlicht; diese Übernahme erstellt ausdrücklich keinen Release.

Der bisherige Release-Workflow wurde nicht übernommen: Er war an den Branch
`Trainingsbetrieb-DCUH` gebunden und enthielt Build-Konfiguration für das
Supabase- und Firebase-Projekt des bisherigen Repositories. Ein eigener
Release-Ablauf muss später mit den Einstellungen dieses Projekts eingerichtet
werden.

## Voraussetzungen für einen späteren Release

- Für Updates bestehender Android-Installationen muss derselbe Release-Keystore
  wie bisher verwendet werden. Ohne denselben Signaturschlüssel kann Android
  kein In-place-Update installieren. Keystore und Passwörter gehören nicht in
  Git, Issues oder Release-Assets.
- Die Android-Buildnummer nach `+` muss mit jeder Veröffentlichung steigen.
  Veröffentlichte Tags verwenden das Format `vX.Y.Z+N`; das APK-Asset heißt
  `dart-turnier-android.apk`.
- Build- und Update-Konfigurationen müssen die Supabase-URL und den
  Publishable-Key des eigenen Projekts verwenden, nicht Werte aus
  `ProfGans/DartTunier`.
- Vor einer Installation ein externes Backup erstellen. Android muss die
  bestehende App mit derselben Paket-ID und Signatur aktualisieren; die App
  prüft außerdem die höhere Buildnummer, Asset-Größe und SHA-256-Prüfsumme.

Vor einem Release sind ein eigener GitHub-Actions-Workflow, die nötigen
Repository-Secrets und ein Geräte-/Upgrade-Test einzurichten. Bis dahin
veröffentlicht oder installiert diese Repository-Kopie keine neue Version.
