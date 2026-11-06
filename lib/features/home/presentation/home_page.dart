part of '../../../tournament_workspace.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _tournamentStorage = TournamentStorage();

  List<SportDestination> get _destinations => [
    SportDestination(
      'Übersicht',
      Icons.home_outlined,
      () => Navigator.of(context).popUntil((route) => route.isFirst),
    ),
    SportDestination(
      'Turniere',
      Icons.emoji_events_outlined,
      () => _open(const TournamentHomePage(), 1),
    ),
    SportDestination(
      'Spieler',
      Icons.groups_outlined,
      () => _open(const PlayersPage(), 2),
    ),
    SportDestination(
      'Statistiken',
      Icons.bar_chart_outlined,
      () => _open(const PlayersPage(statisticsOnly: true), 3),
    ),
    SportDestination(
      'Ranglisten',
      Icons.leaderboard_outlined,
      () => _open(RankingsPage(onOpenTournament: _openTournamentById), 4),
    ),
  ];

  Future<void> _open(Widget page, int selected) async {
    Navigator.of(context).popUntil((route) => route.isFirst);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SportAppShell(
          selected: selected,
          destinations: _destinations,
          child: page,
        ),
      ),
    );
  }

  Future<void> _openTournamentById(String tournamentId) async {
    try {
      final tournaments = await _tournamentStorage.loadTournaments();
      final tournament = tournaments
          .where((item) => item.id == tournamentId)
          .firstOrNull;
      if (tournament == null) {
        throw StateError('Das zugehörige Turnier wurde nicht gefunden.');
      }
      final lastStageIndex = tournament.runStages.length - 1;
      final isComplete =
          lastStageIndex >= 0 &&
          tournament.completedStageIndexes.contains(lastStageIndex);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => isComplete
              ? TournamentResultsPage(tournament: tournament)
              : TournamentRunPage(
                  tournament: tournament,
                  tournamentStorage: _tournamentStorage,
                ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Turnier konnte nicht geöffnet werden: $error'),
          ),
        );
      }
    }
  }

  void _openTournamentArea() => _open(const TournamentHomePage(), 1);
  void _openPlayersArea() => _open(const PlayersPage(), 2);
  void _openSettings() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
  Widget _shell(Widget page, int selected) => SportAppShell(
    destinations: _destinations,
    selected: selected,
    child: page,
  );
  void _createTournament() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _shell(const TournamentCreationPage(), 0),
    ),
  );

  @override
  Widget build(BuildContext context) => _shell(
    Scaffold(
      appBar: AppBar(
        title: const Text('Dart Turnierverwaltung'),
        actions: [
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Einstellungen',
          ),
        ],
      ),
      body: AdaptiveContentList(
        children: [
          SportHero(onTournament: _createTournament),
          const SizedBox(height: 28),
          SportMenuGroup(
            title: 'Spielzentrale',
            actions: [
              SportMenuAction(
                label: 'Turniere',
                icon: Icons.emoji_events_outlined,
                onTap: _openTournamentArea,
              ),
              SportMenuAction(
                label: 'Spieler',
                icon: Icons.groups_outlined,
                onTap: _openPlayersArea,
              ),
              SportMenuAction(
                label: 'Statistiken',
                icon: Icons.bar_chart_outlined,
                onTap: () => _open(const PlayersPage(statisticsOnly: true), 3),
              ),
              SportMenuAction(
                label: 'Ranglisten',
                icon: Icons.leaderboard_outlined,
                onTap: () => _open(
                  RankingsPage(onOpenTournament: _openTournamentById),
                  4,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    0,
  );
}

enum TournamentSortOption {
  date('Turnierdatum'),
  lastModified('Letzte Änderung'),
  alphabetical('Alphabetisch');

  const TournamentSortOption(this.label);
  final String label;
}

class TournamentHomePage extends StatefulWidget {
  const TournamentHomePage({super.key, this.storage});

  final TournamentStorage? storage;

  @override
  State<TournamentHomePage> createState() => _TournamentHomePageState();
}

class _TournamentHomePageState extends State<TournamentHomePage> {
  late final TournamentStorage _storage;
  late Future<List<CreatedTournament>> _tournamentsFuture;
  String _tournamentQuery = '';
  TournamentSortOption _sortOption = TournamentSortOption.date;
  bool _isDeletingTournament = false;
  bool _isConvertingTournament = false;

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? TournamentStorage();
    _tournamentsFuture = _storage.loadTournaments();
  }

  void _reloadTournaments() {
    setState(() {
      _tournamentsFuture = _storage.loadTournaments();
    });
  }

  void _reloadTournamentsWithUpdatedTournament(
    CreatedTournament updatedTournament,
  ) {
    setState(() {
      _tournamentsFuture = _storage.loadTournaments().then(
        (tournaments) => [
          for (final tournament in tournaments)
            tournament.id == updatedTournament.id
                ? updatedTournament
                : tournament,
        ],
      );
    });
  }

  Future<void> _openCreationPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TournamentCreationPage()),
    );
    _reloadTournaments();
  }

  Future<void> _openTournament(CreatedTournament tournament) async {
    final updatedTournament = await Navigator.of(context)
        .push<CreatedTournament>(
          MaterialPageRoute<CreatedTournament>(
            builder: (_) => _tournamentPageFor(tournament),
          ),
        );
    if (!mounted) return;
    if (updatedTournament == null) {
      _reloadTournaments();
    } else {
      _reloadTournamentsWithUpdatedTournament(updatedTournament);
    }
  }

  Future<void> _quickEditTournament(CreatedTournament tournament) async {
    final updatedTournament = await Navigator.of(context)
        .push<CreatedTournament>(
          MaterialPageRoute<CreatedTournament>(
            builder: (_) => TournamentCreationPage(
              tournamentStorage: _storage,
              existingTournament: tournament,
            ),
          ),
        );
    if (!mounted) return;
    if (updatedTournament == null) {
      _reloadTournaments();
    } else {
      _reloadTournamentsWithUpdatedTournament(updatedTournament);
    }
  }

  Widget _tournamentPageFor(CreatedTournament tournament) {
    final lastStageIndex = tournament.runStages.length - 1;
    if (lastStageIndex >= 0 &&
        tournament.completedStageIndexes.contains(lastStageIndex)) {
      return TournamentResultsPage(tournament: tournament, storage: _storage);
    }
    return TournamentRunPage(
      tournament: tournament,
      tournamentStorage: _storage,
    );
  }

  bool _matchesTournamentQuery(CreatedTournament tournament) {
    final query = _tournamentQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    final lastStageIndex = tournament.runStages.length - 1;
    final complete =
        tournament.finishedAt != null ||
        (lastStageIndex >= 0 &&
            tournament.completedStageIndexes.contains(lastStageIndex));
    final searchable = <String>[
      tournament.name,
      complete ? 'abgeschlossen archiv fertig' : 'bereit läuft aktiv',
      (tournament.tournamentDate ?? tournament.createdAt)
          .toLocal()
          .toIso8601String(),
      ...tournament.stages.map((stage) => stage.type),
      ...tournament.players.map((player) => player.name),
    ].join(' ').toLowerCase();
    return searchable.contains(query);
  }

  Future<void> _copyTournament(CreatedTournament tournament) async {
    try {
      final copy = tournament.copy();
      await _storage.saveTournament(copy);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kopie "${copy.name}" erstellt.')));
      _reloadTournaments();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kopieren nicht möglich: $error')),
        );
      }
    }
  }

  Future<void> _editTournamentEndTime(CreatedTournament tournament) async {
    final current = tournament.finishedAt ?? tournament.createdAt;
    final date = await showDatePicker(
      context: context,
      initialDate: current.toLocal(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Turnier-Enddatum auswählen',
      confirmText: 'Weiter',
      cancelText: 'Abbrechen',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current.toLocal()),
      helpText: 'Endzeit auswählen',
      confirmText: 'Speichern',
      cancelText: 'Abbrechen',
    );
    if (time == null || !mounted) return;
    final endTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final previous = tournament.finishedAt;
    if (tournament.startedAt != null &&
        endTime.isBefore(tournament.startedAt!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Das Turnierende muss nach dem Turnierstart liegen.'),
        ),
      );
      return;
    }
    try {
      tournament.finishedAt = endTime;
      await _storage.saveTournament(tournament);
      if (mounted) {
        _reloadTournaments();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Turnier-Enddatum gespeichert.')),
        );
      }
    } catch (error) {
      tournament.finishedAt = previous;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Enddatum konnte nicht gespeichert werden: $error'),
          ),
        );
      }
    }
  }

  Future<void> _convertChallongeTournament(CreatedTournament tournament) async {
    if (_isConvertingTournament) return;
    final archive = tournament.importedArchive;
    if (archive == null) return;
    final unassignedCount = archive.participants
        .where(
          (participant) =>
              (participant['profileId'] as String?)?.isNotEmpty != true,
        )
        .length;
    if (unassignedCount > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Nicht alle Spieler sind zugeordnet'),
          content: Text(
            '$unassignedCount Challonge-Spieler werden als lokale Spieler '
            'übernommen. Ihre Begegnungen bleiben standardmäßig ohne '
            'Ranglistenwertung. In den Ranglisteneinstellungen kannst du '
            '„Begegnungen mit lokalen Spielern Werten“ aktivieren, damit sie '
            'mit 1000 Elo einfließen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Trotzdem konvertieren'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _isConvertingTournament = true);
    try {
      final converted = await ChallongeTournamentConversionService().convert(
        tournament,
      );
      await _storage.saveTournament(converted);
      if (!mounted) return;
      _reloadTournaments();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"${converted.name}" wurde in ein abgeschlossenes Turnier '
            'konvertiert.',
          ),
        ),
      );
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              TournamentResultsPage(tournament: converted, storage: _storage),
        ),
      );
      if (mounted) _reloadTournaments();
    } catch (error) {
      if (mounted) {
        final message = error is FormatException
            ? error.message
            : 'Turnier konnte nicht konvertiert werden: $error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isConvertingTournament = false);
    }
  }

  Future<void> _deleteTournament(CreatedTournament tournament) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Turnier löschen?'),
        content: Text(
          '„${tournament.name}“ wird dauerhaft gelöscht. Möchtest du fortfahren?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingTournament = true);
    try {
      await _storage.deleteTournament(tournament.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Löschen nicht möglich: $error')),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _isDeletingTournament = false);
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${tournament.name} gelöscht.')));
    _reloadTournaments();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Turniere')),
      body: SafeArea(
        child: FutureBuilder<List<CreatedTournament>>(
          future: _tournamentsFuture,
          builder: (context, snapshot) {
            final tournaments = snapshot.data;
            final visibleTournaments = tournaments
                ?.where(_matchesTournamentQuery)
                .toList();
            if (visibleTournaments != null) {
              switch (_sortOption) {
                case TournamentSortOption.date:
                  visibleTournaments.sort((a, b) {
                    final aDate =
                        a.tournamentDate ??
                        a.startedAt ??
                        a.finishedAt ??
                        a.createdAt;
                    final bDate =
                        b.tournamentDate ??
                        b.startedAt ??
                        b.finishedAt ??
                        b.createdAt;
                    return bDate.compareTo(aDate);
                  });
                  break;
                case TournamentSortOption.lastModified:
                  visibleTournaments.sort(
                    (a, b) => b.updatedAt.compareTo(a.updatedAt),
                  );
                  break;
                case TournamentSortOption.alphabetical:
                  visibleTournaments.sort(
                    (a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  );
                  break;
              }
            }

            return AdaptiveContentList(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Meine Turniere',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                if (tournaments != null)
                  Text(
                    '${tournaments.length} gespeicherte Turniere',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ValueListenableBuilder<String>(
                  valueListenable: SupabaseWorkspaceSyncService.status,
                  builder: (context, status, _) => Semantics(
                    liveRegion: true,
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.cloud_sync_outlined),
                        title: Text(status),
                      ),
                    ),
                  ),
                ),
                if (_isDeletingTournament)
                  Semantics(
                    label: 'Turnier wird gelöscht',
                    child: const LinearProgressIndicator(),
                  ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < 520 ||
                        MediaQuery.textScalerOf(context).scale(16) > 20;
                    final label = Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        const Icon(Icons.sort, size: 20),
                        Text(
                          'Sortierung:',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    );
                    final dropdown = SizedBox(
                      width: compact ? constraints.maxWidth : 260,
                      child: DropdownButtonFormField<TournamentSortOption>(
                        initialValue: _sortOption,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Sortierung',
                        ),
                        onChanged: (option) {
                          if (option != null) {
                            setState(() => _sortOption = option);
                          }
                        },
                        items: [
                          for (final opt in TournamentSortOption.values)
                            DropdownMenuItem(
                              value: opt,
                              child: Text(opt.label),
                            ),
                        ],
                      ),
                    );
                    return compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [label, dropdown],
                          )
                        : Row(
                            children: [
                              label,
                              const SizedBox(width: 12),
                              dropdown,
                            ],
                          );
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (value) =>
                      setState(() => _tournamentQuery = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Turniere suchen',
                    hintText: 'Name, Status, Datum oder Modus',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _tournamentQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Suche löschen',
                            onPressed: () => setState(() {
                              _tournamentQuery = '';
                            }),
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _openCreationPage,
                  icon: const Icon(Icons.add),
                  label: const Text('Turnier erstellen'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ChallongeLocalImportPage(),
                      ),
                    );
                    _reloadTournaments();
                  },
                  icon: const Icon(Icons.sync_alt),
                  label: const Text(
                    'Challonge-Turniere importieren / exportieren',
                  ),
                ),
                const SizedBox(height: 20),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData)
                  const LinearProgressIndicator(),
                if (snapshot.hasError && !snapshot.hasData) ...[
                  const Text('Turniere konnten nicht geladen werden.'),
                  TextButton(
                    onPressed: _reloadTournaments,
                    child: const Text('Erneut versuchen'),
                  ),
                ],
                if (tournaments != null && tournaments.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Noch keine Turniere gespeichert.'),
                    ),
                  )
                else if (visibleTournaments != null &&
                    visibleTournaments.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Keine passenden Turniere gefunden.'),
                    ),
                  )
                else if (visibleTournaments != null &&
                    visibleTournaments.isNotEmpty)
                  AdaptiveTileLayout(
                    minTileWidth: 360,
                    children: [
                      for (final tournament in visibleTournaments)
                        TournamentSummaryCard(
                          tournament: tournament,
                          onOpen: () => _openTournament(tournament),
                          onDelete: () => _deleteTournament(tournament),
                          onEditEndTime: () =>
                              _editTournamentEndTime(tournament),
                          onQuickEdit:
                              tournament.startedAt == null &&
                                  tournament.importedArchive == null
                              ? () => _quickEditTournament(tournament)
                              : null,
                          onCopy: () => _copyTournament(tournament),
                          onConvert:
                              tournament.importedArchive != null &&
                                  !tournament
                                      .importedArchive!
                                      .usesNativeLogic &&
                                  !_isConvertingTournament
                              ? () => _convertChallongeTournament(tournament)
                              : null,
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
