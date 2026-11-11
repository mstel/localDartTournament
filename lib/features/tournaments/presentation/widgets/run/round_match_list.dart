import 'package:flutter/material.dart';
import '../../../domain/tournament_models.dart';
import 'result_entry.dart';
import '../../../../../shared/widgets/adaptive_content.dart';

/// Shows one round at a time instead of every future pairing on a phone.
class RoundMatchList extends StatefulWidget {
  const RoundMatchList({
    super.key,
    required this.rounds,
    required this.onEditResult,
    required this.canEditResults,
    this.labels,
    this.openOnly = false,
    this.useColumns = false,
    this.originLabelFor,
    this.leadingLabelFor,
  });
  final List<List<GroupMatch>> rounds;
  final List<String>? labels;
  final bool openOnly;
  final bool useColumns;
  final String? Function(GroupMatch)? originLabelFor, leadingLabelFor;
  final ValueChanged<GroupMatch> onEditResult;
  final bool canEditResults;
  @override
  State<RoundMatchList> createState() => _RoundMatchListState();
}

class _RoundMatchListState extends State<RoundMatchList>
    with AutomaticKeepAliveClientMixin {
  int? _selected;
  bool _restored = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_restored && widget.key != null) {
      final stored = PageStorage.maybeOf(
        context,
      )?.readState(context, identifier: widget.key);
      if (stored is int) _selected = stored;
      _restored = true;
    }
  }

  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final available = [
      for (var i = 0; i < widget.rounds.length; i++)
        if (!widget.openOnly || widget.rounds[i].any((m) => !m.isResolved)) i,
    ];
    if (available.isEmpty) return const Text('Keine offenen Begegnungen.');
    final firstReady = available
        .where(
          (i) => widget.rounds[i].any((m) => m.hasPlayers && !m.isResolved),
        )
        .firstOrNull;
    final selected = available.contains(_selected)
        ? _selected!
        : firstReady ?? available.first;
    final matches = widget.rounds[selected].where(
      (m) => !widget.openOnly || !m.isResolved,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (available.length > 1) ...[
          DropdownButtonFormField<int>(
            key: ValueKey('round-$selected'),
            initialValue: selected,
            isExpanded: true,
            itemHeight: null,
            decoration: const InputDecoration(labelText: 'Runde'),
            items: [
              for (final i in available)
                DropdownMenuItem(
                  value: i,
                  child: Text(
                    '${widget.labels?[i] ?? 'Runde ${i + 1}'} · ${widget.rounds[i].every((m) => m.isResolved) ? '${widget.rounds[i].length} Ergebnisse' : '${widget.rounds[i].where((m) => !m.isResolved).length} offen'}',
                  ),
                ),
            ],
            onChanged: (value) {
              setState(() => _selected = value);
              if (widget.key != null) {
                PageStorage.maybeOf(
                  context,
                )?.writeState(context, value, identifier: widget.key);
              }
            },
          ),
          const SizedBox(height: 12),
        ],
        if (widget.useColumns)
          AdaptiveTileLayout(
            minTileWidth: 360,
            children: [
              for (final match in matches)
                MatchResultTile(
                  match: match,
                  onEditResult: widget.onEditResult,
                  canEditResult: widget.canEditResults,
                  originLabel: widget.originLabelFor?.call(match),
                  leadingLabel:
                      widget.leadingLabelFor?.call(match) ??
                      (match.isDecider
                          ? match.label
                          : widget.labels?[selected]),
                ),
            ],
          )
        else ...[
          for (final match in matches)
            MatchResultTile(
              match: match,
              onEditResult: widget.onEditResult,
              canEditResult: widget.canEditResults,
              originLabel: widget.originLabelFor?.call(match),
              leadingLabel:
                  widget.leadingLabelFor?.call(match) ??
                  (match.isDecider ? match.label : widget.labels?[selected]),
            ),
        ],
      ],
    );
  }
}
