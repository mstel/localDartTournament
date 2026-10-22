import 'package:flutter/material.dart';
import '../../../modes/swiss/swiss_engine.dart';

import '../../../domain/tournament_models.dart';

class RenamePlayerDialog extends StatefulWidget {
  const RenamePlayerDialog({super.key, required this.player});

  final TournamentPlayer player;

  @override
  State<RenamePlayerDialog> createState() => _RenamePlayerDialogState();
}

class _RenamePlayerDialogState extends State<RenamePlayerDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.player.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_nameController.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Spieler bearbeiten'),
      content: TextField(
        controller: _nameController,
        autofocus: true,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Spielername',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Speichern')),
      ],
    );
  }
}

class GroupSizePreview extends StatelessWidget {
  const GroupSizePreview({super.key, required this.groupSizes});

  final List<int> groupSizes;

  @override
  Widget build(BuildContext context) {
    if (groupSizes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 14),
        child: Text('Erst Spieler anlegen.'),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var index = 0; index < groupSizes.length; index++)
          Chip(
            avatar: CircleAvatar(child: Text('${index + 1}')),
            label: Text('${groupSizes[index]} Spieler'),
          ),
      ],
    );
  }
}

class RoundRobinRepeatsSetup extends StatelessWidget {
  const RoundRobinRepeatsSetup({
    super.key,
    required this.groupSizes,
    required this.playTypes,
    required this.repeats,
    required this.onChangeRepeats,
  });

  final List<int> groupSizes;
  final List<String> playTypes;
  final List<int> repeats;
  final void Function(int groupIndex, int delta) onChangeRepeats;

