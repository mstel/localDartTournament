import 'package:flutter/material.dart';

import '../../tournaments/domain/tournament_models.dart';

class LeagueGameFormatSetup extends StatelessWidget {
  const LeagueGameFormatSetup({
    super.key,
    required this.value,
    required this.onChanged,
    this.additionalSettings = const [],
  });

  final TournamentGameFormat value;
  final ValueChanged<TournamentGameFormat> onChanged;
  final List<Widget> additionalSettings;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final columns = (constraints.maxWidth / (200 * scale)).floor().clamp(
        1,
        4,
      );
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final setting in [
            _x01Field(width),
            _checkoutField(width),
            _legsField(width),
            _setsField(width),
            _doubleInField(width),
            ...additionalSettings.map(
              (child) => SizedBox(width: width, child: child),
            ),
          ])
            setting,
        ],
      );
    },
  );

  Widget _x01Field(double width) => SizedBox(
    width: width,
    child: DropdownButtonFormField<int>(
      key: ValueKey('league-x01-${value.x01Score}'),
      initialValue: value.x01Score,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'X01-Punktzahl'),
      items: const [101, 170, 201, 301, 401, 501, 701, 901]
          .map((score) => DropdownMenuItem(value: score, child: Text('$score')))
          .toList(),
      onChanged: (score) {
        if (score != null) onChanged(_copy(x01Score: score));
      },
    ),
  );

  Widget _checkoutField(double width) => SizedBox(
    width: width,
    child: DropdownButtonFormField<String>(
      key: ValueKey('league-checkout-${value.checkoutType}'),
      initialValue: value.checkoutType,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Checkout'),
      items: const [
        DropdownMenuItem(value: 'double_out', child: Text('Double Out')),
        DropdownMenuItem(value: 'single_out', child: Text('Single Out')),
        DropdownMenuItem(value: 'master_out', child: Text('Master Out')),
      ],
      onChanged: (checkout) {
        if (checkout != null) onChanged(_copy(checkoutType: checkout));
      },
    ),
  );

  Widget _legsField(double width) => SizedBox(
    width: width,
    child: DropdownButtonFormField<int>(
      key: ValueKey('league-legs-${value.bestOfLegs}'),
      initialValue: value.bestOfLegs,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Best of Legs'),
      items:
          ([
                ...TournamentGameFormat.supportedBestOfLegs,
                if (value.bestOfSets == 1)
                  ...TournamentGameFormat.supportedDrawLegs,
              ]..sort())
              .map(
                (legs) =>
                    DropdownMenuItem(value: legs, child: Text('$legs Legs')),
              )
              .toList(),
      onChanged: (legs) {
        if (legs != null) onChanged(_copy(bestOfLegs: legs));
      },
    ),
  );

  Widget _setsField(double width) => SizedBox(
    width: width,
    child: DropdownButtonFormField<int>(
      key: ValueKey('league-sets-${value.bestOfSets}'),
      initialValue: value.bestOfSets,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Best of Sets'),
      items: const [1, 3, 5]
          .map(
            (sets) => DropdownMenuItem(
              value: sets,
              child: Text(sets == 1 ? 'Nur Legs' : '$sets Sets'),
            ),
          )
          .toList(),
      onChanged: (sets) {
        if (sets != null) onChanged(_copy(bestOfSets: sets));
      },
    ),
  );

  Widget _doubleInField(double width) => SizedBox(
    width: width,
    child: DropdownButtonFormField<bool>(
      key: ValueKey('league-double-in-${value.doubleIn}'),
      initialValue: value.doubleIn,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Double In'),
      items: const [
        DropdownMenuItem(value: false, child: Text('Nein')),
        DropdownMenuItem(value: true, child: Text('Ja')),
      ],
      onChanged: (doubleIn) {
        if (doubleIn != null) onChanged(_copy(doubleIn: doubleIn));
      },
    ),
  );

  TournamentGameFormat _copy({
    int? x01Score,
    String? checkoutType,
    int? bestOfLegs,
    int? bestOfSets,
    bool? doubleIn,
  }) {
    final sets = bestOfSets ?? value.bestOfSets;
    final legs = bestOfLegs ?? value.bestOfLegs;
    return TournamentGameFormat(
      x01Score: x01Score ?? value.x01Score,
      checkoutType: checkoutType ?? value.checkoutType,
      bestOfLegs: sets > 1 && legs.isEven ? legs + 1 : legs,
      bestOfSets: sets,
      doubleIn: doubleIn ?? value.doubleIn,
    );
  }
}
