import 'package:flutter/material.dart';
import '../../../../shared/widgets/adaptive_content.dart';
import '../../../statistics/domain/best_performance.dart';
import '../../../tournaments/data/app_database.dart';
import '../../domain/tournament_models.dart';
import '../../data/tournament_storage.dart';
import '../widgets/run/best_performance_editor.dart';

class ChallongeArchivePage extends StatefulWidget {
  const ChallongeArchivePage({super.key, required this.tournament});
  final CreatedTournament tournament;

  @override
  State<ChallongeArchivePage> createState() => _ChallongeArchivePageState();
}

class _ChallongeArchivePageState extends State<ChallongeArchivePage> {
  late CreatedTournament tournament = widget.tournament;
  bool saving = false;

  // ── helper: persist and reload ───────────────────────────────────────────────
  Future<void> _save(CreatedTournament updated) async {
    setState(() => saving = true);
    try {
      await TournamentStorage().saveTournament(updated);
      if (mounted) setState(() => tournament = updated);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  // ── Bestleistungen bearbeiten ─────────────────────────────────────────────────
  Future<void> editBestPerformances(Map<String, dynamic> source) async {
    final archive = tournament.importedArchive!;
    final playerById = <String, TournamentPlayer>{};
    for (final participant in archive.participants) {
      final player = TournamentPlayer(
        profileId: participant['profileId'] as String?,
        name: '${participant['name'] ?? 'Teilnehmer'}',
        isGenerated: false,
      );
      playerById['${participant['id']}'] = player;
      for (final alias in participant['groupPlayerIds'] as List? ?? const []) {
        playerById['$alias'] = player;
      }
    }
    final performances = (source['bestPerformances'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => BestPerformance.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
    final match = GroupMatch(
      homePlayer: playerById['${source['player1_id']}'],
      awayPlayer: playerById['${source['player2_id']}'],
      round: (source['round'] as int? ?? 1).abs(),
      bestPerformances: performances,
    );
    final result = await showDialog<List<BestPerformance>>(
      context: context,
      builder: (_) =>
          _ArchivePerformanceDialog(match: match, initial: performances),
    );
    if (result == null || !mounted) return;
    final updatedMatches = [
      for (final item in archive.matches)
        if (identical(item, source) ||
            (source['id'] != null && item['id'] == source['id']))
          {
            ...item,
            'bestPerformances': result.map((entry) => entry.toJson()).toList(),
          }
        else
          Map<String, dynamic>.from(item),
    ];
    final updatedJson = tournament.toJson();
    updatedJson['importedArchive'] = archive
        .copyWithMatches(updatedMatches)
        .toJson();
    await _save(CreatedTournament.fromJson(updatedJson));
  }

  // ── Teilnehmer-Zuweisung bearbeiten ─────────────────────────────────────────────
  Future<void> _editPlayerAssignments() async {
    final archive = tournament.importedArchive!;
    final db = LocalAppDatabase();
    final allProfiles = await db.loadPlayerProfiles();

    if (!mounted) return;

    // Map: challonge participant id → profileId (nullable)
    final current = <String, String?>{
      for (final p in archive.participants)
        '${p['id']}': p['profileId'] as String?,
    };

    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (_) => _PlayerAssignmentDialog(
        participants: archive.participants,
        allProfiles: allProfiles,
        initial: current,
      ),
    );
    if (result == null || !mounted) return;

    // Build updated participants list
    final updatedParticipants = [
      for (final p in archive.participants)
        {...Map<String, dynamic>.from(p), 'profileId': result['${p['id']}']},
    ];

    final updatedJson = tournament.toJson();
    updatedJson['importedArchive'] = archive
        .copyWithParticipants(updatedParticipants)
        .toJson();

    // Also update the players list on the tournament itself
    final updatedTournamentJson = Map<String, dynamic>.from(updatedJson);
    final updatedTournament = CreatedTournament.fromJson(updatedTournamentJson);

    // Patch players by name match (using name→profileId mapping from archive)
    final nameToProfileId = <String, String?>{
      for (final p in updatedParticipants)
        '${p['name']}': p['profileId'] as String?,
    };

    final patchedPlayers = [
      for (final p in updatedTournament.players)
        p.copyWith(profileId: nameToProfileId[p.name]),
    ];

    final finalJson = updatedTournament.toJson();
    finalJson['players'] = patchedPlayers.map((p) => p.toJson()).toList();
    await _save(CreatedTournament.fromJson(finalJson));
  }

  @override
  Widget build(BuildContext context) {
    final archive = tournament.importedArchive!;
    final players = {
      for (final p in archive.participants) '${p['id']}': '${p['name']}',
      for (final p in archive.participants)
        for (final alias in (p['groupPlayerIds'] as List? ?? const []))
          '$alias': '${p['name']}',
    };
    final ranks = [...archive.participants]
      ..sort(
        (a, b) => ((a['finalRank'] as int?) ?? 999999).compareTo(
          (b['finalRank'] as int?) ?? 999999,
        ),
      );

    // Determine assignment quality
    final assigned = archive.participants
        .where((p) => p['profileId'] != null)
        .length;
    final total = archive.participants.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('${tournament.name} (Challonge-Turnier)'),
        actions: [
          IconButton(
            tooltip: 'Teilnehmer-Zuweisung bearbeiten',
            icon: const Icon(Icons.people_alt_outlined),
            onPressed: saving ? null : _editPlayerAssignments,
          ),
        ],
      ),
      body: AdaptiveContentList(
        children: [
          Text(
            '${archive.usesNativeLogic ? 'Challonge-Vergleich' : 'Challonge-Archiv'} · ${switch (archive.mode) {
              'single elimination' => 'Einfach-K.-o.',
              'double elimination' => 'Doppel-K.-o.',
              'round robin' => 'Jeder gegen jeden',
              'swiss' => 'Schweizer System',
              _ => archive.mode,
            }}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text('Originalergebnisse und Platzierungen aus Challonge.'),
          if (saving) const LinearProgressIndicator(),
          if (archive.url.isNotEmpty) SelectableText(archive.url),
          const SizedBox(height: 8),

          // Player assignment status banner
          Card(
            color: assigned == total
                ? Theme.of(context).colorScheme.secondaryContainer
                : Theme.of(context).colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 450;
                  final content = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        assigned == total
                            ? 'Alle Teilnehmer zugewiesen ($assigned/$total)'
                            : 'Teilnehmer-Zuweisung unvollständig ($assigned/$total zugewiesen)',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (assigned < total) ...[
                        const SizedBox(height: 4),
                        const Text(
                          'Für die Ranglistenwertung müssen alle Teilnehmer zugewiesen sein.',
                        ),
                      ],
                    ],
                  );
                  final button = FilledButton.tonal(
                    onPressed: saving ? null : _editPlayerAssignments,
                    child: const Text('Zuweisung bearbeiten'),
                  );

                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              assigned == total
                                  ? Icons.check_circle_outline
                                  : Icons.warning_amber_outlined,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: content),
                          ],
                        ),
                        const SizedBox(height: 8),
                        button,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Icon(
                        assigned == total
                            ? Icons.check_circle_outline
                            : Icons.warning_amber_outlined,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: content),
                      const SizedBox(width: 8),
                      button,
                    ],
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 16),
          if (archive.nativeValidation != null) ...[
            Text(
              'Prüfung mit eigener Turnierlogik',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              archive.nativeValidation!['status'] == 'matched'
                  ? 'Die berechneten Platzierungen und das Weiterkommen stimmen mit den verfügbaren Challonge-Daten überein.'
                  : 'Abweichungen zu Challonge wurden festgestellt:',
            ),
            for (final issue
                in archive.nativeValidation!['issues'] as List? ?? const [])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('$issue'),
              ),
            const Text(
              'Historische Paarungen und K.-o.-Startplätze werden übernommen; die Auslosung wird damit nicht geprüft.',
            ),
            const SizedBox(height: 16),
          ],

          Text('Platzierungen', style: Theme.of(context).textTheme.titleLarge),
          for (final p in ranks)
            ListTile(
              leading: p['profileId'] != null
                  ? const Icon(Icons.person, size: 18, color: Colors.green)
                  : const Icon(Icons.person_off_outlined, size: 18),
              title: Text('${p['finalRank'] ?? '–'}. ${p['name']}'),
              subtitle: Text(
                [
                  if (p['profileId'] == null) 'Kein lokales Profil zugewiesen',
                  if (p['finalRank'] == null)
                    'Keine Gesamtplatzierung von Challonge geliefert',
                  for (final group in p['groupPlacements'] as List? ?? const [])
                    '${group['group']}: Platz ${group['rank']}',
                ].join('\n'),
              ),
            ),

          Text(
            'Begegnungen (${archive.matches.length})',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final m in archive.matches)
            ListTile(
              title: Text(
                '${players['${m['player1_id']}'] ?? 'Freilos / offen'} – ${players['${m['player2_id']}'] ?? 'Freilos / offen'}',
              ),
              subtitle: Text(
                '${m['group_id'] == null ? '' : 'Gruppe ${m['group_id']} · '}Runde ${m['round'] ?? '–'} · ${m['scores_csv'] == null || m['scores_csv'] == '' ? 'Kein Spielstand' : m['scores_csv']}\nSieger: ${players['${m['winner_id']}'] ?? 'Keiner angegeben'}',
              ),
              trailing: IconButton(
                tooltip: 'Bestleistungen erfassen oder bearbeiten',
                onPressed: saving ? null : () => editBestPerformances(m),
                icon: Badge(
                  isLabelVisible:
                      (m['bestPerformances'] as List?)?.isNotEmpty ?? false,
                  child: const Icon(Icons.military_tech_outlined),
                ),
              ),
            ),

          if (!archive.usesNativeLogic)
            const ExpansionTile(
              title: Text('Hinweise zum Import'),
              children: [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Einzelne ganzzahlige Spielstände werden als Legs in die Statistik übernommen. Mehrteilige Ergebnisse und kampflose Siege bleiben im Archiv sichtbar. Der historische Turnierbaum wird nicht neu berechnet.',
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Teilnehmer-Zuweisung-Dialog ──────────────────────────────────────────────────

class _PlayerAssignmentDialog extends StatefulWidget {
  const _PlayerAssignmentDialog({
    required this.participants,
    required this.allProfiles,
    required this.initial,
  });
  final List<Map<String, dynamic>> participants;
  final List<PlayerProfile> allProfiles;
  final Map<String, String?> initial;

  @override
  State<_PlayerAssignmentDialog> createState() =>
      _PlayerAssignmentDialogState();
}

class _PlayerAssignmentDialogState extends State<_PlayerAssignmentDialog> {
  late final Map<String, String?> _assignments = Map.from(widget.initial);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Teilnehmer-Zuweisung bearbeiten'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Weise jedem Challonge-Teilnehmer ein lokales Teilnehmerprofil zu. Nur zugewiesene Teilnehmer gehen in die Ranglistenwertung ein.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              for (final p in widget.participants) ...[
                Text(
                  '${p['name']}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                DropdownButtonFormField<String?>(
                  initialValue: _assignments['${p['id']}'],
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text(
                        '— Kein Profil —',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ),
                    for (final profile in widget.allProfiles)
                      DropdownMenuItem(
                        value: profile.id,
                        child: Text(profile.displayName),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _assignments['${p['id']}'] = value),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _assignments),
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

// ── Bestleistungen-Dialog ─────────────────────────────────────────────────────

class _ArchivePerformanceDialog extends StatefulWidget {
  const _ArchivePerformanceDialog({required this.match, required this.initial});
  final GroupMatch match;
  final List<BestPerformance> initial;
  @override
  State<_ArchivePerformanceDialog> createState() =>
      _ArchivePerformanceDialogState();
}

class _ArchivePerformanceDialogState extends State<_ArchivePerformanceDialog> {
  late List<BestPerformance> items = [...widget.initial];
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Bestleistungen erfassen'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: BestPerformanceEditor(
          match: widget.match,
          initial: items,
          onChanged: (value) => items = value,
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, items),
        child: const Text('Speichern'),
      ),
    ],
  );
}
