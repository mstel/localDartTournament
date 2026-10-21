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
    final rankingIds = _selectedIds.toList()..sort();
    try {
      widget.tournament
        ..countsForRanking = _selectedIds.isNotEmpty
        ..rankingIds = rankingIds;
      await _storage.saveTournament(widget.tournament);
      widget.onSaved?.call();
    } catch (error) {
      widget.tournament
        ..countsForRanking = oldCountsForRanking
        ..rankingIds = oldRankingIds;
      if (mounted) {
        setState(
          () => _saveError = 'Ranglisten-Zuweisung nicht gespeichert: $error',
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
                  'Ranglisten-Zuweisung',
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
