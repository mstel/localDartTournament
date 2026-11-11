import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../shared/utils/group_assignment_text.dart';
import '../../../data/app_database.dart';
import '../../../domain/engines/group_player_allocation_engine.dart';
import '../../../domain/tournament_models.dart';

class GroupPositionsDialog extends StatefulWidget {
  const GroupPositionsDialog({
    super.key,
    required this.stage,
    this.ratings = const {},
    this.loadRatings,
    this.loadCatalogProfiles,
  });

  final GroupTournamentRunStage stage;
  final Map<String, int> ratings;
  final Future<Map<String, int>> Function()? loadRatings;
  final Future<List<PlayerProfile>> Function()? loadCatalogProfiles;

  @override
  State<GroupPositionsDialog> createState() => _GroupPositionsDialogState();
}

class _GroupPositionsDialogState extends State<GroupPositionsDialog> {
  late List<List<TournamentPlayer>> _groups;
  GroupPlayerAllocationMode _mode = GroupPlayerAllocationMode.manual;
  _GroupPlayerPosition? _selected;
  final _playerReplacements = <TournamentPlayer, TournamentPlayer>{};
  late Map<String, int> _ratings = widget.ratings;
  bool _isAllocating = false;

  @override
  void initState() {
    super.initState();
    _groups = [
      for (final group in widget.stage.groups) [...group.players],
    ];
  }

  void _swap(_GroupPlayerPosition first, _GroupPlayerPosition second) {
    if (first == second ||
        first.groupIndex < 0 ||
        second.groupIndex < 0 ||
        first.groupIndex >= _groups.length ||
        second.groupIndex >= _groups.length) {
      return;
    }
    final firstIndex = _groups[first.groupIndex].indexOf(first.player);
    final secondIndex = _groups[second.groupIndex].indexOf(second.player);
    if (firstIndex < 0 || secondIndex < 0) return;
    setState(() {
      _groups[first.groupIndex][firstIndex] = second.player;
      _groups[second.groupIndex][secondIndex] = first.player;
      _selected = null;
      _mode = GroupPlayerAllocationMode.manual;
    });
  }

  void _select(_GroupPlayerPosition position) {
    final selected = _selected;
    if (selected == null || selected.player == position.player) {
      setState(() => _selected = selected == position ? null : position);
      return;
    }
    _swap(selected, position);
  }

  Future<void> _allocate(GroupPlayerAllocationMode mode) async {
    if (_isAllocating || mode == GroupPlayerAllocationMode.manual) return;
    setState(() {
      _isAllocating = true;
      _mode = mode;
      _selected = null;
    });
    try {
      if (mode != GroupPlayerAllocationMode.random &&
          _ratings.isEmpty &&
          widget.loadRatings != null) {
        _ratings = await widget.loadRatings!();
        if (!mounted) return;
      }
      final players = _groups.expand((group) => group).toList();
      final arranged = const GroupPlayerAllocationEngine().allocate(
        players: players,
        groupSizes: [for (final group in _groups) group.length],
        mode: mode,
        ratings: _ratings,
        random: Random(),
      );
      var offset = 0;
      final nextGroups = <List<TournamentPlayer>>[];
      for (final group in _groups) {
        nextGroups.add(arranged.skip(offset).take(group.length).toList());
        offset += group.length;
      }
      setState(() => _groups = nextGroups);
    } catch (error) {
      _showError('Gruppen konnten nicht neu eingeteilt werden: $error');
    } finally {
      if (mounted) setState(() => _isAllocating = false);
    }
  }

