import 'package:flutter/material.dart';
import '../../../domain/player_withdrawal.dart';
import '../../../domain/tournament_models.dart';
import '../../../application/player_withdrawal_service.dart';

class PlayerWithdrawalDialog extends StatefulWidget {
  const PlayerWithdrawalDialog({
    super.key,
    required this.tournament,
    this.initialPlayer,
  });
  final CreatedTournament tournament;
  final TournamentPlayer? initialPlayer;
  @override
  State<PlayerWithdrawalDialog> createState() => _WithdrawalState();
}

class _WithdrawalState extends State<PlayerWithdrawalDialog> {
  TournamentPlayer? player;
  WithdrawalResultMode mode = WithdrawalResultMode.loseOpen;
  bool ranking = false, opponents = true;
  @override
  void initState() {
    super.initState();
    player = widget.initialPlayer;
  }

  Widget _explanationRow(
    BuildContext context,
    String option,
    String explanation,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            option,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            explanation,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Spieler aus Turnier entfernen'),
    scrollable: true,
    content: SizedBox(
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<TournamentPlayer>(
            itemHeight: null,
            isExpanded: true,
            initialValue: player,
            decoration: const InputDecoration(labelText: 'Spieler / Team'),
            items: [
              for (final p in widget.tournament.players)
                if (PlayerWithdrawalService.policy(widget.tournament, p) ==
                    null)
                  DropdownMenuItem(value: p, child: Text(p.name)),
            ],
            onChanged: (p) => setState(() => player = p),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<WithdrawalResultMode>(
            itemHeight: null,
            initialValue: mode,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Spielwertung'),
            items: [
              for (final v in WithdrawalResultMode.values)
                DropdownMenuItem(
                  value: v,
                  child: Text(switch (v) {
                    WithdrawalResultMode.loseOpen =>
                      'Offene Spiele als Niederlage zu null werten',
                    WithdrawalResultMode.loseAll =>
                      'Alle Spiele als Niederlage zu null werten',
                    WithdrawalResultMode.ignoreOpen =>
                      'Nur offene Spiele von der Ranglistenwertung ausschließen',
                    WithdrawalResultMode.ignoreAll =>
                      'Alle Spiele von der Ranglistenwertung ausschließen',
                  }),
                ),
            ],
            onChanged: (v) => setState(() => mode = v!),
          ),
          const SizedBox(height: 16),
          Card(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.help_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Erläuterung der Optionen',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _explanationRow(
                    context,
                    'Offene Spiele als Niederlage zu null werten',
                    'Bereits gespielte Partien bleiben unverändert. Die offenen Partien zählen als Niederlagen.',
                  ),
                  const Divider(height: 8),
                  _explanationRow(
                    context,
                    'Alle Spiele als Niederlage zu null werten',
                    'Alle Partien zählen als Niederlagen.',
                  ),
                  const Divider(height: 8),
                  _explanationRow(
                    context,
                    'Nur offene Spiele von der Ranglistenwertung ausschließen',
                    'Bereits gespielte Partien bleiben gewertet; offene Partien beeinflussen die Rangliste nicht.',
                  ),
                  const Divider(height: 8),
                  _explanationRow(
                    context,
                    'Alle Spiele von der Ranglistenwertung ausschließen',
                    'Keine Partie dieses Turniers fließt für diesen Spieler in die Ranglistenwertung ein.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '„Alle Spiele“ betrifft auch bisherige Ergebnisse. Wenn frühere Etappen betroffen sind, werden die davon abhängigen späteren Etappen neu aufgebaut und ihre Ergebnisse zurückgesetzt. Im K.-o.-Baum kommt der Gegner eines offenen Spiels kampflos weiter.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: player == null
            ? null
            : () => Navigator.pop(
                context,
                PlayerWithdrawal(
                  playerKey: PlayerWithdrawalService.key(player!),
                  mode: mode,
                  createdAt: DateTime.now(),
                  countForRanking: ranking,
                  countOpponentsForRanking: opponents,
                ),
              ),
        child: const Text('Entfernen und Wertung anwenden'),
      ),
    ],
  );
}
