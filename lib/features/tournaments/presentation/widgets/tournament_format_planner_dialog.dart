part of '../../../../tournament_workspace.dart';

class TournamentFormatPlannerDialog extends StatefulWidget {
  const TournamentFormatPlannerDialog({super.key});
  @override
  State<TournamentFormatPlannerDialog> createState() =>
      _TournamentFormatPlannerDialogState();
}

class _TournamentFormatPlannerDialogState
    extends State<TournamentFormatPlannerDialog> {
  final _players = TextEditingController(text: '8');
  final _boards = TextEditingController(text: '4');
  final _maximumGroups = TextEditingController();
  String? _maximumGroupsError;
  final _manualQualifiers = TextEditingController();
  String? _manualQualifiersError;
  int _bestOfLegs = 3;
  bool _lockLegsFormat = true;
  final _structureKey = GlobalKey<SportSettingsSectionState>();
  final _minimumMatches = TextEditingController(text: '3');
  // Duration fields: store as whole minutes to avoid decimal confusion
  final _minHours = TextEditingController(text: '2');
  final _minMinutes = TextEditingController(text: '0');
  final _maxHours = TextEditingController(text: '4');
  final _maxMinutes = TextEditingController(text: '0');
  final _targetHours = TextEditingController(text: '3');
  final _targetMinutes = TextEditingController(text: '0');
  bool _useTargetDuration = false;
  String? _targetError;
  String? _durationError;
  String _checkoutType = 'double_out';
  final _scrollController = ScrollController();
  final _resultsKey = GlobalKey();

  String _x01Selection = '501';

  List<TournamentFormatSuggestion>? _suggestions;
  bool _calculating = false;
  bool _cancelled = false;
  VoidCallback? _cancelCalculation;
  void _cancel() {
    _cancelled = true;
    _cancelCalculation?.call();
  }

  bool _allowSets = false;
  bool _allowDraws = false;
  bool _requireGroupPhase = false;
  int _maximumStages = 2;
  int _maximumLives = 5;
  int _suggestionPageSize = 3;
  String? _preferredFinalStage = 'single_knockout';
  final Set<String> _enabledModes = {
    'groups:round_robin',
    'groups:double_round_robin',
    'groups:limited_round_robin',
  };

  static const _modeDescriptions = <String, String>{
    'single_knockout':
        'Einfaches K.-o.-System (Single Elimination):\n\n'
        'Wer eine Begegnung verliert, scheidet sofort aus dem Turnier aus. Der Gewinner zieht in die nächste Runde ein, bis im Finale der Turniersieger ermittelt wird.',
    'double_knockout':
        'Doppel-K.-o.-System (Double Elimination):\n\n'
        'Jeder Spieler hat zwei Chancen. Wer in der Hauptrunde (Winners Bracket) verliert, scheidet nicht aus, sondern wechselt in die Verliererrunde (Losers Bracket). Erst bei der zweiten Niederlage scheidet ein Teilnehmer endgültig aus.',
    'triple_knockout':
        'Triple-K.-o.-System (Triple Elimination):\n\n'
        'Jeder Spieler scheidet erst nach der dritten Niederlage aus. Neben der Hauptrunde gibt es zwei Auffangrunden (B- und C-Bracket), wodurch allen Teilnehmern mindestens drei garantierte K.-o.-Partien geboten werden.',
    'kratzer':
        'Kratzer-Modus (Leben-System):\n\n'
        'Alle Teilnehmer starten mit einer festen Anzahl an Leben (z. B. 3 bis 5 Leben). Jede verlorene Partie kostet ein Leben („Kratzer“). Wer alle Leben aufgebraucht hat, scheidet aus. Die verbleibenden Spieler treten gegeneinander an, bis nur noch ein Sieger übrig ist.',
    'groups:round_robin':
        'Gruppenphase: Jeder gegen jeden (einmal):\n\n'
        'Innerhalb jeder Gruppe spielt jeder Teilnehmer genau einmal gegen jeden anderen Gruppengegner. Die Rangfolge ergibt sich aus Siegen, Leg-Differenz und direktem Vergleich.',
    'groups:double_round_robin':
        'Gruppenphase: Jeder gegen jeden (zweimal):\n\n'
        'Innerhalb jeder Gruppe spielt jeder Teilnehmer zweimal gegen jeden anderen Gruppengegner. Die doppelte Spielanzahl gibt eine breitere Bewertungsgrundlage, verlängert aber die Turnierdauer.',
    'groups:limited_round_robin':
        'Gruppenphase: Rundenformat mit max. 5 Spielen:\n\n'
        'Für größere Teilnehmergruppen: Jeder Spieler absolviert maximal 5 festgelegte Runden gegen verschiedene Gegner, um die Turnierdauer verlässlich einzugrenzen, ohne dass alle Kombinationen ausgespielt werden müssen.',
    'groups:swiss':
        'Schweizer System:\n\n'
        'In jeder Spielrunde werden Teilnehmer mit identischem oder ähnlichem Punktestand gegeneinander gepaart. Niemand scheidet vorzeitig aus, und die Spiele bleiben durch das dynamische Nachrücken bis zum Ende ausgeglichen.',
    'groups:mini_knockout':
        'Gruppenphase: Mini-K.-o.:\n\n'
        'Innerhalb der Gruppe wird ein kleines K.-o.-Raster (z. B. 4 Spieler: Halbfinale und Finale) gespielt. Die Sieger qualifizieren sich direkt für die nächste Turnieretappe.',
    'groups:double_knockout':
        'Gruppenphase: Mini-Doppel-K.-o.:\n\n'
        'Wie das Mini-K.-o., jedoch mit Verlierer-Runde innerhalb der Gruppe (Double Elimination). Erst zwei Gruppen-Niederlagen führen zum Ausscheiden.',
    'groups:triple_knockout':
        'Gruppenphase: Mini-Triple-K.-o.:\n\n'
        'Gruppenentscheidung mit drei Leben: Erst nach der dritten Niederlage in der Gruppe steht das Ausscheiden fest.',
  };

  Future<void> _pickMinDuration() async {
    final curH = int.tryParse(_minHours.text) ?? 2;
    final curM = int.tryParse(_minMinutes.text) ?? 0;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: curH.clamp(0, 23), minute: curM.clamp(0, 59)),
      helpText: 'Mindestdauer auswählen',
      confirmText: 'Übernehmen',
      cancelText: 'Abbrechen',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _minHours.text = '${picked.hour}';
        _minMinutes.text = '${picked.minute}';
        _suggestions = null;
      });
    }
  }

  Future<void> _pickMaxDuration() async {
    final curH = int.tryParse(_maxHours.text) ?? 4;
    final curM = int.tryParse(_maxMinutes.text) ?? 0;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: curH.clamp(0, 23), minute: curM.clamp(0, 59)),
      helpText: 'Maximaldauer auswählen',
      confirmText: 'Übernehmen',
      cancelText: 'Abbrechen',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _maxHours.text = '${picked.hour}';
        _maxMinutes.text = '${picked.minute}';
        _suggestions = null;
      });
    }
  }

  Future<void> _pickTargetDuration() async {
    final curH = int.tryParse(_targetHours.text) ?? 3;
    final curM = int.tryParse(_targetMinutes.text) ?? 0;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: curH.clamp(0, 23), minute: curM.clamp(0, 59)),
      helpText: 'Wunschdauer auswählen',
      confirmText: 'Übernehmen',
      cancelText: 'Abbrechen',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _targetHours.text = '${picked.hour}';
        _targetMinutes.text = '${picked.minute}';
        _suggestions = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _players,
      _boards,
      _maximumGroups,
      _manualQualifiers,
      _minimumMatches,
      _minHours,
      _minMinutes,
      _maxHours,
      _maxMinutes,
      _targetHours,
      _targetMinutes,
    ]) {
      controller.addListener(() {
        if (_calculating) _cancel();
        if (mounted && _suggestions != null) {
          setState(() => _suggestions = null);
        }
      });
    }
  }

  String get _inputSignature => [
    _players.text,
    _boards.text,
    _maximumGroups.text,
    _manualQualifiers.text,
    _bestOfLegs,
    _lockLegsFormat,
    _minimumMatches.text,
    '${_minHours.text}h${_minMinutes.text}m',
    '${_maxHours.text}h${_maxMinutes.text}m',
    '${_targetHours.text}h${_targetMinutes.text}m',
    _useTargetDuration,
    _checkoutType,
    _x01Selection,
    _allowSets,
    _allowDraws,
    _requireGroupPhase,
    _maximumStages,
    _maximumLives,
    _preferredFinalStage,
    (_enabledModes.toList()..sort()).join(','),
  ].join('|');

  @override
  void dispose() {
    _cancel();
    _scrollController.dispose();
    _maximumGroups.dispose();
    _manualQualifiers.dispose();
    _players.dispose();
    _boards.dispose();
    _minimumMatches.dispose();
    _minHours.dispose();
    _minMinutes.dispose();
    _maxHours.dispose();
    _maxMinutes.dispose();
    _targetHours.dispose();
    _targetMinutes.dispose();
    super.dispose();
  }

  Future<void> _calculate() async {
    // Parse target duration (hours + minutes)
    final th = int.tryParse(_targetHours.text.trim());
    final tm = int.tryParse(_targetMinutes.text.trim());
    final targetTotalMinutes =
        _useTargetDuration ? ((th ?? 0) * 60 + (tm ?? 0)) : null;
    if (_useTargetDuration &&
        (th == null ||
            tm == null ||
            tm < 0 ||
            tm > 59 ||
            targetTotalMinutes! < 1 ||
            targetTotalMinutes > 525600)) {
      setState(() {
        _targetError =
            'Gültige Dauer eingeben (max. 365 Tage). Minuten: 0–59.';
        _suggestions = null;
      });
      return;
    }
    setState(() => _targetError = null);

    // Parse min/max duration (hours + minutes) – Fix 1.1: was int.tryParse only
    final minH = int.tryParse(_minHours.text.trim()) ?? 0;
    final minM = int.tryParse(_minMinutes.text.trim()) ?? 0;
    final maxH = int.tryParse(_maxHours.text.trim()) ?? 4;
    final maxM = int.tryParse(_maxMinutes.text.trim()) ?? 0;
    final minTotal = minH * 60 + minM.clamp(0, 59);
    final maxTotal = maxH * 60 + maxM.clamp(0, 59);

    if (!_useTargetDuration && maxTotal < 1) {
      setState(() {
        _durationError = 'Max. Dauer muss mindestens 1 Minute betragen.';
        _suggestions = null;
      });
      return;
    }
    setState(() => _durationError = null);

    final groupText = _maximumGroups.text.trim();
    final groupLimit = int.tryParse(groupText);
    if (groupText.isNotEmpty &&
        (groupLimit == null || groupLimit < 1 || groupLimit > 64)) {
      _structureKey.currentState?.expand();
      setState(() {
        _maximumGroupsError = 'Ganze Zahl von 1 bis 64 eingeben.';
        _suggestions = null;
      });
      return;
    }
    setState(() => _maximumGroupsError = null);

    final qualifiersText = _manualQualifiers.text.trim();
    final manualQualifiers = int.tryParse(qualifiersText);
    final playersCount = int.tryParse(_players.text.trim()) ?? 0;
    if (qualifiersText.isNotEmpty) {
      if (manualQualifiers == null ||
          manualQualifiers < 2 ||
          manualQualifiers >= playersCount) {
        _structureKey.currentState?.expand();
        setState(() {
          _manualQualifiersError =
              'Zahl von 2 bis ${max(2, playersCount - 1)} eingeben.';
          _suggestions = null;
        });
        return;
      }
    }
    setState(() => _manualQualifiersError = null);

    _cancelled = false;
    setState(() => _calculating = true);
    final inputSignature = _inputSignature;
    try {
      final parameters = await PlanningSettingsStorage().load();
      if (!mounted || _cancelled) return;
      final suggestions = await ExpandedFormatPlanner(parameters: parameters)
          .suggest(
            TournamentPlanningRequest(
              players: playersCount,
              boards: int.tryParse(_boards.text) ?? 0,
              maximumGroups: groupLimit,
              requireGroupPhase: _requireGroupPhase,
              maximumStages: _maximumStages,
              maximumLives: _maximumLives,
              enabledModes: Set.unmodifiable(_enabledModes),
              bestOfLegs: _bestOfLegs,
              lockLegsFormat: _lockLegsFormat,
              manualQualifiers: manualQualifiers,
              minimumMatchesPerPlayer: int.tryParse(_minimumMatches.text) ?? 1,
              minimumMinutes: minTotal,
              maximumMinutes: maxTotal,
              targetMinutes: targetTotalMinutes,
              x01Selection: _x01Selection,
              checkoutType: _checkoutType,
              allowSets: _allowSets,
              allowDraws: _allowDraws,
              preferredFinalStage: _preferredFinalStage,
            ),
            allResults: true,
            onCancel: (cancel) => _cancelCalculation = cancel,
          );
      if (!mounted) return;
      if (_inputSignature != inputSignature) return;
      setState(() {
        _suggestions = suggestions;
        _suggestionPageSize = parameters.maximumSuggestions;
      });
      // Fix 1.7: Scroll to results after calculation
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_resultsKey.currentContext != null) {
          Scrollable.ensureVisible(
            _resultsKey.currentContext!,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (_) {
      if (!mounted || _cancelled) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Einstellungen konnten nicht geladen werden. Bitte erneut versuchen.',
          ),
        ),
      );
    } finally {
      _cancelCalculation = null;
      if (mounted) setState(() => _calculating = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: constraints.maxWidth < 600 ? 12 : 40,
        vertical: 20,
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      title: const Text('Passende Turnierform finden'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Die Schätzung berücksichtigt Runden, begrenzt nutzbare Boards und Wartezeiten zwischen KO-Runden.',
              ),
              const SizedBox(height: 16),
              AdaptiveTileLayout(
                minTileWidth: 220,
                children: [
                  _numberField(_players, 'Anzahl Spieler'),
                  _numberField(_boards, 'Anzahl Boards'),
                  _numberField(_minimumMatches, 'Mindestens Spiele/Spieler'),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final target in [false, true])
                    ChoiceChip(
                      label: Text(target ? 'Wunschdauer' : 'Zeitfenster'),
                      selected: _useTargetDuration == target,
                      padding: const EdgeInsets.all(12),
                      onSelected: _calculating
                          ? null
                          : (_) => setState(() {
                              _useTargetDuration = target;
                              _suggestions = null;
                              _targetError = null;
                              _durationError = null;
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_useTargetDuration) ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('Wunschdauer festlegen'),
                    subtitle: Text(
                      '${_targetHours.text} Std. ${_targetMinutes.text.padLeft(2, '0')} Min. (Vorschläge sortiert nach Nähe)',
                    ),
                    trailing: FilledButton.tonalIcon(
                      onPressed: _calculating ? null : _pickTargetDuration,
                      icon: const Icon(Icons.access_time),
                      label: const Text('Ändern'),
                    ),
                    onTap: _calculating ? null : _pickTargetDuration,
                  ),
                ),
                if (_targetError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 12),
                    child: Text(
                      _targetError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ] else ...[
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 450;
                    final minWidget = Card(
                      child: ListTile(
                        leading: const Icon(Icons.hourglass_top_outlined),
                        title: const Text('Mindestdauer'),
                        subtitle: Text(
                          '${_minHours.text} Std. ${_minMinutes.text.padLeft(2, '0')} Min.',
                        ),
                        trailing: OutlinedButton.icon(
                          onPressed: _calculating ? null : _pickMinDuration,
                          icon: const Icon(Icons.access_time),
                          label: const Text('Ändern'),
                        ),
                        onTap: _calculating ? null : _pickMinDuration,
                      ),
                    );
                    final maxWidget = Card(
                      child: ListTile(
                        leading: const Icon(Icons.hourglass_bottom_outlined),
                        title: const Text('Maximaldauer'),
                        subtitle: Text(
                          '${_maxHours.text} Std. ${_maxMinutes.text.padLeft(2, '0')} Min.',
                        ),
                        trailing: OutlinedButton.icon(
                          onPressed: _calculating ? null : _pickMaxDuration,
                          icon: const Icon(Icons.access_time),
                          label: const Text('Ändern'),
                        ),
                        onTap: _calculating ? null : _pickMaxDuration,
                      ),
                    );
                    if (isNarrow) {
                      return Column(
                        children: [
                          minWidget,
                          const SizedBox(height: 8),
                          maxWidget,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: minWidget),
                        const SizedBox(width: 8),
                        Expanded(child: maxWidget),
                      ],
                    );
                  },
                ),
                if (_durationError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 12),
                    child: Text(
                      _durationError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 16),

              SportSettingsSection(
                title: 'Turnierformen',
                summary:
                    '${_enabledModes.length} Formen in der Suche berücksichtigt',
                icon: Icons.account_tree_outlined,
                children: [
                  const Text('Berücksichtigte Turnierformen'),
                  const Text(
                    'Die Auswahl gilt für jede Etappe. Gruppen-Spielarten können unabhängig von den KO-Etappen gewählt werden.',
                  ),
                  for (final mode
                      in TournamentPlanningRequest.modeLabels.entries)
                    Row(
                      children: [
                        Expanded(
                          child: CheckboxListTile(
                            key: ValueKey('planner-mode-${mode.key}'),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(mode.value),
                            value: _enabledModes.contains(mode.key),
                            onChanged: _calculating
                                ? null
                                : (selected) => setState(() {
                                    if (selected == true) {
                                      _enabledModes.add(mode.key);
                                    } else {
                                      _enabledModes.remove(mode.key);
                                    }
                                    _suggestions = null;
                                  }),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.help_outline, size: 20),
                          tooltip: 'Erklärung zur Turnierform',
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(mode.value),
                              content: Text(
                                _modeDescriptions[mode.key] ??
                                    'Keine Beschreibung vorhanden.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Schließen'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (_enabledModes.isEmpty)
                    const Text('Bitte mindestens eine Turnierform auswählen.'),
                  if (_requireGroupPhase &&
                      !_enabledModes.any((m) => m.startsWith('groups:')))
                    const Text(
                      'Für die erforderliche Gruppenphase bitte eine Gruppen-Spielart auswählen.',
                    ),
                  const SizedBox(height: 16),
                ],
              ),
              SportSettingsSection(
                key: _structureKey,
                title: 'Aufbau & Gruppen',
                summary:
                    'Bis zu $_maximumStages Etappen · ${_requireGroupPhase ? 'mit Gruppenphase' : 'Gruppenphase optional'}',
                icon: Icons.groups_outlined,
                children: [
                  TextField(
                    key: const ValueKey('planner-maximum-groups'),
                    controller: _maximumGroups,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Maximale Gruppenzahl',
                      helperText:
                          'Obergrenze je Gruppenphase, keine Pflicht für Gruppen. Leer: gespeicherter Wert. Mindestens 3 Spieler je Gruppe.',
                      helperMaxLines: 3,
                      errorText: _maximumGroupsError,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('planner-manual-qualifiers'),
                    controller: _manualQualifiers,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Weiterkommende Spieler (Top X / Finalrunde)',
                      helperText:
                          'Anzahl Qualifikanten für die Final-/KO-Runde (z. B. 6 für Top 6 mit Freilosen bei 12 Spielern). Leer: automatisch.',
                      helperMaxLines: 3,
                      errorText: _manualQualifiersError,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    key: const ValueKey('planner-require-groups'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Gruppenphase erforderlich'),
                    value: _requireGroupPhase,
                    onChanged: _calculating
                        ? null
                        : (value) => setState(() {
                            _requireGroupPhase = value;
                            _suggestions = null;
                          }),
                  ),
                  const Text(
                    'Nur Vorschläge mit Gruppenphase. Weitere Etappen bleiben möglich.',
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: _maximumStages,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Maximale Etappen',
                      helperText: 'Suche nach Kombinationen aller Turniermodi.',
                      helperMaxLines: 3,
                    ),
                    items: [
                      for (var n = 1; n <= 4; n++)
                        DropdownMenuItem(value: n, child: Text('$n')),
                    ],
                    onChanged: _calculating
                        ? null
                        : (n) => setState(() {
                            _maximumStages = n!;
                            _suggestions = null;
                          }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    key: const ValueKey('planner-preferred-final-stage'),
                    initialValue: _preferredFinalStage,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Gewünschte letzte Etappe',
                      helperText: 'Legt fest, mit welchem Format das Turnier enden soll.',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'single_knockout',
                        child: Text('Einfaches KO (Standard)'),
                      ),
                      DropdownMenuItem(
                        value: null,
                        child: Text('Egal (alle Finalformen zulassen)'),
                      ),
                      DropdownMenuItem(
                        value: 'double_knockout',
                        child: Text('Doppel-KO'),
                      ),
                      DropdownMenuItem(
                        value: 'triple_knockout',
                        child: Text('Triple-KO'),
                      ),
                      DropdownMenuItem(
                        value: 'kratzer',
                        child: Text('Kratzer'),
                      ),
                      DropdownMenuItem(
                        value: 'groups:round_robin',
                        child: Text('Gruppen: Jeder gegen jeden (einmal)'),
                      ),
                      DropdownMenuItem(
                        value: 'groups:double_round_robin',
                        child: Text('Gruppen: Jeder gegen jeden (zweimal)'),
                      ),
                    ],
                    onChanged: _calculating
                        ? null
                        : (val) => setState(() {
                            _preferredFinalStage = val;
                            _suggestions = null;
                          }),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: _maximumLives,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Maximale Leben im Kratzer-Modus',
                    ),
                    items: [
                      for (var n = 2; n <= 10; n++)
                        DropdownMenuItem(value: n, child: Text('$n')),
                    ],
                    onChanged: _calculating
                        ? null
                        : (n) => setState(() {
                            _maximumLives = n!;
                            _suggestions = null;
                          }),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
              SportSettingsSection(
                title: 'Spielregeln',
                summary:
                    'Best of $_bestOfLegs Legs${_lockLegsFormat ? ' (fix)' : ''} · ${_x01Selection == 'variable_301_501' ? '301 oder 501' : _x01Selection} · ${_checkoutType == 'double_out'
                        ? 'Double Out'
                        : _checkoutType == 'single_out'
                        ? 'Single Out'
                        : _checkoutType == 'master_out'
                        ? 'Master Out'
                        : 'Double In / Double Out'} · ${_allowSets ? 'Legs und Sets' : 'Legs'}',
                icon: Icons.sports_score,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _x01Selection,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'X01-Punktzahl',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: '101', child: Text('101')),
                      DropdownMenuItem(value: '170', child: Text('170')),
                      DropdownMenuItem(value: '201', child: Text('201')),
                      DropdownMenuItem(value: '301', child: Text('301')),
                      DropdownMenuItem(value: '401', child: Text('401')),
                      DropdownMenuItem(value: '501', child: Text('501')),
                      DropdownMenuItem(value: '701', child: Text('701')),
                      DropdownMenuItem(value: '901', child: Text('901')),
                      DropdownMenuItem(
                        value: 'variable_301_501',
                        child: Text('Variabel (301 oder 501)'),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      _x01Selection = value!;
                      _suggestions = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _checkoutType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Checkout-Modus',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'double_out',
                        child: Text('Double Out'),
                      ),
                      DropdownMenuItem(
                        value: 'single_out',
                        child: Text('Single Out'),
                      ),
                      DropdownMenuItem(
                        value: 'master_out',
                        child: Text('Master Out'),
                      ),
                      DropdownMenuItem(
                        value: 'double_in_out',
                        child: Text('Double In / Double Out'),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      _checkoutType = value!;
                      _suggestions = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    key: const ValueKey('planner-best-of-legs'),
                    initialValue: _bestOfLegs,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Spieldistanz (Best of Legs)',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 Leg (Single Leg)')),
                      DropdownMenuItem(value: 3, child: Text('Best of 3 Legs (Standard)')),
                      DropdownMenuItem(value: 5, child: Text('Best of 5 Legs')),
                      DropdownMenuItem(value: 7, child: Text('Best of 7 Legs')),
                      DropdownMenuItem(value: 9, child: Text('Best of 9 Legs')),
                      DropdownMenuItem(value: 11, child: Text('Best of 11 Legs')),
                    ],
                    onChanged: _calculating
                        ? null
                        : (val) => setState(() {
                            _bestOfLegs = val!;
                            _suggestions = null;
                          }),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    key: const ValueKey('planner-lock-legs-format'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Spieldistanz nicht verkürzen'),
                    subtitle: const Text(
                      'Verhindert, dass der Planer kürzere Distanzen (wie Best of 1) vorschlägt, nur um ins Zeitfenster zu passen.',
                    ),
                    value: _lockLegsFormat,
                    onChanged: _calculating
                        ? null
                        : (val) => setState(() {
                            _lockLegsFormat = val;
                            _suggestions = null;
                          }),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    key: const ValueKey('planner-allow-draws'),
                    title: const Text('Unentschieden erlauben'),
                    subtitle: const Text(
                      'Zusätzlich gerade Leg-Längen in Liga-/Gruppenphasen: 1 Punkt je Spieler. K.-o. und Set-Formate benötigen einen Sieger.',
                    ),
                    value: _allowDraws,
                    onChanged: _calculating
                        ? null
                        : (value) => setState(() {
                            _allowDraws = value;
                            _suggestions = null;
                          }),
                  ),
                  SwitchListTile(
                    key: const ValueKey('planner-allow-sets'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sets in Vorschlägen erlauben'),
                    subtitle: const Text(
                      'Ausgeschaltet: nur Legs. Eingeschaltet: zusätzlich Best of 3 oder 5 Sets.',
                    ),
                    value: _allowSets,
                    onChanged: _calculating
                        ? null
                        : (value) => setState(() {
                            _allowSets = value;
                            _suggestions = null;
                          }),
                  ),
                ],
              ),
              ExpansionTile(
                title: const Text('So entsteht die Schätzung', style: TextStyle(fontSize: 14)),
                subtitle: const Text('Spieldistanz, Zeitansatz und weitere Etappen', style: TextStyle(fontSize: 12)),
                leading: const Icon(Icons.info_outline, size: 20),
                initiallyExpanded: false,
                children: const [
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      'Spätere Etappen bleiben bei gleicher Distanz oder steigen höchstens um eine Best-of-Stufe (Bo3 → Bo5); dies gilt für Legs und Sets. Jede Etappe erhält einen eigenen Vorschlag: Best of 1 bis 101 Legs; bei erlaubtem Unentschieden zusätzlich gerade Leg-Längen bis 100 und optional Best of 3 oder 5 Sets. Bei variabler Punktzahl werden 301 und 501 je Etappe verglichen. Zeitansatz: Mittelwert aus minimaler und maximaler Anzahl Legs bzw. Sets. Bo3 = 2,5; Bo4 = 3,5; Bo5 = 4; Bo101 = 76. Bo1 = 1.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              if (_calculating)
                TextButton(
                  onPressed: _cancel,
                  child: const Text('Berechnung abbrechen'),
                ),
              if (_suggestions != null) ...[
                SizedBox(key: _resultsKey, height: 16),
                const Text(
                  'Mehr Boards ändern bei gleichem Turnieraufbau nur die Dauer, nicht die Spielanzahl. Dadurch können andere Gruppenaufteilungen ins Zeitfenster passen und die Vorschläge anders sortiert werden. Bei variabler Punktzahl kann sich auch 301/501 ändern.',
                ),
                const SizedBox(height: 12),
                if (_suggestions!.isEmpty)
                  Text(
                    _requireGroupPhase && (int.tryParse(_players.text.trim()) ?? 0) < 3
                        ? 'Keine Gruppenaufteilung möglich: Jede Gruppe benötigt mindestens 3 Spieler.'
                        : 'Keine passende Turnierform im gewählten Zeitfenster gefunden. Bitte Dauer anpassen oder weitere Spielarten zulassen.',
                  ),
                PlanningSuggestionList(
                  suggestions: _suggestions!,
                  pageSize: _suggestionPageSize,
                  onSelected: (suggestion) =>
                      Navigator.of(context).pop(suggestion),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed:
              _calculating ||
                  _enabledModes.isEmpty ||
                  (_requireGroupPhase &&
                      !_enabledModes.any((m) => m.startsWith('groups:')))
              ? null
              : _calculate,
          icon: const Icon(Icons.search),
          label: Text(_calculating ? 'Berechnet …' : 'Vorschläge berechnen'),
        ),

        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
      ],
    ),
  );

  Widget _numberField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      );
}

class _StageGameFormatSetup extends StatelessWidget {
  const _StageGameFormatSetup({required this.value, required this.onChanged});
  final TournamentGameFormat value;
  final ValueChanged<TournamentGameFormat> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Spielformat',
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _field(
            width: 160,
            child: DropdownButtonFormField<int>(
              key: ValueKey('x01-${value.x01Score}'),
              initialValue: value.x01Score,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'X01-Punktzahl',
                border: OutlineInputBorder(),
              ),
              items: const [101, 170, 201, 301, 401, 501, 701, 901]
                  .map(
                    (score) =>
                        DropdownMenuItem(value: score, child: Text('$score')),
                  )
                  .toList(),
              onChanged: (score) => _change(x01Score: score),
            ),
          ),
          _field(
            width: 180,
            child: DropdownButtonFormField<String>(
              key: ValueKey('checkout-${value.checkoutType}'),
              initialValue: value.checkoutType,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Checkout',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'double_out',
                  child: Text('Double Out'),
                ),
                DropdownMenuItem(
                  value: 'single_out',
                  child: Text('Single Out'),
                ),
                DropdownMenuItem(
                  value: 'master_out',
                  child: Text('Master Out'),
                ),
              ],
              onChanged: (checkout) => _change(checkoutType: checkout),
            ),
          ),
          _field(
            width: 145,
            child: DropdownButtonFormField<int>(
              key: ValueKey('legs-${value.bestOfLegs}'),
              initialValue: value.bestOfLegs,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Best of Legs',
                border: OutlineInputBorder(),
              ),
              items:
                  ([
                        ...TournamentGameFormat.supportedBestOfLegs,
                        if (value.bestOfSets == 1)
                          ...TournamentGameFormat.supportedDrawLegs,
                      ]..sort())
                      .map(
                        (legs) => DropdownMenuItem(
                          value: legs,
                          child: Text('$legs Legs'),
                        ),
                      )
                      .toList(),
              onChanged: (legs) => _change(bestOfLegs: legs),
            ),
          ),
          _field(
            width: 180,
            child: DropdownButtonFormField<int>(
              key: ValueKey('sets-${value.bestOfSets}'),
              initialValue: value.bestOfSets,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Best of Sets',
                border: OutlineInputBorder(),
              ),
              items: const [1, 3, 5]
                  .map(
                    (sets) => DropdownMenuItem(
                      value: sets,
                      child: Text(sets == 1 ? 'Nur Legs' : '$sets Sets'),
                    ),
                  )
                  .toList(),
              onChanged: (sets) => _change(bestOfSets: sets),
            ),
          ),
          _field(
            width: 160,
            child: DropdownButtonFormField<bool>(
              key: ValueKey('double-in-${value.doubleIn}'),
              initialValue: value.doubleIn,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Double In',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: false, child: Text('Nein')),
                DropdownMenuItem(value: true, child: Text('Ja')),
              ],
              onChanged: (doubleIn) => _change(doubleIn: doubleIn),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _field({required double width, required Widget child}) =>
      SizedBox(width: width, child: child);
  void _change({
    int? x01Score,
    String? checkoutType,
    int? bestOfLegs,
    int? bestOfSets,
    bool? doubleIn,
  }) => onChanged(
    TournamentGameFormat(
      x01Score: x01Score ?? value.x01Score,
      checkoutType: checkoutType ?? value.checkoutType,
      bestOfLegs:
          bestOfSets != null && bestOfSets > 1 && value.bestOfLegs.isEven
          ? value.bestOfLegs + 1
          : bestOfLegs ?? value.bestOfLegs,
      bestOfSets: bestOfSets ?? value.bestOfSets,
      doubleIn: doubleIn ?? value.doubleIn,
    ),
  );
}
