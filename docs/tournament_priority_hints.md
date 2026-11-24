# Prioritätshinweise im Turnierbetrieb

Die geräteweiten Hinweiswerte werden unter **Einstellungen → Werkzeuge &
Verwaltung → Hinweiseinstellungen** gespeichert. Nicht vorhandene Werte in
bestehenden Installationen verwenden weiterhin die Standardwerte von zwei
Partien pro Spieler und drei Partien pro Gruppe. Die prozentuale Berechnung ist
standardmäßig ausgeschaltet.

Im absoluten Modus bleibt die bisherige Logik bestehen: Gruppen werden nach
absolut gespielten Begegnungen und Spieler nach ihren absolvierten Partien
verglichen.

Im Prozentmodus wird der Gruppenfortschritt als absolvierte Begegnungen geteilt
durch alle für diese Gruppe angesetzten Begegnungen berechnet. Der Abstand zur
fortgeschrittensten Gruppe wird anschließend in „Partien der längsten
Gruppenspielplan-Größe“ umgerechnet. Bei Gruppenspielplänen von 10 und 6
Begegnungen entsprechen beispielsweise 30 Prozentpunkte Rückstand drei
Partien. Damit bleibt die konfigurierbare Schwelle vergleichbar, ohne Gruppen
mit gleichem relativen Fortschritt wegen ihrer unterschiedlichen Größe zu
priorisieren. Die Spielerschwelle bleibt in beiden Modi absolut.

Seit 4.0 verwenden feste und dynamische Spielpläne dieselbe Prioritäts-Engine.
Spielerkollisionen werden zuerst hart ausgeschlossen; danach entscheiden die
Wartezeit seit dem letzten Spielende, der Gruppenfortschritt (abgeschlossen =
1, laufend = 0,5, prognostiziert = 0,25), die absolute Restarbeit, die
Spielbelastung, die verbleibenden Partien und die Ursprungsreihenfolge. Laufende
Partien blockieren ihre Spieler und Boards auch dann, wenn sie in einer anderen
Phase laufen.

Neue Turniere verwenden standardmäßig diese Tie-Breaker-Reihenfolge:
Matchpunkte, Leg-Differenz, gewonnene Legs, direkter Vergleich. Eine unter
**Tie Breaker Standardwerte** gespeicherte benutzerdefinierte Reihenfolge wird
für die nächsten Turniere übernommen; gespeicherte Turniere behalten ihre
eigene Reihenfolge.