  @override
  Widget build(BuildContext context) {
    if (groupSizes.isEmpty ||
        !playTypes.any((t) => t == 'round_robin' || t == 'swiss')) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Begegnungen pro Paar / Swiss-Runden',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (playTypes.contains('swiss'))
          const Text(
            'Swiss: feste Rundenzahl, maximal die aufgerundete halbe Teilnehmerzahl je Gruppe. Die nächste Runde wartet auf alle Ergebnisse.',
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var index = 0; index < groupSizes.length; index++)
              if (index < playTypes.length &&
                  (playTypes[index] == 'round_robin' ||
                      playTypes[index] == 'swiss'))
                Container(
                  padding: const EdgeInsets.only(left: 10),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(groupLabel(index + 1)),
                      const SizedBox(width: 8),
                      IconButton(
                        key: ValueKey('round-robin-repeat-minus-${index + 1}'),
                        constraints: const BoxConstraints.tightFor(
                          width: 48,
                          height: 48,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: repeats[index] <= 1
                            ? null
                            : () => onChangeRepeats(index, -1),
                        icon: const Icon(Icons.remove),
                        tooltip: 'Weniger Spiele',
                      ),
                      Text(
                        playTypes[index] == 'swiss'
                            ? '${repeats[index]} Runden'
                            : '${repeats[index]}x',
                      ),
                      IconButton(
                        key: ValueKey('round-robin-repeat-plus-${index + 1}'),
                        constraints: const BoxConstraints.tightFor(
                          width: 48,
                          height: 48,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed:
                            playTypes[index] == 'swiss' &&
                                repeats[index] >=
                                    SwissEngine.maximumRounds(groupSizes[index])
                            ? null
                            : () => onChangeRepeats(index, 1),
                        icon: const Icon(Icons.add),
                        tooltip: 'Mehr Spiele',
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ],
    );
  }
}

class GroupPlayTypeSetup extends StatelessWidget {
  const GroupPlayTypeSetup({
    super.key,
    required this.groupSizes,
    required this.playTypes,
    required this.onChanged,
  });

  final List<int> groupSizes;
  final List<String> playTypes;
  final void Function(int groupIndex, String playType) onChanged;

  @override
  Widget build(BuildContext context) {
    if (groupSizes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Spieltyp je Gruppe',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var index = 0; index < groupSizes.length; index++)
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  itemHeight: null,
                  key: ValueKey(
                    'group-play-type-${index + 1}-${playTypes[index]}',
                  ),
                  isExpanded: true,
                  initialValue: playTypes[index],
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: groupLabel(index + 1),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'round_robin', child: Text('Liga')),
                    DropdownMenuItem(
                      value: 'swiss',
                      child: Text('Schweizer System'),
                    ),
                    DropdownMenuItem(
                      value: 'mini_knockout',
                      child: Text('Mini-KO'),
                    ),
                    DropdownMenuItem(
                      value: 'double_knockout',
                      child: Text('Doppel-KO'),
                    ),
                    DropdownMenuItem(
                      value: 'triple_knockout',
                      child: Text('Triple-KO'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      onChanged(index, value);
                    }
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class StageMatchCountPreview extends StatelessWidget {
  const StageMatchCountPreview({
    super.key,
    required this.matchCount,
    required this.details,
  });

  final int matchCount;
  final List<String> details;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sports_score_outlined, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$matchCount Spiele in dieser Etappe',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final detail in details)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(detail),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GroupTieBreakerSetup extends StatelessWidget {
  const GroupTieBreakerSetup({
    super.key,
    required this.tieBreakers,
    required this.onMoveTieBreaker,
  });

  final List<String> tieBreakers;
  final void Function(int index, int direction) onMoveTieBreaker;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Tie-Breaker', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var index = 0; index < tieBreakers.length; index++)
              Container(
                padding: const EdgeInsets.only(left: 10),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(radius: 12, child: Text('${index + 1}')),
                    const SizedBox(width: 8),
                    Flexible(child: Text(tieBreakerLabel(tieBreakers[index]))),
                    Tooltip(
                      message: tieBreakerExplanation(tieBreakers[index]),
                      child: const SizedBox.square(
                        dimension: 48,
                        child: Center(
                          child: Icon(Icons.info_outline, size: 18),
                        ),
                      ),
                    ),
                    IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: index == 0
                          ? null
                          : () => onMoveTieBreaker(index, -1),
                      icon: const Icon(Icons.keyboard_arrow_up),
                      tooltip: 'Tie-Breaker nach oben',
                    ),
                    IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: index == tieBreakers.length - 1
                          ? null
                          : () => onMoveTieBreaker(index, 1),
                      icon: const Icon(Icons.keyboard_arrow_down),
                      tooltip: 'Tie-Breaker nach unten',
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

String tieBreakerExplanation(String tieBreaker) => switch (tieBreaker) {
  'points' =>
    'Matchpunkte: Sieg = 3 Punkte, Unentschieden = 1 Punkt, Niederlage = 0. '
        'Es zählen Match-Ergebnisse, nicht die Anzahl einzelner Legs.',
  'legDifference' =>
    'Leg-Differenz: Summe der gewonnenen Legs minus Summe der verlorenen Legs '
        'aus allen gewerteten Gruppenmatches. Die höhere Differenz gewinnt.',
  'legsFor' =>
    'Gewonnene Legs: Gesamtzahl der in gewerteten Gruppenmatches gewonnenen '
        'Legs. Die höhere Zahl gewinnt.',
  'headToHead' =>
    'Direkter Vergleich: Matchpunkte aus den direkten Duellen; bei Gleichstand '
        'entscheidet dort zuerst die Leg-Differenz und danach die Zahl '
        'gewonnener Legs.',
  _ => tieBreaker,
};

class QualificationRuleSummary extends StatelessWidget {
  const QualificationRuleSummary({super.key, required this.qualificationPlan});

  final QualificationPlan? qualificationPlan;

  @override
  Widget build(BuildContext context) {
    final plan = qualificationPlan;
    if (plan == null) {
      return const Text('Keine gültige Anzahl Weiterkommende.');
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(label: Text('${plan.totalQualifiers} Weiterkommende')),
        if (plan.fixedByGroup.isNotEmpty &&
            plan.fixedByGroup.toSet().length > 1)
          Chip(label: Text(_fixedByGroupSummary(plan.fixedByGroup)))
        else if (plan.fixedPerGroup > 0)
          Chip(label: Text('Top ${plan.fixedPerGroup} je Gruppe')),
        if (plan.extraCount > 0)
          Chip(
            label: Text(
              'Beste ${plan.extraCount} der ${plan.extraRank}. Plätze',
            ),
          ),
        if (plan.extraCount > 0 && plan.extraGroups.isNotEmpty)
          Chip(label: Text('Zusatz aus ${_formatGroups(plan.extraGroups)}')),
      ],
    );
  }

  String _formatGroups(List<int> groups) {
    if (groups.length == 1) {
      return groupLabel(groups.first);
    }

    return groups.map(groupLabel).join(', ');
  }

  String _fixedByGroupSummary(List<int> fixedByGroup) {
    return [
      for (var index = 0; index < fixedByGroup.length; index++)
        '${groupLabel(index + 1)} ${fixedByGroup[index]}',
    ].join(', ');
  }
}

class QualificationErrorBanner extends StatelessWidget {
  const QualificationErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class QualificationGroupPreview extends StatelessWidget {
  const QualificationGroupPreview({
    super.key,
    required this.groupSizes,
    required this.qualificationPlan,
    required this.onCyclePlace,
  });

  final List<int> groupSizes;
  final QualificationPlan? qualificationPlan;
  final void Function(int groupNumber, int place) onCyclePlace;

  @override
  Widget build(BuildContext context) {
    final plan = qualificationPlan;
    if (plan == null) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (var groupIndex = 0; groupIndex < groupSizes.length; groupIndex++)
          _QualificationGroupCard(
            groupNumber: groupIndex + 1,
            playerCount: groupSizes[groupIndex],
            qualificationPlan: plan,
            onCyclePlace: onCyclePlace,
          ),
      ],
    );
  }
}

class _QualificationGroupCard extends StatelessWidget {
  const _QualificationGroupCard({
    required this.groupNumber,
    required this.playerCount,
    required this.qualificationPlan,
    required this.onCyclePlace,
  });

  final int groupNumber;
  final int playerCount;
  final QualificationPlan qualificationPlan;
  final void Function(int groupNumber, int place) onCyclePlace;

  int get _fixedForGroup {
    if (groupNumber - 1 < qualificationPlan.fixedByGroup.length) {
      return qualificationPlan.fixedByGroup[groupNumber - 1];
    }
    return qualificationPlan.fixedPerGroup;
  }

  bool _isExtraCandidate(int place) {
    return qualificationPlan.extraCount > 0 &&
        place == qualificationPlan.extraRank &&
        qualificationPlan.extraGroups.contains(groupNumber);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 178,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            groupLabel(groupNumber),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var place = 1; place <= playerCount; place++)
                _QualificationPlaceBadge(
                  place: place,
                  isQualified: place <= _fixedForGroup,
                  isExtraCandidate: _isExtraCandidate(place),
                  onTap: () => onCyclePlace(groupNumber, place),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QualificationPlaceBadge extends StatelessWidget {
  const _QualificationPlaceBadge({
    required this.place,
    required this.isQualified,
    required this.isExtraCandidate,
    required this.onTap,
  });

  final int place;
  final bool isQualified;
  final bool isExtraCandidate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = isQualified
        ? const Color(0xFFC8F7DC)
        : isExtraCandidate
        ? const Color(0xFFFFE8A3)
        : colorScheme.surfaceContainerHighest;
    final borderColor = isQualified
        ? const Color(0xFF14965F)
        : isExtraCandidate
        ? const Color(0xFFC58A00)
        : colorScheme.outlineVariant;

    return Tooltip(
      message: isQualified
          ? 'Sicher weiter'
          : isExtraCandidate
          ? 'Vergleich um Zusatzplatz'
          : 'Scheidet aus',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: backgroundColor,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('$place.'),
        ),
      ),
    );
  }
}