  Future<void> _copyAssignment() async {
    try {
      await Clipboard.setData(
        ClipboardData(
          text: GroupAssignmentText.format(
            groupNames: [for (final group in widget.stage.groups) group.name],
            groups: [
              for (final group in _groups)
                [for (final player in group) player.name],
            ],
          ),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gruppenliste in die Zwischenablage kopiert.'),
          ),
        );
      }
    } catch (error) {
      _showError('Gruppenliste konnte nicht kopiert werden: $error');
    }
  }

  Future<void> _importAssignment() async {
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      final parsed = GroupAssignmentText.parse(clipboard?.text ?? '');
      if (parsed.groups.length != _groups.length) {
        throw FormatException(
          'Die Vorlage enthält ${parsed.groups.length} Gruppen; '
          'das Turnier hat ${_groups.length}.',
        );
      }
      for (var index = 0; index < _groups.length; index++) {
        if (parsed.groups[index].length != _groups[index].length) {
          throw FormatException(
            '${parsed.groupNames[index]} enthält ${parsed.groups[index].length} '
            'Teilnehmer; ${widget.stage.groups[index].name} benötigt '
            '${_groups[index].length}.',
          );
        }
      }

      final currentPlayers = _groups.expand((group) => group).toList();
      final currentByName = <String, TournamentPlayer>{
        for (final player in currentPlayers) _nameKey(player.name): player,
      };
      final currentKeys = currentPlayers
          .map((player) => _nameKey(player.name))
          .toSet();
      final importedKeys = parsed.players.map(_nameKey).toSet();
      if (currentKeys.length != currentPlayers.length ||
          currentKeys.length != importedKeys.length ||
          !currentKeys.containsAll(importedKeys)) {
        throw const FormatException(
          'Gruppenanzahl und Teilnehmernamen müssen exakt zum Turnier passen. '
          'Die aktuelle Zuweisung wurde nicht verändert.',
        );
      }

      final profiles = widget.loadCatalogProfiles == null
          ? const <PlayerProfile>[]
          : await widget.loadCatalogProfiles!();
      if (!mounted) return;
      final profilesByName = <String, List<PlayerProfile>>{};
      for (final profile in profiles) {
        profilesByName
            .putIfAbsent(_nameKey(profile.displayName), () => [])
            .add(profile);
      }
      final catalogMatches = currentPlayers
          .where(
            (player) =>
                !player.isTeam &&
                (profilesByName[_nameKey(player.name)]?.isNotEmpty ?? false),
          )
          .toList();

      var useCatalog = false;
      if (catalogMatches.isNotEmpty) {
        final choice = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Spielerkatalog verwenden?'),
            content: const Text(
              'Namen aus der Zwischenablage sind im lokalen Spielerkatalog '
              'vorhanden. Sollen die passenden Katalogprofile verwendet oder '
              'lokale Teilnehmer angelegt werden?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Lokalen Teilnehmer anlegen'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Teilnehmer aus dem Spielerkatalog verwenden',
                ),
              ),
            ],
          ),
        );
        if (!mounted || choice == null) return;
        useCatalog = choice;
      }

      final replacements = <TournamentPlayer, TournamentPlayer>{};
      for (final player in catalogMatches) {
        PlayerProfile? profile;
        if (useCatalog) {
          final candidates = profilesByName[_nameKey(player.name)]!;
          if (candidates.length == 1) {
            profile = candidates.single;
          } else {
            profile = await _chooseCatalogProfile(player.name, candidates);
            if (!mounted || profile == null) return;
          }
        }
        final replacement = useCatalog
            ? TournamentPlayer(
                profileId: profile!.id,
                name: player.name,
                isGenerated: false,
                compactName: player.compactName,
                kratzerStartingScratches: player.kratzerStartingScratches,
              )
            : TournamentPlayer(
                name: player.name,
                isGenerated: false,
                compactName: player.compactName,
                kratzerStartingScratches: player.kratzerStartingScratches,
              );
        if (replacement != player) replacements[player] = replacement;
      }

      final nextGroups = [
        for (final group in parsed.groups)
          [
            for (final name in group)
              replacements[currentByName[_nameKey(name)]] ??
                  currentByName[_nameKey(name)]!,
          ],
      ];
      final composedReplacements = <TournamentPlayer, TournamentPlayer>{
        for (final entry in _playerReplacements.entries)
          entry.key: replacements[entry.value] ?? entry.value,
      };
      for (final entry in replacements.entries) {
        if (!composedReplacements.values.contains(entry.key)) {
          composedReplacements[entry.key] = entry.value;
        }
      }
      setState(() {
        _groups = nextGroups;
        _playerReplacements
          ..clear()
          ..addAll(composedReplacements);
        _selected = null;
        _mode = GroupPlayerAllocationMode.manual;
      });
    } on FormatException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('Zuweisung konnte nicht übernommen werden: $error');
    }
  }

  Future<PlayerProfile?> _chooseCatalogProfile(
    String playerName,
    List<PlayerProfile> candidates,
  ) => showDialog<PlayerProfile>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Welches Profil ist $playerName?'),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final profile in candidates)
              ListTile(
                title: Text(profile.displayName),
                subtitle: Text(
                  [
                    profile.city,
                    profile.country,
                  ].where((part) => part.trim().isNotEmpty).join(', '),
                ),
                onTap: () => Navigator.pop(context, profile),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
      ],
    ),
  );

  String _nameKey(String name) => name.trim().toLowerCase();

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final width = (screenSize.width - 32).clamp(280.0, 1400.0);
    final height = (screenSize.height - 48).clamp(300.0, 900.0);
    final theme = Theme.of(context);

    return Dialog(
      child: SizedBox(
        width: width,
        height: height,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Gruppen neu einteilen',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Dialog schließen',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Verteilung auswählen oder Teilnehmer per Drag-and-drop '
                'zwischen den Gruppen verschieben. Änderungen werden erst '
                'mit „Übernehmen“ gespeichert.',
              ),
              const SizedBox(height: 4),
              Text(
                'Stärkestufen nutzen lokale ELO-Wertungen; Teilnehmer ohne '
                'Wertung werden gleich gewichtet.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final picker =
                      DropdownButtonFormField<GroupPlayerAllocationMode>(
                        initialValue: _mode,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Gruppenverteilung',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: GroupPlayerAllocationMode.strengthLevels,
                            child: Text('Stärkestufen bündeln'),
                          ),
                          DropdownMenuItem(
                            value: GroupPlayerAllocationMode.balanced,
                            child: Text('Stärke ausgeglichen verteilen'),
                          ),
                          DropdownMenuItem(
                            value: GroupPlayerAllocationMode.random,
                            child: Text('Zufällige Verteilung'),
                          ),
                          DropdownMenuItem(
                            value: GroupPlayerAllocationMode.manual,
                            child: Text('Manuell per Drag-and-drop'),
                          ),
                        ],
                        onChanged: (mode) {
                          if (mode != null && !_isAllocating) {
                            setState(() => _mode = mode);
                          }
                        },
                      );
                  if (constraints.maxWidth < 560) {
                    return picker;
                  }
                  return Row(
                    children: [
                      Expanded(child: picker),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed:
                            _isAllocating ||
                                _mode == GroupPlayerAllocationMode.manual
                            ? null
                            : () => _allocate(_mode),
                        icon: _isAllocating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.shuffle),
                        label: const Text('Neu einteilen'),
                      ),
                    ],
                  );
                },
              ),
              if (MediaQuery.sizeOf(context).width < 560) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed:
                        _isAllocating ||
                            _mode == GroupPlayerAllocationMode.manual
                        ? null
                        : () => _allocate(_mode),
                    icon: _isAllocating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.shuffle),
                    label: const Text('Neu einteilen'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _copyAssignment,
                    icon: const Icon(Icons.copy),
                    label: const Text('Gruppen als Text kopieren'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _importAssignment,
                    icon: const Icon(Icons.content_paste),
                    label: const Text(
                      'Zuweisung aus Zwischenablage übernehmen',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GridView.extent(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                maxCrossAxisExtent: 400,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  for (
                    var index = 0;
                    index < widget.stage.groups.length;
                    index++
                  )
                    _groupCard(index, widget.stage.groups[index], theme),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      GroupPositionsResult(
                        assignments: [
                          for (final group in _groups)
                            List<TournamentPlayer>.of(group),
                        ],
                        playerReplacements: Map.of(_playerReplacements),
                      ),
                    ),
                    child: const Text('Übernehmen'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupCard(int groupIndex, TournamentGroup group, ThemeData theme) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(group.name, style: theme.textTheme.titleMedium),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: _groups[groupIndex].length,
                  itemBuilder: (context, index) {
                    final player = _groups[groupIndex][index];
                    final position = _GroupPlayerPosition(groupIndex, player);
                    final isSelected = _selected == position;
                    final colors = theme.colorScheme;
                    final row = Material(
                      color: isSelected
                          ? colors.secondaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _select(position),
                        child: SizedBox(
                          height: 48,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.check_circle
                                      : Icons.person_outline,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    player.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.drag_indicator, size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );

                    return DragTarget<_GroupPlayerPosition>(
                      onWillAcceptWithDetails: (details) =>
                          details.data.player != player,
                      onAcceptWithDetails: (details) =>
                          _swap(details.data, position),
                      builder: (context, candidates, rejected) => DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: candidates.isEmpty
                              ? null
                              : Border.all(color: colors.primary, width: 2),
                        ),
                        child: LongPressDraggable<_GroupPlayerPosition>(
                          data: position,
                          feedback: Material(
                            elevation: 6,
                            borderRadius: BorderRadius.circular(8),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 320),
                              child: row,
                            ),
                          ),
                          childWhenDragging: Opacity(opacity: 0.35, child: row),
                          child: row,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
}

class GroupPositionsResult {
  const GroupPositionsResult({
    required this.assignments,
    this.playerReplacements = const {},
  });

  final List<List<TournamentPlayer>> assignments;
  final Map<TournamentPlayer, TournamentPlayer> playerReplacements;
}

class _GroupPlayerPosition {
  const _GroupPlayerPosition(this.groupIndex, this.player);

  final int groupIndex;
  final TournamentPlayer player;

  @override
  bool operator ==(Object other) =>
      other is _GroupPlayerPosition &&
      other.groupIndex == groupIndex &&
      other.player == player;

  @override
  int get hashCode => Object.hash(groupIndex, player);
}
