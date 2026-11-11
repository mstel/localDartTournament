import 'package:flutter/material.dart';

import '../../../domain/tournament_models.dart';
import '../../../../statistics/domain/best_performance.dart';

class BestPerformanceEditor extends StatefulWidget {
  const BestPerformanceEditor({
    super.key,
    required this.match,
    required this.initial,
    required this.onChanged,
  });

  final GroupMatch match;
  final List<BestPerformance> initial;
  final ValueChanged<List<BestPerformance>> onChanged;

  @override
  State<BestPerformanceEditor> createState() => _BestPerformanceEditorState();
}

class _BestPerformanceEditorState extends State<BestPerformanceEditor> {
  late final List<BestPerformance> _items = [...widget.initial];
  BestPerformanceType _type = BestPerformanceType.score180;
  String? _playerId;
  final TextEditingController _value = TextEditingController();

  List<TournamentPlayer> get _players => [
    if (widget.match.homePlayer != null) widget.match.homePlayer!,
    if (widget.match.awayPlayer != null) widget.match.awayPlayer!,
  ];

  @override
  void initState() {
    super.initState();
    final home = widget.match.homePlayer;
    _playerId = home == null ? null : (home.profileId ?? home.name);
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _add() {
    final players = _players;
    if (players.isEmpty) return;
    final player = players.firstWhere(
      (candidate) => (candidate.profileId ?? candidate.name) == _playerId,
      orElse: () => players.first,
    );
    final value = int.tryParse(_value.text.trim());
    final details = _value.text.trim();
    if ((_type == BestPerformanceType.highFinish &&
            (value == null || value < 100 || value > 170)) ||
        (_type == BestPerformanceType.shortLeg &&
            (value == null || value < 1 || value > 18)) ||
        (_type == BestPerformanceType.bullseyeFinish && details.isEmpty)) {
      return;
    }
    setState(() {
      _items.add(
        BestPerformance(
          type: _type,
          playerName: player.name,
          playerProfileId: player.profileId,
          value: value,
          details: _type == BestPerformanceType.bullseyeFinish ? details : null,
        ),
      );
      _value.clear();
    });
    widget.onChanged(List.unmodifiable(_items));
  }

  @override
  Widget build(BuildContext context) {
    final players = _players;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_items.isNotEmpty)
          for (var index = 0; index < _items.length; index++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${_items[index].playerName}: ${_items[index].label}'
                '${_items[index].value == null ? '' : ' ${_items[index].value}'}'
                '${_items[index].details == null ? '' : ' · ${_items[index].details}'}',
              ),
              trailing: IconButton(
                tooltip: 'Bestleistung entfernen',
                onPressed: () {
                  setState(() => _items.removeAt(index));
                  widget.onChanged(List.unmodifiable(_items));
                },
                icon: const Icon(Icons.delete_outline),
              ),
            ),
        if (players.isNotEmpty)
          DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _playerId,
            decoration: const InputDecoration(labelText: 'Teilnehmer'),
            items: [
              for (final player in players)
                DropdownMenuItem<String?>(
                  value: player.profileId ?? player.name,
                  child: Text(player.name),
                ),
            ],
            onChanged: (value) => setState(() => _playerId = value),
          ),
        const SizedBox(height: 8),
        DropdownButtonFormField<BestPerformanceType>(
          isExpanded: true,
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Bestleistung'),
          items: [
            for (final type in _selectableTypes)
              DropdownMenuItem(value: type, child: Text(_label(type))),
          ],
          onChanged: (value) => setState(() => _type = value ?? _type),
        ),
        if (_type == BestPerformanceType.highFinish ||
            _type == BestPerformanceType.shortLeg ||
            _type == BestPerformanceType.bullseyeFinish) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _value,
            keyboardType: _type == BestPerformanceType.bullseyeFinish
                ? TextInputType.text
                : TextInputType.number,
            decoration: InputDecoration(
              labelText: switch (_type) {
                BestPerformanceType.highFinish => 'Finish (100–170)',
                BestPerformanceType.shortLeg => 'Darts (1–18)',
                BestPerformanceType.bullseyeFinish => 'Finish beschreiben',
                _ => null,
              },
              hintText: _type == BestPerformanceType.bullseyeFinish
                  ? 'z. B. Bullseye'
                  : null,
            ),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: players.isEmpty ? null : _add,
          icon: const Icon(Icons.add),
          label: const Text('Bestleistung hinzufügen'),
        ),
      ],
    );
  }

  String _label(BestPerformanceType type) => switch (type) {
    BestPerformanceType.bigFish170 => '170 (Big Fish)',
    BestPerformanceType.score171Plus => '171+',
    BestPerformanceType.score180 => '180+',
    BestPerformanceType.highFinish => 'High Finish',
    BestPerformanceType.bullseyeFinish => 'Bullseye Finish',
    BestPerformanceType.shortLeg => 'Shortleg',
    BestPerformanceType.score170 => '171+',
  };

  static const _selectableTypes = [
    BestPerformanceType.bigFish170,
    BestPerformanceType.score171Plus,
    BestPerformanceType.score180,
    BestPerformanceType.highFinish,
    BestPerformanceType.bullseyeFinish,
    BestPerformanceType.shortLeg,
  ];
}
