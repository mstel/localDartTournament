import 'package:flutter/material.dart';

/// Editor für eine Mannschaft im Team-Game-Setup.
///
/// Die Controller liegen bewusst in der Seite, damit Eingaben bei
/// Layoutwechseln und Rotation erhalten bleiben.
class TeamRosterEditor extends StatelessWidget {
  const TeamRosterEditor({
    super.key,
    required this.side,
    required this.title,
    required this.icon,
    required this.teamNameController,
    required this.playerControllers,
    required this.onAddPlayer,
    required this.onRemovePlayer,
  });

  final String side;
  final String title;
  final IconData icon;
  final TextEditingController teamNameController;
  final List<TextEditingController> playerControllers;
  final VoidCallback onAddPlayer;
  final void Function(int index) onRemovePlayer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey('team-game-$side-name'),
              controller: teamNameController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Mannschaftsname',
                border: const OutlineInputBorder(),
                prefixIcon: Icon(icon),
              ),
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < playerControllers.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: ValueKey('team-game-$side-player-$index'),
                        controller: playerControllers[index],
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Spieler ${index + 1}',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      key: ValueKey('team-game-$side-remove-$index'),
                      onPressed: () => onRemovePlayer(index),
                      icon: const Icon(Icons.person_remove_outlined),
                      tooltip: 'Spieler entfernen',
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              key: ValueKey('team-game-$side-add'),
              onPressed: onAddPlayer,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Spieler hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }
}
