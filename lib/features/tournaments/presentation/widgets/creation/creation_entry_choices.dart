import 'package:flutter/material.dart';
import '../../../../../shared/widgets/adaptive_content.dart';
import '../../../../../shared/widgets/sport_menu.dart';

class CreationEntryChoices extends StatelessWidget {
  const CreationEntryChoices({
    super.key,
    this.onFind,
    required this.onExpert,
    required this.onLeague,
  });
  final VoidCallback? onFind;
  final VoidCallback onExpert;
  final VoidCallback onLeague;
  @override
  Widget build(BuildContext context) => AdaptiveContentList(
    children: [
      Text(
        'Wie möchtest du dein Turnier erstellen?',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      const Text(
        'Wähle deinen Einstieg. Alle Details kannst du anschließend anpassen.',
      ),
      const SizedBox(height: 24),
      SportMenuGroup(
        title: 'Turnier starten',
        actions: [
          SportMenuAction(
            label: 'Normales- oder Ranglistenturnier erstellen',
            description:
                'Teilnehmer, Phasen, Regeln und Ranglisten selbst festlegen.',
            icon: Icons.tune,
            onTap: onExpert,
          ),
          SportMenuAction(
            label: 'Liga- oder Freundschaftsspiel erstellen',
            description: 'Heim- und Gastmannschaft mit Einzel und Doppel.',
            icon: Icons.groups_outlined,
            onTap: onLeague,
          ),
        ],
      ),
    ],
  );
}
