import 'package:flutter/material.dart';

import '../../statistics/domain/performance_snapshot.dart';
import '../../statistics/domain/player_monthly_performance.dart';
import '../../tournaments/data/app_database.dart';

enum _PerformanceEntryMode { direct, scolia }

class _PerformanceEntryData {
  const _PerformanceEntryData({required this.direct, required this.snapshots});

  final PlayerMonthlyPerformance? direct;
  final List<PerformanceSnapshot> snapshots;

  PerformanceSnapshot? snapshotFor(int year, int month) {
    for (final snapshot in snapshots) {
      if (snapshot.year == year && snapshot.month == month) return snapshot;
    }
    return null;
  }
}

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
  final _matchesController = TextEditingController();
  final _newLegsController = TextEditingController();
  final _scoringController = TextEditingController();
  final _averageController = TextEditingController();
  final _checkoutController = TextEditingController();
  late Future<_PerformanceEntryData> _entry;
  _PerformanceEntryData? _loadedData;
  PlayerMonthlyPerformance? _loadedEntry;
  PerformanceSnapshot? _loadedSnapshot;
  _PerformanceEntryMode _mode = _PerformanceEntryMode.direct;
  bool _needsNewLegsOverride = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _entry = _loadEntry();
    _entry.then(_populate, onError: (Object _) {});
  }

  Future<_PerformanceEntryData> _loadEntry() async {
    final entries = await _database.loadPlayerMonthlyPerformance(
      widget.player.id,
      year: _year,
    );
    final snapshots = await _database.loadPerformanceSnapshots(
      widget.player.id,
    );
    return _PerformanceEntryData(
      direct: entries.where((entry) => entry.month == _month).firstOrNull,
      snapshots: snapshots,
    );
  }

  void _reload() {
    final entry = _loadEntry();
    setState(() {
      _entry = entry;
    });
    entry.then((value) {
      if (mounted && identical(_entry, entry)) _populate(value);
    }, onError: (Object _) {});
  }

  void _selectPeriod({int? year, int? month}) {
    setState(() {
      _year = year ?? _year;
      _month = month ?? _month;
      _error = null;
    });
    _reload();
  }

  void _selectMode(_PerformanceEntryMode mode) {
    setState(() => _mode = mode);
    final data = _loadedData;
    if (data != null) _populate(data);
  }

  void _populate(_PerformanceEntryData data) {
    _loadedData = data;
    _loadedEntry = data.direct;
    _loadedSnapshot = data.snapshotFor(_year, _month);
    if (_loadedSnapshot != null) _mode = _PerformanceEntryMode.scolia;

    _needsNewLegsOverride = false;
    if (_mode == _PerformanceEntryMode.scolia) {
      final snapshot = _loadedSnapshot;
      _legsController.text =
          '${snapshot?.windowLegs ?? data.direct?.weightedLegs ?? 0}';
      _matchesController.text =
          '${snapshot?.matches ?? data.direct?.matches ?? 0}';
      _scoringController.text =
          (snapshot?.scoring ?? data.direct?.scoring)?.toString() ?? '';
      _averageController.text =
          (snapshot?.average ?? data.direct?.average)?.toString() ?? '';
      _checkoutController.text =
          (snapshot?.checkoutRate ?? data.direct?.checkoutRate)?.toString() ??
          '';
      final derived = derivePerformanceMonths(
        data.snapshots,
      ).monthFor('$_year-${_month.toString().padLeft(2, '0')}');
      _needsNewLegsOverride = derived?.isEstimated ?? false;
      _newLegsController.text = _needsNewLegsOverride
          ? derived!.weightedLegs.toString()
          : '';
      return;
    }

    _legsController.text = '${data.direct?.weightedLegs ?? 0}';
    _scoringController.text = data.direct?.scoring?.toString() ?? '';
    _averageController.text = data.direct?.average?.toString() ?? '';
    _checkoutController.text = data.direct?.checkoutRate?.toString() ?? '';
  }

  double? _optionalNumber(TextEditingController controller) {
    final value = controller.text.trim();
    if (value.isEmpty) return null;
    return double.tryParse(value.replaceAll(',', '.'));
  }

  int? _nonNegativeInt(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    return value == null || value < 0 ? null : value;
  }

  Widget _numberField({
    required String fieldKey,
    required String label,
    required TextEditingController controller,
    bool decimal = false,
    String? suffixText,
  }) => TextField(
    key: ValueKey(fieldKey),
    controller: controller,
    decoration: InputDecoration(
      labelText: label,
      suffixText: suffixText,
      border: const OutlineInputBorder(),
    ),
    keyboardType: decimal
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.number,
  );

  Future<void> _save() async {
    final legs = _nonNegativeInt(_legsController);
    final matches = _nonNegativeInt(_matchesController);
    final newLegs = _newLegsController.text.trim().isEmpty
        ? null
        : _nonNegativeInt(_newLegsController);
    final scoring = _optionalNumber(_scoringController);
    final average = _optionalNumber(_averageController);
    final checkout = _optionalNumber(_checkoutController);
    final isScolia = _mode == _PerformanceEntryMode.scolia;
    if (legs == null ||
        isScolia && legs > 100 ||
        isScolia && (matches == null || matches > 100) ||
        _needsNewLegsOverride && (newLegs == null || newLegs < 1) ||
        _scoringController.text.trim().isNotEmpty && scoring == null ||
        _averageController.text.trim().isNotEmpty && average == null ||
        _checkoutController.text.trim().isNotEmpty && checkout == null ||
        scoring != null && (!scoring.isFinite || scoring < 0) ||
        average != null && (!average.isFinite || average < 0) ||
        checkout != null &&
            (!checkout.isFinite || checkout < 0 || checkout > 100)) {
      setState(
        () => _error = isScolia
            ? 'Bitte gültige Scolia-Werte eingeben: 0 bis 100 Legs, '
                  'nicht negative Partien und eine Checkout-Quote zwischen 0 '
                  'und 100 %. Bei vollem Fenster bitte die neuen Legs angeben.'
            : 'Bitte gültige, nicht negative ganze Zahlen für die gewerteten '
                  'Legs eingeben. Die Checkout-Quote muss zwischen 0 und 100 liegen.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (isScolia) {
        final snapshot = PerformanceSnapshot.create(
          id:
              _loadedSnapshot?.id ??
              '${widget.player.id}-$_year-${_month.toString().padLeft(2, '0')}',
          playerId: widget.player.id,
          year: _year,
          month: _month,
          windowLegs: legs,
          matches: matches ?? 0,
          scoring: scoring,
          average: average,
          checkoutRate: checkout,
          newLegsOverride: _needsNewLegsOverride ? newLegs : null,
          note: _needsNewLegsOverride
              ? 'Monatstrennung bei vollem Scolia-Fenster bestätigt.'
              : '',
          updatedAt: DateTime.now(),
        );
        final derived = await _database.savePerformanceSnapshotAndRebuild(
          snapshot,
        );
        if (!mounted) return;
        _reload();
        final month = derived
            .where((entry) => entry.year == _year && entry.month == _month)
            .firstOrNull;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              month == null
                  ? 'Scolia-Messpunkt gespeichert. Es gab keine neuen Legs.'
                  : 'Monatswert abgeleitet: ${month.weightedLegs} Legs'
                        '${month.average == null ? '' : ', Average ${month.average!.toStringAsFixed(2)}'}'
                        '${month.isEstimated ? ' (geschätzt)' : ''}.',
            ),
          ),
        );
        return;
      }

      final entry = PlayerMonthlyPerformance(
        playerId: widget.player.id,
        year: _year,
        month: _month,
        weightedLegs: legs,
        // Match counts, wins and losses are derived from assigned tournaments
        // and must survive edits of the manually recorded performance values.
        matches: _loadedEntry?.matches ?? 0,
        wins: _loadedEntry?.wins ?? 0,
        losses: _loadedEntry?.losses ?? 0,
        scoring: scoring,
        average: average,
        checkoutRate: checkout,
        source: _loadedEntry?.source ?? 'manual',
      );
      await _database.savePlayerMonthlyPerformance(entry);
      if (!mounted) return;
      _loadedEntry = entry;
      _reload();
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
    _matchesController.dispose();
    _newLegsController.dispose();
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
    body: FutureBuilder<_PerformanceEntryData>(
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
        final data = snapshot.data!;
        final derivedForPeriod = _mode == _PerformanceEntryMode.scolia
            ? derivePerformanceMonths(
                data.snapshots,
              ).monthFor('$_year-${_month.toString().padLeft(2, '0')}')
            : null;
        final needsOverride = derivedForPeriod?.isEstimated ?? false;
        final years = [
          for (var year = DateTime.now().year; year >= 2000; year--) year,
        ];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SegmentedButton<_PerformanceEntryMode>(
              key: const ValueKey('performance-entry-mode'),
              segments: const [
                ButtonSegment(
                  value: _PerformanceEntryMode.direct,
                  label: Text('Monatswerte'),
                  icon: Icon(Icons.calendar_month_outlined),
                ),
                ButtonSegment(
                  value: _PerformanceEntryMode.scolia,
                  label: Text('Scolia kumulativ'),
                  icon: Icon(Icons.trending_up_outlined),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) => _selectMode(selection.first),
            ),
            const SizedBox(height: 12),
            Text(
              _mode == _PerformanceEntryMode.scolia
                  ? 'Ab Oktober 2026 die aktuell in Scolia angezeigten '
                        'Gesamtwerte eintragen. Die App speichert jeden Messpunkt '
                        'und berechnet daraus den eigenständigen Monatswert. '
                        'Bestehende Monate bis September 2026 bleiben unverändert.'
                  : 'Gewertete Legs und Durchschnittswerte manuell erfassen. '
                        'Partien, Gewonnen, Verloren und Siegesrate werden '
                        'automatisch aus den zugewiesenen Turnieren berechnet.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final selectors = [
                  DropdownButtonFormField<int>(
                    key: const ValueKey('performance-month'),
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
                    key: const ValueKey('performance-year'),
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
              _mode == _PerformanceEntryMode.scolia
                  ? _loadedSnapshot == null
                        ? 'Neuer kumulierter Messpunkt für diesen Monat.'
                        : 'Vorhandenen Messpunkt bearbeiten.'
                  : data.direct == null
                  ? 'Für diesen Monat sind noch keine Daten erfasst.'
                  : 'Vorhandene Monatsdaten bearbeiten.',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final isScolia = _mode == _PerformanceEntryMode.scolia;
                final columns = constraints.maxWidth >= 900
                    ? 4
                    : constraints.maxWidth >= 600
                    ? 2
                    : 1;
                const gap = 12.0;
                final fieldWidth =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    if (isScolia)
                      SizedBox(
                        width: fieldWidth,
                        child: _numberField(
                          fieldKey: 'performance-scolia-matches',
                          label: 'Gespielte Spiele',
                          controller: _matchesController,
                        ),
                      ),
                    SizedBox(
                      width: fieldWidth,
                      child: _numberField(
                        fieldKey: 'performance-weighted-legs',
                        label: isScolia
                            ? 'Legs (Scolia-Fenster)'
                            : 'Gewertete Legs',
                        controller: _legsController,
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: _numberField(
                        fieldKey: 'performance-scoring',
                        label: isScolia ? 'Scoring (bis 101)' : 'Scoring',
                        controller: _scoringController,
                        decimal: true,
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: _numberField(
                        fieldKey: 'performance-average',
                        label: isScolia ? 'Average (inkl. Finish)' : 'Average',
                        controller: _averageController,
                        decimal: true,
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: _numberField(
                        fieldKey: 'performance-checkout',
                        label: 'Checkout%',
                        controller: _checkoutController,
                        decimal: true,
                        suffixText: '%',
                      ),
                    ),
                  ],
                );
              },
            ),
            if (_mode == _PerformanceEntryMode.scolia && needsOverride) ...[
              const SizedBox(height: 12),
              Container(
                key: const ValueKey('performance-scolia-window-info'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Das Scolia-Fenster umfasst 100 Legs. Ältere Legs sind bereits '
                  'herausgefallen, deshalb ist die Monatstrennung nicht mehr '
                  'eindeutig. Bitte prüfe die geschätzten neuen Legs.',
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _numberField(
                  fieldKey: 'performance-scolia-new-legs',
                  label: 'Neue Legs im Monat',
                  controller: _newLegsController,
                ),
              ),
            ],
            if (derivedForPeriod case final derived?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Abgeleiteter Monatswert: ${derived.weightedLegs} Legs'
                  '${derived.average == null ? '' : ', Average ${derived.average!.toStringAsFixed(2)}'}'
                  '${derived.isEstimated ? ' (geschätzt)' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
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
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
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
