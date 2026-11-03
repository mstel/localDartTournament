import 'package:flutter/material.dart';

import '../../statistics/domain/player_monthly_performance.dart';
import '../../tournaments/data/app_database.dart';

class PlayerPerformanceEntryPage extends StatefulWidget {
  const PlayerPerformanceEntryPage({
    super.key,
    required this.player,
    LocalAppDatabase? database,
  }) : _database = database;

  final PlayerProfile player;
  final LocalAppDatabase? _database;

  @override
  State<PlayerPerformanceEntryPage> createState() =>
      _PlayerPerformanceEntryPageState();
}

class _PlayerPerformanceEntryPageState
    extends State<PlayerPerformanceEntryPage> {
  static const _months = [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ];

  late final LocalAppDatabase _database =
      widget._database ?? LocalAppDatabase();
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;
  final _legsController = TextEditingController();
  final _scoringController = TextEditingController();
  final _averageController = TextEditingController();
  final _checkoutController = TextEditingController();
  late Future<PlayerMonthlyPerformance?> _entry;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _entry = _loadEntry();
    _entry.then(_populate, onError: (Object _) {});
  }

  Future<PlayerMonthlyPerformance?> _loadEntry() async {
    final entries = await _database.loadPlayerMonthlyPerformance(
      widget.player.id,
      year: _year,
    );
    return entries.where((entry) => entry.month == _month).firstOrNull;
  }

  void _selectPeriod({int? year, int? month}) {
    late final Future<PlayerMonthlyPerformance?> entry;
    setState(() {
      _year = year ?? _year;
      _month = month ?? _month;
      entry = _loadEntry();
      _entry = entry;
      _error = null;
    });
    entry.then((value) {
      if (mounted && identical(_entry, entry)) _populate(value);
    }, onError: (Object _) {});
  }

  void _populate(PlayerMonthlyPerformance? entry) {
    _legsController.text = '${entry?.weightedLegs ?? 0}';
    _scoringController.text = entry?.scoring?.toString() ?? '';
    _averageController.text = entry?.average?.toString() ?? '';
    _checkoutController.text = entry?.checkoutRate?.toString() ?? '';
  }

  double? _optionalNumber(TextEditingController controller) {
    final value = controller.text.trim();
    if (value.isEmpty) return null;
    return double.tryParse(value.replaceAll(',', '.'));
  }

  Future<void> _save() async {
    final legs = int.tryParse(_legsController.text.trim());
    final scoring = _optionalNumber(_scoringController);
    final average = _optionalNumber(_averageController);
    final checkout = _optionalNumber(_checkoutController);
    if (legs == null ||
        legs < 0 ||
        _scoringController.text.trim().isNotEmpty && scoring == null ||
        _averageController.text.trim().isNotEmpty && average == null ||
        _checkoutController.text.trim().isNotEmpty && checkout == null ||
        scoring != null && (!scoring.isFinite || scoring < 0) ||
        average != null && (!average.isFinite || average < 0) ||
        checkout != null &&
            (!checkout.isFinite || checkout < 0 || checkout > 100)) {
      setState(
        () => _error =
            'Bitte gültige Werte eingeben. Die Checkout-Quote muss zwischen 0 und 100 liegen.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _database.savePlayerMonthlyPerformance(
        PlayerMonthlyPerformance(
          playerId: widget.player.id,
          year: _year,
          month: _month,
          weightedLegs: legs,
          scoring: scoring,
          average: average,
          checkoutRate: checkout,
        ),
      );
      if (!mounted) return;
      setState(() => _entry = _loadEntry());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Performance für ${_months[_month - 1]} $_year gespeichert.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Speichern fehlgeschlagen: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _legsController.dispose();
    _scoringController.dispose();
    _averageController.dispose();
    _checkoutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Performance Stats · ${widget.player.displayName}'),
    ),
    body: FutureBuilder<PlayerMonthlyPerformance?>(
      future: _entry,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Performance-Daten konnten nicht geladen werden: ${snapshot.error}',
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final years = [
          for (var year = DateTime.now().year; year >= 2000; year--) year,
        ];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Monatliche Werte manuell erfassen. Nicht eingetragene Kennzahlen werden bei Mittelwerten ausgelassen.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final selectors = [
                  DropdownButtonFormField<int>(
                    initialValue: _month,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Monat',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (var month = 1; month <= 12; month++)
                        DropdownMenuItem(
                          value: month,
                          child: Text(_months[month - 1]),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) _selectPeriod(month: value);
                    },
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: _year,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Jahr',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final year in years)
                        DropdownMenuItem(value: year, child: Text('$year')),
                    ],
                    onChanged: (value) {
                      if (value != null) _selectPeriod(year: value);
                    },
                  ),
                ];
                return constraints.maxWidth >= 600
                    ? Row(
                        children: [
                          Expanded(child: selectors[0]),
                          const SizedBox(width: 12),
                          Expanded(child: selectors[1]),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          selectors[0],
                          const SizedBox(height: 12),
                          selectors[1],
                        ],
                      );
              },
            ),
            const SizedBox(height: 16),
            Text(
              snapshot.data == null
                  ? 'Für diesen Monat sind noch keine Daten erfasst.'
                  : 'Vorhandene Monatsdaten bearbeiten.',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('performance-weighted-legs'),
              controller: _legsController,
              decoration: const InputDecoration(
                labelText: 'Gewertete Legs',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('performance-scoring'),
              controller: _scoringController,
              decoration: const InputDecoration(
                labelText: 'Scoring',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('performance-average'),
              controller: _averageController,
              decoration: const InputDecoration(
                labelText: 'Average',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('performance-checkout'),
              controller: _checkoutController,
              decoration: const InputDecoration(
                labelText: 'Checkout%',
                suffixText: '%',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Speichert …' : 'Monatswerte speichern'),
              ),
            ),
          ],
        );
      },
    ),
  );
}
