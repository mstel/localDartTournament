import '../../../shared/widgets/sport_menu.dart';
import '../../../shared/widgets/sport_page_heading.dart';
import '../../statistics/presentation/local_player_statistics_page.dart';
import '../../statistics/presentation/player_comparison_page.dart';
import '../../rankings/presentation/rankings_page.dart';

import 'package:dart_tournament_manager/shared/widgets/adaptive_content.dart';
import 'package:flutter/material.dart';

import '../../tournaments/data/app_database.dart';

class PlayersPage extends StatefulWidget {
  const PlayersPage({
    super.key,
    LocalAppDatabase? database,
    this.statisticsOnly = false,
  }) : _database = database;

  final LocalAppDatabase? _database;
  final bool statisticsOnly;

  @override
  State<PlayersPage> createState() => _PlayersPageState();
}

class _PlayersPageState extends State<PlayersPage> {
  late final LocalAppDatabase _database;
  late Future<List<PlayerProfile>> _playersFuture;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _database = widget._database ?? LocalAppDatabase();
    _playersFuture = _database.loadPlayerProfiles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reloadPlayers() {
    setState(() {
      _playersFuture = _database.loadPlayerProfiles();
    });
  }

  Future<void> _openPlayerDialog([PlayerProfile? player]) async {
    final result = await showDialog<_PlayerFormResult>(
      context: context,
      builder: (context) => _PlayerDialog(player: player),
    );
    if (result == null) {
      return;
    }

    final metadataJson = PlayerProfile.encodeMetadata(
      nickname: result.nickname,
      birthdate: result.birthdate,
      scoliaId: result.scoliaId,
      autodartsName: result.autodartsName,
      threeKDartsId: result.threeKDartsId,
    );

    if (player == null) {
      await _database.createPlayerProfile(
        firstName: result.firstName,
        lastName: result.lastName,
        country: '',
        city: '',
        dartsSetupJson: metadataJson,
      );
    } else {
      await _database.updatePlayerProfile(
        player.copyWith(
          firstName: result.firstName,
          lastName: result.lastName,
          dartsSetupJson: metadataJson,
        ),
      );
    }

    if (!mounted) {
      return;
    }
    _reloadPlayers();
  }

