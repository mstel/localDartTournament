# Gruppen per Text auslosen

Die Turnier-Gruppenverwaltung und das Auslosungsrad verwenden dasselbe
Zwischenablageformat:

```text
Gruppen: 2

Gruppe A:
Spieler 1
Spieler 2

Gruppe B:
Spieler 3
Spieler 4
```

In der Gruppenverwaltung lässt sich die aktuelle Zuweisung als Text kopieren.
Im Auslosungsrad kann dieser Text übernommen werden; Gruppenzahl, Überschriften,
Spielernamen und Gruppengrößen werden daraus geladen. Nach der Ziehung kopiert
das Rad die neue Verteilung wieder in diesem Format.

Zurück in der Gruppenverwaltung müssen Gruppenzahl, Gruppengrößen und
Spielernamen übereinstimmen. Andernfalls bleibt die aktuelle Einteilung
unverändert. Sind Namen im lokalen Spielerkatalog vorhanden, kann für den
Import gewählt werden, ob die Katalogprofile oder lokale Turnierspieler
verwendet werden sollen. Bei mehrfach vorhandenen Katalognamen wird das Profil
explizit ausgewählt.
