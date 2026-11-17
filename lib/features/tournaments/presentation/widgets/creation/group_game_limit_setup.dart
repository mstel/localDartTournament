import 'package:flutter/material.dart';
import '../../../domain/engines/limited_round_robin_engine.dart';
import '../../../domain/tournament_models.dart';

class GroupGameLimitSetup extends StatelessWidget {
  const GroupGameLimitSetup({
    super.key,
    required this.groupSizes,
    required this.playTypes,
    required this.repeats,
    required this.limits,
    required this.onChanged,
    this.strategies,
    this.onStrategyChanged,
  });
  final List<int> groupSizes, repeats;
  final List<String> playTypes;
  final List<int?> limits;
  final List<String>? strategies;
  final void Function(int group, int? limit) onChanged;
  final void Function(int group, String strategy)? onStrategyChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < groupSizes.length; i++)
        if (playTypes[i] == 'round_robin' && groupSizes[i] > 1) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            key: ValueKey('group-game-limit-${i + 1}'),
            title: Text(
              '${groupLabel(i + 1)}: Begegnungen pro Teilnehmer begrenzen',
            ),
            subtitle: const Text(
              'Feste, ausgewogene Gegnerauswahl. Freilose zählen nicht als Begegnung. Bei ungerader Teilnehmerzahl kann ein Teilnehmer eine Begegnung weniger erhalten.',
            ),
            value: limits[i] != null,
            onChanged: (enabled) => onChanged(i, enabled ? 5 : null),
          ),
          if (limits[i] != null)
            DropdownButtonFormField<int>(
              key: ValueKey('group-game-limit-value-${i + 1}-${limits[i]}'),
              initialValue: limits[i],
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Spielobergrenze'),
              items: [
                for (
                  var limit = 1;
                  limit <=
                      ((groupSizes[i] - 1) * repeats[i] > limits[i]!
                          ? (groupSizes[i] - 1) * repeats[i]
                          : limits[i]!);
                  limit++
                )
                  DropdownMenuItem(
                    value: limit,
                    child: Text('$limit Begegnungen'),
                  ),
              ],
              onChanged: (value) => onChanged(i, value),
            ),
          if (limits[i] != null &&
              strategies != null &&
              onStrategyChanged != null)
            DropdownButtonFormField<String>(
              key: ValueKey('group-matchmaking-strategy-${i + 1}'),
              initialValue: i < strategies!.length ? strategies![i] : 'elo',
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Gegnerauswahl',
              ),
              items: [
                for (final strategy in limitedRoundRobinMatchmakingStrategies)
                  DropdownMenuItem(
                    value: strategy,
                    child: Text(limitedRoundRobinMatchmakingLabel(strategy)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onStrategyChanged!(i, value);
              },
            ),
          const SizedBox(height: 12),
        ],
    ],
  );
}
