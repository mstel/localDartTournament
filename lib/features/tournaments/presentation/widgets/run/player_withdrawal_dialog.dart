import 'package:flutter/material.dart';
import '../../../domain/player_withdrawal.dart';
import '../../../domain/tournament_models.dart';
import '../../../application/player_withdrawal_service.dart';

class PlayerWithdrawalDialog extends StatefulWidget {
  const PlayerWithdrawalDialog({
    super.key,
    required this.tournament,
    required this.stageIndex,
    this.initialPlayer,
  });
  final CreatedTournament tournament;
  final int stageIndex;
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

  String _modeLabel(WithdrawalResultMode value) => switch (value) {
    WithdrawalResultMode.loseOpen =>
      'Offene Begegnungen als Niederlage zu null werten',
    WithdrawalResultMode.loseAll =>
      'Alle Begegnungen als Niederlage zu null werten',
    WithdrawalResultMode.ignoreOpen =>
      'Nur offene Begegnungen von der Ranglistenwertung ausschließen',
    WithdrawalResultMode.ignoreAll =>
      'Alle Begegnungen von der Ranglistenwertung ausschließen',
  };

  String _modeExplanation(WithdrawalResultMode value) => switch (value) {
    WithdrawalResultMode.loseOpen =>
      'Bereits gespielte Partien bleiben unverändert. Die offenen Partien zählen als Niederlagen.',
    WithdrawalResultMode.loseAll => 'Alle Partien zählen als Niederlagen.',
    WithdrawalResultMode.ignoreOpen =>
      'Bereits gespielte Partien bleiben gewertet; offene Partien beeinflussen die Rangliste nicht.',
    WithdrawalResultMode.ignoreAll =>
      'Keine Partie dieses Turniers fließt für diesen Teilnehmer in die Ranglistenwertung ein.',
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Teilnehmer aus Turnier entfernen'),
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
            decoration: const InputDecoration(labelText: 'Teilnehmer / Team'),
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
            decoration: const InputDecoration(labelText: 'Begegnungswertung'),
            items: [
              for (final v in WithdrawalResultMode.values)
                DropdownMenuItem(
                  value: v,
                  child: Row(
                    children: [
                      Expanded(child: Text(_modeLabel(v))),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: _modeExplanation(v),
                        child: Icon(
                          Icons.help_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: (v) => setState(() => mode = v!),
          ),
          const SizedBox(height: 12),
          const Text(
            '„Alle Begegnungen“ betrifft auch bisherige Ergebnisse. Wenn frühere Phasen betroffen sind, werden die davon abhängigen späteren Phasen neu aufgebaut und ihre Ergebnisse zurückgesetzt. Im K.-o.-Baum kommt der Gegner eines offenen Spiels kampflos weiter.',
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
                  stageIndex: widget.stageIndex,
                  countForRanking: ranking,
                  countOpponentsForRanking: opponents,
                ),
              ),
        child: const Text('Entfernen und Wertung anwenden'),
      ),
    ],
  );
}
