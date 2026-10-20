import 'package:flutter/material.dart';

import '../../../../rankings/domain/local_ranking.dart';
import '../../../data/app_database.dart';
import '../../../data/tournament_storage.dart';
import '../../../domain/tournament_models.dart';

class TournamentRankingAssignmentSection extends StatefulWidget {
  const TournamentRankingAssignmentSection({
    super.key,
    required this.tournament,
    this.onAssigned,
    LocalAppDatabase? database,
    TournamentStorage? storage,
  }) : _database = database,
       _storage = storage;

  final CreatedTournament tournament;
  final VoidCallback? onAssigned;
  final LocalAppDatabase? _database;
  final TournamentStorage? _storage;

  @override
  State<TournamentRankingAssignmentSection> createState() =>
      _TournamentRankingAssignmentSectionState();
}

class _TournamentRankingAssignmentSectionState
    extends State<TournamentRankingAssignmentSection> {
  late final Future<List<LocalRanking>> _rankings =
      (widget._database ?? LocalAppDatabase()).loadLocalRankings();
  bool _saving = false;

  Future<void> _assign(List<LocalRanking> rankings) async {
    final selected = <String>{...widget.tournament.rankingIds};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Ranglisten zuweisen'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final ranking in rankings)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(ranking.name),
                      value: selected.contains(ranking.id),
                      onChanged: (value) => setDialogState(() {
                        if (value == true) {
                          selected.add(ranking.id);
                        } else {
                          selected.remove(ranking.id);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(selected),
              child: const Text('Zuweisen'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;

    final previousCountsForRanking = widget.tournament.countsForRanking;
    final previousRankingIds = List<String>.from(widget.tournament.rankingIds);
    setState(() => _saving = true);
    widget.tournament
      ..countsForRanking = true
      ..rankingIds.clear()
      ..rankingIds.addAll(result);
    try {
      await (widget._storage ?? TournamentStorage()).saveTournament(
        widget.tournament,
      );
      if (!mounted) return;
      widget.onAssigned?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turnier Rangliste(n) zugewiesen.')),
      );
    } catch (error) {
      widget.tournament
        ..countsForRanking = previousCountsForRanking
        ..rankingIds.clear()
        ..rankingIds.addAll(previousRankingIds);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ranglisten-Zuordnung fehlgeschlagen: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<LocalRanking>>(
    future: _rankings,
    builder: (context, snapshot) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Turnier noch keiner Rangliste zugeordnet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'Die Ergebnisse werden erst nach einer ausdrücklichen Zuordnung in Ranglisten berücksichtigt.',
              ),
              if (snapshot.hasError) ...[
                const SizedBox(height: 8),
                Text(
                  'Ranglisten konnten nicht geladen werden: ${snapshot.error}',
                ),
              ] else if (snapshot.hasData && snapshot.data!.isEmpty) ...[
                const SizedBox(height: 8),
                const Text('Lege zuerst eine Rangliste im Hauptmenü an.'),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed:
                    _saving || !snapshot.hasData || snapshot.data!.isEmpty
                    ? null
                    : () => _assign(snapshot.data!),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.playlist_add),
                label: const Text('Rangliste zuweisen'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
