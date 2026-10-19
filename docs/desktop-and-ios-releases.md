# Desktop- und iOS-Veröffentlichungen

Der Workflow `.github/workflows/ci.yml` prüft Analyse und vollständige Tests
sowie Desktop-Builds für Windows 2022 x64, Ubuntu 22.04 x64 und Ubuntu
22.04 ARM64. Ein Tag `vX.Y.Z+N`, der exakt zur `version` in `pubspec.yaml`
passt, erzeugt versionsgekennzeichnete Desktop-Pakete samt
`data/update-manifest.json` und ein signiertes Android-APK. Der GitHub-Release
wird erst veröffentlicht, wenn Analyse, Tests und alle Plattform-Builds
erfolgreich waren.

Ein Release enthält die Windows-x64-, Linux-x64- und Linux-ARM64-Pakete, ein
signiertes Android-APK sowie eine `SHA256SUMS`-Datei zur Integritätsprüfung.
Android-Signatur und Neuinstallation sind in
[`android-releases.md`](android-releases.md) beschrieben.
Release-Builds verbinden sich mit dem eigenen Supabase-Projekt und verwenden
die Actions-Variable `SUPABASE_PUBLISHABLE_KEY`.
macOS und iOS benötigen zusätzlich eigene Signierungs- und
Provisionierungskonfiguration. Zertifikate, Profile und Zugangsdaten gehören
ausschließlich in eine geschützte Release-Umgebung und niemals ins Repository.

CI-Builds belegen Kompilierbarkeit, nicht Installation oder Upgrade auf realen
Geräten. Vor dem produktiven Einsatz sind Pakete, Backup/Wiederherstellung und
Update mit Neustart auf den Zielsystemen manuell zu prüfen.

macOS und iOS benötigen zusätzlich eigene Signierungs- und
Provisionierungskonfiguration. Zertifikate, Profile und Zugangsdaten gehören
ausschließlich in die geschützte Release-Umgebung und niemals ins Repository.

Technische Plattformreferenzen:
- https://docs.flutter.dev/deployment/ios
- https://docs.flutter.dev/deployment/macos
- https://docs.flutter.dev/platform-integration/linux/setup