  Future<void> _deactivatePlayer(PlayerProfile player) async {
    await _database.deactivatePlayerProfile(player.id);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${player.displayName} deaktiviert.')),
    );
    _reloadPlayers();
  }

  Future<void> _challongeLinks(PlayerProfile player) async {
    final links = await _database.loadChallongePlayerLinks();
    final names = links
        .where((row) => row['playerProfileId'] == player.id)
        .map((row) => '${row['challongeName']}')
        .toList();
    if (!mounted) return;
    if (names.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Für diesen Spieler sind keine Challonge-Namen verknüpft.',
          ),
        ),
      );
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Challonge-Verknüpfungen · ${player.displayName}'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final alias in names)
                ListTile(
                  title: Text(alias),
                  trailing: IconButton(
                    tooltip: 'Verknüpfung aufheben',
                    icon: const Icon(Icons.link_off),
                    onPressed: () => Navigator.pop(dialogContext, alias),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fertig'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Verknüpfung aufheben?'),
        content: Text(
          '„$name“ wird nicht länger automatisch ${player.displayName} zugeordnet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Nein'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Ja, aufheben'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _database.deleteChallongePlayerLink(name);
      if (mounted) _challongeLinks(player);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.statisticsOnly ? 'Statistik' : 'Spieler'),
      ),
      floatingActionButton: widget.statisticsOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openPlayerDialog(),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Spieler'),
            ),
      body: SafeArea(
        child: FutureBuilder<List<PlayerProfile>>(
          future: _playersFuture,
          builder: (context, snapshot) {
            final players = snapshot.data ?? const <PlayerProfile>[];
            return AdaptiveContentList(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
              children: [
                SportPageHeading(
                  title: widget.statisticsOnly
                      ? 'Statistiken'
                      : 'Spieler verwalten',
                  subtitle: widget.statisticsOnly
                      ? 'Spieler- und Ranglisten-Statistiken sowie Jahresrückblicke auswerten.'
                      : 'Spielerprofile anlegen und für Turniere vorbereiten.',
                  icon: Icons.groups_outlined,
                ),
                const SizedBox(height: 24),
                if (widget.statisticsOnly) ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.calendar_month_outlined),
                      title: const Text('Jahresrückblick'),
                      subtitle: const Text(
                        'Teilnahmen, Turniersiege, Legs und Bestleistungen je Rangliste oder Spieler auswerten.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const RankingYearReviewPage(),
                        ),
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.compare_arrows_outlined),
                      title: const Text('Spieler vergleichen'),
                      subtitle: const Text(
                        'Spielwerte und Elo-Entwicklung zweier Spieler gegenüberstellen.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PlayerComparisonPage(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (players.isNotEmpty) ...[
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Spieler suchen',
                      hintText: 'Name, Spitzname oder ID eingeben…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val.trim().toLowerCase();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else if (players.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Noch keine Spieler angelegt.'),
                    ),
                  )
                else if (players
                    .where(
                      (p) =>
                          _searchQuery.isEmpty ||
                          p.displayName.toLowerCase().contains(_searchQuery) ||
                          p.nickname.toLowerCase().contains(_searchQuery) ||
                          p.autodartsName.toLowerCase().contains(
                            _searchQuery,
                          ) ||
                          p.scoliaId.toLowerCase().contains(_searchQuery) ||
                          p.threeKDartsId.toLowerCase().contains(_searchQuery),
                    )
                    .isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Keine Spieler für „$_searchQuery“ gefunden.',
                      ),
                    ),
                  )
                else
                  for (final player in players.where(
                    (p) =>
                        _searchQuery.isEmpty ||
                        p.displayName.toLowerCase().contains(_searchQuery) ||
                        p.nickname.toLowerCase().contains(_searchQuery) ||
                        p.autodartsName.toLowerCase().contains(_searchQuery) ||
                        p.scoliaId.toLowerCase().contains(_searchQuery) ||
                        p.threeKDartsId.toLowerCase().contains(_searchQuery),
                  ))
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(_initialsFor(player.displayName)),
                        ),
                        title: Text(player.displayName),
                        subtitle: Text(_subtitleFor(player)),
                        trailing: widget.statisticsOnly
                            ? null
                            : PopupMenuButton<String>(
                                tooltip: 'Spieleraktionen',
                                onSelected: (action) {
                                  if (action == 'edit') {
                                    _openPlayerDialog(player);
                                  }
                                  if (action == 'deactivate') {
                                    _deactivatePlayer(player);
                                  }
                                  if (action == 'statistics') {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            LocalPlayerStatisticsPage(
                                              name: player.displayName,
                                              profileIds: {player.id},
                                            ),
                                      ),
                                    );
                                  }
                                  if (action == 'challonge') {
                                    _challongeLinks(player);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'statistics',
                                    child: SportMenuLabel(
                                      label: 'Profilstatistiken öffnen',
                                      icon: Icons.bar_chart_outlined,
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: SportMenuLabel(
                                      label: 'Spieler bearbeiten',
                                      icon: Icons.edit_outlined,
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'challonge',
                                    child: SportMenuLabel(
                                      label: 'Challonge-Verknüpfungen',
                                      icon: Icons.link,
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'deactivate',
                                    child: SportMenuLabel(
                                      label: 'Spieler deaktivieren',
                                      icon: Icons.arrow_forward_outlined,
                                    ),
                                  ),
                                ],
                              ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => LocalPlayerStatisticsPage(
                              name: player.displayName,
                              profileIds: {player.id},
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _initialsFor(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '?';
    }
    return parts.take(2).map((part) => part[0].toUpperCase()).join();
  }

  String _subtitleFor(PlayerProfile player) {
    final details = <String>[];
    if (player.nickname.isNotEmpty) details.add('„${player.nickname}“');
    if (player.birthdate.isNotEmpty) details.add('Geb.: ${player.birthdate}');
    if (player.autodartsName.isNotEmpty) {
      details.add('Autodarts: ${player.autodartsName}');
    }
    if (player.scoliaId.isNotEmpty) {
      details.add('Scolia: ${player.scoliaId}');
    }
    if (player.threeKDartsId.isNotEmpty) {
      details.add('3k: ${player.threeKDartsId}');
    }
    if (details.isEmpty) return 'Keine weiteren Angaben';
    return details.join(' · ');
  }
}

class _PlayerDialog extends StatefulWidget {
  const _PlayerDialog({this.player});

  final PlayerProfile? player;

  @override
  State<_PlayerDialog> createState() => _PlayerDialogState();
}

class _PlayerDialogState extends State<_PlayerDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _surnameController;
  late final TextEditingController _nicknameController;
  late final TextEditingController _birthdateController;
  late final TextEditingController _scoliaIdController;
  late final TextEditingController _autodartsNameController;
  late final TextEditingController _threeKDartsIdController;

  @override
  void initState() {
    super.initState();
    final player = widget.player;
    _nameController = TextEditingController(text: player?.firstName ?? '');
    _surnameController = TextEditingController(text: player?.lastName ?? '');
    _nicknameController = TextEditingController(text: player?.nickname ?? '');
    _birthdateController = TextEditingController(text: player?.birthdate ?? '');
    _scoliaIdController = TextEditingController(text: player?.scoliaId ?? '');
    _autodartsNameController = TextEditingController(
      text: player?.autodartsName ?? '',
    );
    _threeKDartsIdController = TextEditingController(
      text: player?.threeKDartsId ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _nicknameController.dispose();
    _birthdateController.dispose();
    _scoliaIdController.dispose();
    _autodartsNameController.dispose();
    _threeKDartsIdController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthdate() async {
    DateTime initial = DateTime(2000, 1, 1);
    if (_birthdateController.text.isNotEmpty) {
      final parts = _birthdateController.text.split('.');
      if (parts.length == 3) {
        final d = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final y = int.tryParse(parts[2]);
        if (d != null && m != null && y != null) {
          initial = DateTime(y, m, d);
        }
      }
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      final formatted =
          '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
      setState(() {
        _birthdateController.text = formatted;
      });
    }
  }

  void _submit() {
    final firstName = _nameController.text.trim();
    if (firstName.isEmpty) {
      return;
    }

    Navigator.of(context).pop(
      _PlayerFormResult(
        firstName: firstName,
        lastName: _surnameController.text.trim(),
        nickname: _nicknameController.text.trim(),
        birthdate: _birthdateController.text.trim(),
        scoliaId: _scoliaIdController.text.trim(),
        autodartsName: _autodartsNameController.text.trim(),
        threeKDartsId: _threeKDartsIdController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.player != null;

    return AlertDialog(
      title: Text(isEditing ? 'Spieler bearbeiten' : 'Spieler anlegen'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Vorname *',
                prefixIcon: Icon(Icons.person_outline),
              ),
              textInputAction: TextInputAction.next,
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _surnameController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Nachname',
                prefixIcon: Icon(Icons.person_outline),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nicknameController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Spitzname',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _birthdateController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Geburtsdatum (TT.MM.JJJJ)',
                prefixIcon: const Icon(Icons.cake_outlined),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_today_outlined),
                  tooltip: 'Datum wählen',
                  onPressed: _pickBirthdate,
                ),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _autodartsNameController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Autodarts Name',
                prefixIcon: Icon(Icons.sports_esports_outlined),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _scoliaIdController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Scolia ID',
                prefixIcon: Icon(Icons.camera_alt_outlined),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _threeKDartsIdController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '3k Darts ID',
                prefixIcon: Icon(Icons.tag_outlined),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Speichern')),
      ],
    );
  }
}

class _PlayerFormResult {
  const _PlayerFormResult({
    required this.firstName,
    required this.lastName,
    required this.nickname,
    required this.birthdate,
    required this.scoliaId,
    required this.autodartsName,
    required this.threeKDartsId,
  });

  final String firstName;
  final String lastName;
  final String nickname;
  final String birthdate;
  final String scoliaId;
  final String autodartsName;
  final String threeKDartsId;
}
