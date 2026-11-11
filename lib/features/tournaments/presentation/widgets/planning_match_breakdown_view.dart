import 'package:flutter/material.dart';
import '../../domain/planning_match_breakdown.dart';

class PlanningMatchBreakdownView extends StatelessWidget {
  const PlanningMatchBreakdownView({super.key, required this.breakdown});
  final PlanningMatchBreakdown breakdown;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'So entstehen die ${breakdown.total} Begegnungen',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (breakdown.groupSizes.isNotEmpty)
          const Text('Jeder gegen jeden: n × (n − 1) ÷ 2'),
        for (var index = 0; index < breakdown.groupSizes.length; index++)
          Text(
            'Gruppe ${index + 1}: ${breakdown.groupSizes[index]} Teilnehmer → '
            '${breakdown.groupSizes[index]} × ${breakdown.groupSizes[index] - 1} ÷ 2 = ${breakdown.groupMatches[index]} Begegnungen',
          ),
        if (breakdown.knockoutParticipants > 1) ...[
          Text(
            'K.-o.: ${breakdown.knockoutParticipants} ${breakdown.groupSizes.isEmpty ? 'Teilnehmer' : 'Teilnehmer (bis zu ${breakdown.qualifiersPerGroup} je Gruppe)'} → '
            '${breakdown.knockoutParticipants} − 1 = ${breakdown.knockoutMatches} Begegnungen',
          ),
          if (breakdown.byes > 0)
            Text(
              '${breakdown.byes} Freilose zählen nicht als gespielte Matches.',
            ),
        ],
        Text(
          'Gesamt: ${breakdown.groupTotal} Gruppenspiele + ${breakdown.knockoutMatches} K.-o.-Begegnungen = ${breakdown.total} Begegnungen',
        ),
        const Text(
          'Begegnungen sind Matches; die Legs innerhalb eines Matches werden hier nicht einzeln gezählt.',
        ),
      ],
    ),
  );
}
