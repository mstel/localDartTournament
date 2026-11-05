import 'package:flutter/material.dart';

import '../../tournaments/application/group_tie_breaker_preferences.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../../tournaments/presentation/widgets/creation/stage_setup_widgets.dart';

class TieBreakerDefaultsPanel extends StatefulWidget {
  const TieBreakerDefaultsPanel({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  State<TieBreakerDefaultsPanel> createState() =>
      _TieBreakerDefaultsPanelState();
}

class _TieBreakerDefaultsPanelState extends State<TieBreakerDefaultsPanel> {
  final _preferences = GroupTieBreakerPreferences();
  List<String> _tieBreakers = List<String>.from(defaultGroupTieBreakers);
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final saved = await _preferences.load();
      if (!mounted) return;
      setState(() => _tieBreakers = List<String>.from(saved));
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error =
            'Standard-Tie-Breaker konnten nicht geladen werden: $error',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _move(int index, int direction) async {
    final nextIndex = index + direction;
    if (nextIndex < 0 ||
        nextIndex >= _tieBreakers.length ||
        _loading ||
        _saving) {
      return;
    }
    final previous = List<String>.from(_tieBreakers);
    final updated = List<String>.from(_tieBreakers);
    final value = updated.removeAt(index);
    updated.insert(nextIndex, value);
    setState(() {
      _tieBreakers = updated;
      _saving = true;
      _error = null;
    });
    try {
      await _preferences.save(updated);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _tieBreakers = previous;
        _error =
            'Standard-Tie-Breaker konnten nicht gespeichert werden: $error';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Diese Reihenfolge wird bei neuen Turnieren voreingestellt. Mit den Pfeilen lässt sie sich dauerhaft anpassen.',
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error case final error?) ...[
          const SizedBox(height: 12),
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(onPressed: _load, child: const Text('Erneut laden')),
        ],
        const SizedBox(height: 12),
        GroupTieBreakerSetup(
          tieBreakers: _tieBreakers,
          onMoveTieBreaker: _move,
        ),
        const SizedBox(height: 12),
        const Text(
          'Standard: Matchpunkte, Leg-Differenz, gewonnene Legs, direkter Vergleich.',
        ),
      ],
    );
    if (!widget.showTitle) return content;
    return ExpansionTile(
      leading: const Icon(Icons.rule_folder_outlined),
      title: const Text('Tie Breaker Standardwerte'),
      subtitle: const Text('Reihenfolge der Tabellenwertung festlegen.'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [content],
    );
  }
}
