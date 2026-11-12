part of '../../../tournament_workspace.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.homeOverviewService});

  final HomeOverviewService? homeOverviewService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _tournamentStorage = TournamentStorage();
  int _activityRevision = 0;

  void _refreshActivity() {
    if (!mounted) return;
    setState(() => _activityRevision++);
  }

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
      'Freundschafts- & Ligaspiele',
      Icons.sports,
      () => _open(const TournamentHomePage(leagueMatchesOnly: true), 2),
    ),
    SportDestination(
      'Spielerkatalog',
      Icons.groups_outlined,
      () => _open(const PlayersPage(), 3),
    ),
    SportDestination(
      'Statistiken',
      Icons.bar_chart_outlined,
      () => _open(const PlayersPage(statisticsOnly: true), 4),
    ),
    SportDestination(
      'Ranglisten',
      Icons.leaderboard_outlined,
      () => _open(RankingsPage(onOpenTournament: _openTournamentById), 5),
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
    _refreshActivity();
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
      _refreshActivity();
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

  void _openSettings() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
  Widget _shell(Widget page, int selected) => SportAppShell(
    destinations: _destinations,
    selected: selected,
    child: page,
  );
  Future<void> _createTournament() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _shell(const TournamentCreationPage(skipEntryChoices: true), 0),
      ),
    );
    _refreshActivity();
  }

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
          const SizedBox(height: 20),
          HomeActivityPanel(
            key: ValueKey(_activityRevision),
            service: widget.homeOverviewService,
            onOpenTournament: _openTournamentById,
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

enum _TournamentListingKind { all, ranking, normal }

class TournamentHomePage extends StatefulWidget {
  const TournamentHomePage({
    super.key,
    this.storage,
    this.leagueMatchesOnly = false,
    this.loadRankings,
  });

  final TournamentStorage? storage;
  final bool leagueMatchesOnly;
  final Future<List<LocalRanking>> Function()? loadRankings;

  @override
  State<TournamentHomePage> createState() => _TournamentHomePageState();
}

class _TournamentHomePageState extends State<TournamentHomePage> {
  late final TournamentStorage _storage;
  late Future<List<CreatedTournament>> _tournamentsFuture;
  String _tournamentQuery = '';
  TournamentSortOption _sortOption = TournamentSortOption.date;
  _TournamentListingKind _listingKind = _TournamentListingKind.all;
  String? _rankingFilter;
  int? _yearFilter;
  late Future<List<LocalRanking>> _rankingsFuture;
  bool _isDeletingTournament = false;
  bool _isConvertingTournament = false;

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? TournamentStorage();
    _tournamentsFuture = _storage.loadTournaments();
    _rankingsFuture =
        widget.loadRankings?.call() ?? LocalAppDatabase().loadLocalRankings();
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
    if (widget.leagueMatchesOnly) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (leaguePageContext) => LeagueMatchPage(
            storage: _storage,
            onCreated: (tournament) {
              Navigator.of(leaguePageContext).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => TournamentRunPage(
                    tournament: tournament,
                    tournamentStorage: _storage,
                  ),
                ),
              );
            },
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const TournamentCreationPage(skipEntryChoices: true),
        ),
      );
    }
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
    if (tournament.leagueMatch != null) {
      return TournamentRunPage(
        tournament: tournament,
        tournamentStorage: _storage,
      );
    }
    return TournamentRunPage(
      tournament: tournament,
      tournamentStorage: _storage,
    );
  }

  bool _matchesTournamentQuery(CreatedTournament tournament) {
    if (widget.leagueMatchesOnly != (tournament.leagueMatch != null)) {
      return false;
    }
    if (!widget.leagueMatchesOnly) {
      if (_listingKind == _TournamentListingKind.ranking &&
          !tournament.countsForRanking) {
        return false;
      }
      if (_listingKind == _TournamentListingKind.normal &&
          tournament.countsForRanking) {
        return false;
      }
      if (_rankingFilter != null &&
          !tournament.rankingIds.contains(_rankingFilter)) {
        return false;
      }
      if (_yearFilter != null &&
          (tournament.tournamentDate ?? tournament.createdAt).toLocal().year !=
              _yearFilter) {
        return false;
      }
    }
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

  List<GroupMatch> _matchesWithTimestamps(CreatedTournament tournament) {
    final matches = <GroupMatch>{};
    for (final stage in tournament.runStages) {
      if (stage is KnockoutTournamentRunStage) {
        matches.addAll(stage.matches);
      } else if (stage is GroupTournamentRunStage) {
        for (final group in stage.groups) {
          matches
            ..addAll(group.matches)
            ..addAll(group.knockoutRounds.expand((round) => round))
            ..addAll(group.placementMatches);
        }
      }
    }
    return matches
        .where((match) => match.startedAt != null || match.finishedAt != null)
        .toList();
  }

  DateTime _shiftTimestampDate(DateTime timestamp, int dayOffset) {
    final local = timestamp.toLocal();
    return DateTime(
      local.year,
      local.month,
      local.day + dayOffset,
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
      local.microsecond,
    );
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
    final previousStartedAt = tournament.startedAt;
    final matches = _matchesWithTimestamps(tournament);
    final previousMatchTimes = {
      for (final match in matches) match: (match.startedAt, match.finishedAt),
    };
    final latestMatchTimestamp = matches
        .expand((match) => [match.startedAt, match.finishedAt])
        .whereType<DateTime>()
        .fold<DateTime?>(null, (latest, timestamp) {
          if (latest == null || timestamp.isAfter(latest)) return timestamp;
          return latest;
        });
    final timestampAnchor =
        latestMatchTimestamp ??
        tournament.finishedAt ??
        tournament.startedAt ??
        tournament.createdAt;
    final dayOffset = DateUtils.dateOnly(
      endTime,
    ).difference(DateUtils.dateOnly(timestampAnchor.toLocal())).inDays;
    final shiftedStart = tournament.startedAt == null
        ? null
        : _shiftTimestampDate(tournament.startedAt!, dayOffset);
    if (shiftedStart != null && endTime.isBefore(shiftedStart)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Das Turnierende muss nach dem Turnierstart liegen.'),
        ),
      );
      return;
    }
    try {
      tournament
        ..startedAt = shiftedStart
        ..finishedAt = endTime;
      for (final match in matches) {
        if (match.startedAt != null) {
          match.startedAt = _shiftTimestampDate(match.startedAt!, dayOffset);
        }
        if (match.finishedAt != null) {
          match.finishedAt = _shiftTimestampDate(match.finishedAt!, dayOffset);
        }
      }
      await _storage.saveTournament(tournament);
      if (mounted) {
        _reloadTournaments();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Turnier-Enddatum gespeichert.')),
        );
      }
    } catch (error) {
      tournament
        ..startedAt = previousStartedAt
        ..finishedAt = previous;
      for (final entry in previousMatchTimes.entries) {
        entry.key
          ..startedAt = entry.value.$1
          ..finishedAt = entry.value.$2;
      }
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
          title: const Text('Nicht alle Teilnehmer sind zugeordnet'),
          content: Text(
            '$unassignedCount Challonge-Teilnehmer werden als lokale Teilnehmer '
            'übernommen. Ihre Begegnungen bleiben standardmäßig ohne '
            'Ranglistenwertung. In den Ranglisteneinstellungen kannst du '
            '„Begegnungen mit lokalen Teilnehmern werten“ aktivieren, damit sie '
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

  Widget _sortDropdown() => DropdownButtonFormField<TournamentSortOption>(
    key: const ValueKey('tournament-sort'),
    initialValue: _sortOption,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'Sortierung'),
    onChanged: (option) {
      if (option != null) setState(() => _sortOption = option);
    },
    items: [
      for (final option in TournamentSortOption.values)
        DropdownMenuItem(value: option, child: Text(option.label)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.leagueMatchesOnly ? 'Freundschafts- & Ligaspiele' : 'Turniere',
        ),
      ),
      bottomNavigationBar: _isDeletingTournament
          ? const LinearProgressIndicator(
              semanticsLabel: 'Turnier wird gelöscht',
            )
          : null,
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
                  widget.leagueMatchesOnly
                      ? 'Meine Freundschafts- & Ligaspiele'
                      : 'Meine Turniere',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                if (tournaments != null)
                  Text(
                    widget.leagueMatchesOnly
                        ? '${tournaments.where((item) => item.leagueMatch != null).length} gespeicherte Begegnungen'
                        : '${tournaments.where((item) => item.leagueMatch == null).length} gespeicherte Turniere',
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
                const SizedBox(height: 12),
                if (tournaments != null) ...[
                  Text(
                    widget.leagueMatchesOnly
                        ? 'Sortierung'
                        : 'Sortierung & Filter',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (widget.leagueMatchesOnly)
                    AdaptiveTileLayout(children: [_sortDropdown()])
                  else
                    FutureBuilder<List<LocalRanking>>(
                      future: _rankingsFuture,
                      builder: (context, rankingSnapshot) {
                        final years =
                            tournaments
                                .where((item) => item.leagueMatch == null)
                                .map(
                                  (item) =>
                                      (item.tournamentDate ?? item.createdAt)
                                          .toLocal()
                                          .year,
                                )
                                .toSet()
                                .toList()
                              ..sort((a, b) => b.compareTo(a));
                        return AdaptiveTileLayout(
                          minTileWidth: 170,
                          children: [
                            _sortDropdown(),
                            DropdownButtonFormField<_TournamentListingKind>(
                              key: const ValueKey('tournament-kind-filter'),
                              initialValue: _listingKind,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Turnierart',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: _TournamentListingKind.all,
                                  child: Text('Alle Turniere'),
                                ),
                                DropdownMenuItem(
                                  value: _TournamentListingKind.ranking,
                                  child: Text('Nur Ranglistenturniere'),
                                ),
                                DropdownMenuItem(
                                  value: _TournamentListingKind.normal,
                                  child: Text('Nur normale Turniere'),
                                ),
                              ],
                              onChanged: (value) => setState(
                                () => _listingKind =
                                    value ?? _TournamentListingKind.all,
                              ),
                            ),
                            DropdownButtonFormField<int?>(
                              key: const ValueKey('tournament-year-filter'),
                              initialValue: _yearFilter,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Jahr',
                              ),
                              items: [
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('Alle Jahre'),
                                ),
                                for (final year in years)
                                  DropdownMenuItem<int?>(
                                    value: year,
                                    child: Text('$year'),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _yearFilter = value),
                            ),
                            if (rankingSnapshot.hasError)
                              Text(
                                'Ranglistenfilter konnten nicht geladen werden: ${rankingSnapshot.error}',
                              )
                            else
                              DropdownButtonFormField<String?>(
                                key: const ValueKey(
                                  'tournament-ranking-filter',
                                ),
                                initialValue: _rankingFilter,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Rangliste',
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Alle Ranglisten'),
                                  ),
                                  for (final ranking
                                      in rankingSnapshot.data ?? const [])
                                    DropdownMenuItem<String?>(
                                      value: ranking.id,
                                      child: Text(ranking.name),
                                    ),
                                ],
                                onChanged: (value) =>
                                    setState(() => _rankingFilter = value),
                              ),
                          ],
                        );
                      },
                    ),
                ],
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
                  label: Text(
                    widget.leagueMatchesOnly
                        ? 'Freundschafts- oder Ligaspiel anlegen'
                        : 'Turnier erstellen',
                  ),
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
