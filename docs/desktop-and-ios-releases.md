# Desktop- und iOS-Veröffentlichungen

Für `mstel/localDartTournament` ist noch kein eigener Release-Workflow
eingerichtet. Der bisherige Workflow wurde nicht übernommen, weil er auf
`Trainingsbetrieb-DCUH` und die Konfiguration des bisherigen Supabase-/Firebase-
Projekts ausgerichtet war. Diese Repository-Übernahme veröffentlicht keine
Pakete und erstellt keine Tags.

Die App enthält bereits Update-Unterstützung für Windows x64 sowie Linux x64
und ARM64. Ein künftiger Workflow muss passende Pakete mit einer
versionierten `data/update-manifest.json` bauen und deren SHA-256-Digest als
GitHub-Release-Assets bereitstellen. Vor einer Veröffentlichung sind die
Pakete auf den jeweiligen Zielsystemen sowie Backup/Wiederherstellung und
Update mit Neustart zu prüfen.

macOS und iOS benötigen zusätzlich eigene Signierungs- und
Provisionierungskonfiguration. Zertifikate, Profile und Zugangsdaten gehören
ausschließlich in die geschützte Release-Umgebung und niemals ins Repository.

Technische Plattformreferenzen:
- https://docs.flutter.dev/deployment/ios
- https://docs.flutter.dev/deployment/macos
- https://docs.flutter.dev/platform-integration/linux/setup
