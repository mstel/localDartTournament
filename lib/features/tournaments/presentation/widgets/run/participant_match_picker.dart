import 'package:flutter/material.dart';
import '../../../application/order_of_play/order_of_play_controller.dart';
import '../../../domain/tournament_models.dart';

class ParticipantMatchPicker extends StatelessWidget {
  const ParticipantMatchPicker({
    super.key,
    required this.tournament,
    required this.activeStage,
    required this.onChange,
  });
  final CreatedTournament tournament;
  final int activeStage;
  final Future<void> Function() onChange;

  Future<void> _suggest(BuildContext context, TournamentPlayer player) async {
    const controller = OrderOfPlayController();
    final suggestion = controller.suggestForPlayer(
      tournament,
      activeStage,
      player,
    );
    if (suggestion == null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(player.name),
          content: const Text(
            'Momentan gibt es kein freies Match: Teilnehmer oder Gegner spielen bereits, alle Boards sind belegt oder es steht keine offene Begegnung fest.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Schließen'),
            ),
          ],
        ),
      );
      return;
    }
    final match = suggestion.entry.match;
    final start = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Begegnungsvorschlag'),
        content: SingleChildScrollView(
          child: Text(
            '${match.homePlayer!.name} gegen ${match.awayPlayer!.name}\n${suggestion.entry.origin}\nBoard ${suggestion.board} ist frei.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Jetzt starten'),
          ),
        ],
      ),
    );
    if (start != true || !context.mounted) return;
    // Availability can change while the dialog is open.
    if (controller.start(tournament, activeStage, match, suggestion.board)) {
      await onChange();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Teilnehmer oder Board sind inzwischen belegt. Bitte erneut auswählen.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: const PageStorageKey('order-of-play-participants'),
    title: Text('Teilnehmer (${tournament.players.length})'),
    subtitle: const Text(
      'Antippen, um ein jetzt spielbares Match vorzuschlagen',
    ),
    children: [
      for (final player in tournament.players)
        ListTile(
          title: Text(player.name),
          leading: const Icon(Icons.person_outline),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _suggest(context, player),
        ),
    ],
  );
}
