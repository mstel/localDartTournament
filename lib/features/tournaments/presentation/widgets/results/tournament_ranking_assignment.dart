import 'package:flutter/material.dart';

import '../../../../rankings/domain/local_ranking.dart';
import '../../../data/app_database.dart';
import '../../../data/tournament_storage.dart';
import '../../../domain/tournament_models.dart';

class TournamentRankingAssignment extends StatefulWidget {
  const TournamentRankingAssignment({
    super.key,
    required this.tournament,
    this.database,
    this.storage,
    this.onSaved,
  });

  final CreatedTournament tournament;
  final LocalAppDatabase? database;
  final TournamentStorage? storage;
  final VoidCallback? onSaved;

  @override
  State<TournamentRankingAssignment> createState() =>
      _TournamentRankingAssignmentState();
}

class _TournamentRankingAssignmentState
    extends State<TournamentRankingAssignment> {
  late final LocalAppDatabase _database = widget.database ?? LocalAppDatabase();
  late final TournamentStorage _storage = widget.storage ?? TournamentStorage();
  late final Set<String> _selectedIds = widget.tournament.countsForRanking
      ? widget.tournament.rankingIds.toSet()
      : <String>{};
  late Future<List<LocalRanking>> _rankings = _database.loadLocalRankings();
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _pruneIneligibleAssignments();
  }

  Future<Set<String>> _eligibleRankingIds(Iterable<String> candidates) async {
    final candidateIds = candidates.toSet();
    if (candidateIds.isEmpty) return const {};
    final profiles = await _database.loadPlayerProfiles();
    final profileIdByName = {
      for (final profile in profiles)
        profile.displayName.trim().toLowerCase(): profile.id,
    };
    final tournamentPlayerIds = <String>{};
    for (final player in widget.tournament.players.expand(
      (player) => player.individuals,
    )) {
      final id =
          player.profileId ?? profileIdByName[player.name.trim().toLowerCase()];
      if (id != null) tournamentPlayerIds.add(id);
    }
    if (tournamentPlayerIds.isEmpty) return const {};

    final rankings = await _database.loadLocalRankings();
    final eligible = <String>{};
    for (final ranking in rankings.where(
      (ranking) => candidateIds.contains(ranking.id),
    )) {
      final playerIds = await _database.loadRankingPlayerIds(ranking.id);
      if (playerIds.any(tournamentPlayerIds.contains)) {
        eligible.add(ranking.id);
      }
    }
    return eligible;
  }

  Future<void> _pruneIneligibleAssignments() async {
    if (!widget.tournament.countsForRanking ||
        widget.tournament.rankingIds.isEmpty) {
      return;
    }
    final previousCountsForRanking = widget.tournament.countsForRanking;
    final previousRankingIds = List<String>.from(widget.tournament.rankingIds);
    try {
      final eligibleIds = await _eligibleRankingIds(previousRankingIds);
      if (eligibleIds.length == previousRankingIds.length) return;
      final rankingIds = eligibleIds.toList()..sort();
      setState(() {
        _saving = true;
        _saveError = null;
        _selectedIds
          ..clear()
          ..addAll(eligibleIds);
        widget.tournament
          ..countsForRanking = eligibleIds.isNotEmpty
          ..rankingIds = rankingIds;
      });
      await _storage.saveTournament(widget.tournament);
      widget.onSaved?.call();
    } catch (error) {
      widget.tournament
        ..countsForRanking = previousCountsForRanking
        ..rankingIds = previousRankingIds;
      _selectedIds
        ..clear()
        ..addAll(previousRankingIds);
      if (mounted) {
        setState(
          () => _saveError =
              'Ranglistenwertung konnte nicht geprüft oder bereinigt '
              'werden: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool get _hasChanges {
    final savedIds = widget.tournament.countsForRanking
        ? widget.tournament.rankingIds.toSet()
        : <String>{};
    return !_selectedIds.containsAll(savedIds) ||
        !savedIds.containsAll(_selectedIds);
  }

  Future<void> _save() async {
    if (_saving || !_hasChanges) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final oldCountsForRanking = widget.tournament.countsForRanking;
    final oldRankingIds = List<String>.from(widget.tournament.rankingIds);
    try {
      final requestedCount = _selectedIds.length;
      final eligibleIds = await _eligibleRankingIds(_selectedIds);
      final rankingIds = eligibleIds.toList()..sort();
      widget.tournament
        ..countsForRanking = eligibleIds.isNotEmpty
        ..rankingIds = rankingIds;
      await _storage.saveTournament(widget.tournament);
      _selectedIds
        ..clear()
        ..addAll(eligibleIds);
      widget.onSaved?.call();
      if (eligibleIds.length < requestedCount && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ranglisten ohne teilnehmende Teilnehmer wurden nicht zugewiesen.',
            ),
          ),
        );
      }
    } catch (error) {
      widget.tournament
        ..countsForRanking = oldCountsForRanking
        ..rankingIds = oldRankingIds;
      if (mounted) {
        setState(
          () => _saveError = 'Ranglistenwertung nicht gespeichert: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<List<LocalRanking>>(
          future: _rankings,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ranglisten konnten nicht geladen werden.'),
                  TextButton(
                    onPressed: () => setState(
                      () => _rankings = _database.loadLocalRankings(),
                    ),
                    child: const Text('Erneut versuchen'),
                  ),
                ],
              );
            }
            final rankings = snapshot.data;
            if (rankings == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ranglistenwertung',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Dieses abgeschlossene Turnier wird erst nach dem Speichern '
                  'in den ausgewählten Ranglisten berücksichtigt.',
                ),
                if (rankings.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Es sind noch keine lokalen Ranglisten angelegt.',
                    ),
                  )
                else
                  for (final ranking in rankings)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(ranking.name),
                      value: _selectedIds.contains(ranking.id),
                      onChanged: _saving
                          ? null
                          : (selected) => setState(() {
                              if (selected == true) {
                                _selectedIds.add(ranking.id);
                              } else {
                                _selectedIds.remove(ranking.id);
                              }
                            }),
                    ),
                if (_saveError != null)
                  Text(
                    _saveError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _saving || !_hasChanges ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Zuweisung speichern'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
