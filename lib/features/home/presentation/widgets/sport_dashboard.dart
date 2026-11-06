import 'package:flutter/material.dart';
import '../../../../shared/theme/tournament_display_palette.dart';

class SportHero extends StatelessWidget {
  const SportHero({super.key, required this.onTournament});
  final VoidCallback onTournament;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(
        colors: TournamentDisplayPalette.heroGradient,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'BEREIT FÜR DEN NÄCHSTEN WURF?',
          style: TextStyle(
            color: Color(0xFF70E0BA),
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Deine Spielzentrale.',
          style: Theme.of(
            context,
          ).textTheme.headlineLarge?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: onTournament,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF70E0BA),
                foregroundColor: const Color(0xFF142B3A),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Turnier erstellen'),
            ),
          ],
        ),
      ],
    ),
  );
}
