import 'package:flutter/material.dart';

class TripleKoPreviewPhase {
  const TripleKoPreviewPhase({
    required this.title,
    required this.roundCount,
    required this.encounterCount,
    required this.child,
  });

  final String title;
  final int roundCount;
  final int encounterCount;
  final Widget child;
}

class TripleKoPreviewSections extends StatelessWidget {
  const TripleKoPreviewSections({
    super.key,
    required this.phases,
    required this.finalChild,
  });

  final List<TripleKoPreviewPhase> phases;
  final Widget finalChild;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < phases.length; index++) ...[
          ExpansionTile(
            key: ValueKey('triple-preview-loss-level-$index'),
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            childrenPadding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            collapsedShape: RoundedRectangleBorder(
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            title: Text(phases[index].title),
            subtitle: Text(
              '${phases[index].roundCount} Runden · '
              '${phases[index].encounterCount} Begegnungen',
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: phases[index].child,
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        finalChild,
      ],
    );
  }
}
