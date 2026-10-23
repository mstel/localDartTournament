import 'dart:math';

import 'package:dart_tournament_manager/features/random_draw/application/random_draw_image_generator.dart';
import 'package:dart_tournament_manager/features/random_draw/domain/random_draw_assignment.dart';
import 'package:dart_tournament_manager/shared/utils/png_image_export.dart';
import 'package:dart_tournament_manager/shared/widgets/adaptive_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RandomDrawToolPage extends StatefulWidget {
  const RandomDrawToolPage({super.key});

  @override
  State<RandomDrawToolPage> createState() => _RandomDrawToolPageState();
}

class _RandomDrawToolPageState extends State<RandomDrawToolPage>
    with SingleTickerProviderStateMixin {
  final _groupCountController = TextEditingController(text: '2');
  final _playersController = TextEditingController();
  final _random = Random.secure();
  final _drawnPlayers = <int>[];
  final _groupAssignments = <int, int>{};
  final _groupNameControllers = <TextEditingController>[];
  late final AnimationController _spinController;
  Animation<double>? _spinAnimation;
  double _rotation = 0;
  int? _selectedPlayer;
  bool _spinning = false;
  String? _inputError;

  @override
  void initState() {
    super.initState();
    _syncGroupNameControllers(2);
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
  }

  @override
  void dispose() {
    _spinController.dispose();
    _groupCountController.dispose();
    _playersController.dispose();
    for (final controller in _groupNameControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> get _players => _playersController.text
      .split(RegExp(r'[\r\n,;]+'))
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toList(growable: false);

  int? get _groupCount {
    final value = int.tryParse(_groupCountController.text.trim());
    return value != null && value >= 1 && value <= 32 ? value : null;
  }

  List<String> get _groupNames => [
    for (var index = 0; index < _groupNameControllers.length; index++)
      _groupNameControllers[index].text.trim().isEmpty
          ? _defaultGroupName(index)
          : _groupNameControllers[index].text.trim(),
  ];

  bool get _drawComplete =>
      _players.isNotEmpty && _drawnPlayers.length == _players.length;

  bool get _allAssigned =>
      _drawComplete && _groupAssignments.length == _players.length;

  String _defaultGroupName(int index) {
    var value = index + 1;
    var label = '';
    while (value > 0) {
      value--;
      label = String.fromCharCode(65 + value % 26) + label;
      value ~/= 26;
    }
    return 'Gruppe $label';
  }

  void _syncGroupNameControllers(int count) {
    while (_groupNameControllers.length < count) {
      final index = _groupNameControllers.length;
      _groupNameControllers.add(
        TextEditingController(text: _defaultGroupName(index)),
      );
    }
    while (_groupNameControllers.length > count) {
      _groupNameControllers.removeLast().dispose();
    }
  }

  void _resetDraw() {
    _drawnPlayers.clear();
    _groupAssignments.clear();
    _selectedPlayer = null;
    _inputError = null;
  }

  void _onGroupCountChanged(String text) {
    final count = int.tryParse(text.trim());
    if (count != null && count >= 1 && count <= 32) {
      _syncGroupNameControllers(count);
      _resetDraw();
    } else {
      _inputError = 'Bitte 1 bis 32 Gruppen angeben.';
    }
    setState(() {});
  }

  void _onPlayersChanged(String _) {
    _resetDraw();
    setState(() {});
  }

  String? _validatePlayers() {
    final players = _players;
    if (players.length < 2) return 'Mindestens zwei Namen eingeben.';
    if (_groupCount == null) return 'Bitte 1 bis 32 Gruppen angeben.';
    final normalized = players.map((name) => name.toLowerCase()).toSet();
    if (normalized.length != players.length) {
      return 'Jeder Name muss eindeutig sein.';
    }
    return null;
  }

  Future<void> _spin() async {
    if (_spinning) return;
    final error = _validatePlayers();
    if (error != null) {
      setState(() => _inputError = error);
      return;
    }
    final remaining = [
      for (var index = 0; index < _players.length; index++)
        if (!_drawnPlayers.contains(index)) index,
    ];
    if (remaining.isEmpty) return;

    final selected = remaining[_random.nextInt(remaining.length)];
    final segmentAngle = 2 * pi / _players.length;
    final selectedCenter = (selected + 0.5) * segmentAngle;
    final targetRotation =
        (_rotation / (2 * pi)).ceil() * 2 * pi +
        4 * 2 * pi -
        selectedCenter -
        pi / 2;
    final animation = Tween<double>(begin: _rotation, end: targetRotation)
        .animate(
          CurvedAnimation(parent: _spinController, curve: Curves.easeOutCubic),
        );

    setState(() {
      _spinning = true;
      _selectedPlayer = selected;
      _spinAnimation = animation;
    });
    await _spinController.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _rotation = targetRotation;
      _drawnPlayers.add(selected);
      _spinning = false;
    });
  }

  void _autoAssign() {
    if (!_drawComplete || _groupCount == null) return;
    setState(() {
      _groupAssignments
        ..clear()
        ..addEntries([
          for (var index = 0; index < _drawnPlayers.length; index++)
            MapEntry(_drawnPlayers[index], index % _groupCount!),
        ]);
    });
  }

  List<List<String>> _assignedGroups() {
    final groups = List.generate(_groupNames.length, (_) => <String>[]);
    for (final playerIndex in _drawnPlayers) {
      final groupIndex = _groupAssignments[playerIndex];
      if (groupIndex != null && groupIndex < groups.length) {
        groups[groupIndex].add(_players[playerIndex]);
      }
    }
    return groups;
  }

  Future<void> _copyText() async {
    try {
      await Clipboard.setData(
        ClipboardData(
          text: RandomDrawAssignment.formatText(
            groupNames: _groupNames,
            groups: _assignedGroups(),
          ),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Gruppenliste kopiert.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Text konnte nicht kopiert werden: $error')),
        );
      }
    }
  }

  Future<void> _exportImage() async {
    try {
      final bytes = await const RandomDrawImageGenerator().generate(
        title: 'Turnierauslosung',
        groupNames: _groupNames,
        groups: _assignedGroups(),
      );
      if (!mounted) return;
      await exportPngImage(
        context,
        bytes: bytes,
        fileName: 'turnierauslosung.png',
        successMessage: 'Gruppen-Grafik gespeichert.',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Grafik konnte nicht erstellt werden: $error'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Auslosungsrad')),
    body: AdaptiveContentList(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Unabhängige Ziehung ohne Turnier- oder Gruppenautomatik. '
          'Die Gruppe jedes gezogenen Namens bestimmst du selbst oder lässt '
          'sie gleichmäßig zuordnen.',
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final groupCountField = TextField(
                      controller: _groupCountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Anzahl der Gruppen',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: _onGroupCountChanged,
                    );
                    final playersField = TextField(
                      controller: _playersController,
                      minLines: 4,
                      maxLines: 10,
                      decoration: const InputDecoration(
                        labelText: 'Spielernamen',
                        hintText: 'Ein Name pro Zeile',
                        helperText:
                            'Zeilen, Kommas oder Semikolons trennen Namen.',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      onChanged: _onPlayersChanged,
                    );
                    if (constraints.maxWidth < 600) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          groupCountField,
                          const SizedBox(height: 12),
                          for (
                            var index = 0;
                            index < _groupNameControllers.length;
                            index++
                          ) ...[
                            TextField(
                              key: ValueKey('draw-group-name-$index'),
                              controller: _groupNameControllers[index],
                              decoration: InputDecoration(
                                labelText: 'Name ${_defaultGroupName(index)}',
                                border: const OutlineInputBorder(),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 8),
                          ],
                          const SizedBox(height: 4),
                          playersField,
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 300, child: groupCountField),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            for (
                              var index = 0;
                              index < _groupNameControllers.length;
                              index++
                            )
                              SizedBox(
                                width: 260,
                                child: TextField(
                                  key: ValueKey('draw-group-name-$index'),
                                  controller: _groupNameControllers[index],
                                  decoration: InputDecoration(
                                    labelText:
                                        'Name ${_defaultGroupName(index)}',
                                    border: const OutlineInputBorder(),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        playersField,
                      ],
                    );
                  },
                ),
                if (_inputError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _inputError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _selectedPlayer == null
                      ? 'Bereit zur Ziehung'
                      : 'Zuletzt gezogen: ${_players[_selectedPlayer!]}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = min(constraints.maxWidth, 380.0);
                      return AnimatedBuilder(
                        animation: _spinController,
                        builder: (context, _) => SizedBox.square(
                          dimension: size,
                          child: CustomPaint(
                            painter: _DrawToolWheelPainter(
                              names: _players,
                              drawnPlayers: _drawnPlayers.toSet(),
                              selectedPlayer: _selectedPlayer,
                              rotation: _spinAnimation?.value ?? _rotation,
                              colors: Theme.of(context).colorScheme,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${_drawnPlayers.length} von ${_players.length} gezogen',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _spinning || _drawComplete ? null : _spin,
                  icon: const Icon(Icons.casino_outlined),
                  label: Text(
                    _drawnPlayers.isEmpty ? 'Rad drehen' : 'Nächsten ziehen',
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_drawComplete) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Gruppen befüllen',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _autoAssign,
                    icon: const Icon(Icons.shuffle),
                    label: const Text('Automatisch gleichmäßig verteilen'),
                  ),
                  for (final playerIndex in _drawnPlayers)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_players[playerIndex]),
                      trailing: SizedBox(
                        width: min(
                          MediaQuery.sizeOf(context).width * 0.48,
                          220,
                        ),
                        child: DropdownButtonFormField<int>(
                          key: ValueKey(
                            'draw-player-group-$playerIndex-'
                            '${_groupAssignments[playerIndex]}',
                          ),
                          initialValue: _groupAssignments[playerIndex],
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Gruppe',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          hint: const Text('Zuordnen'),
                          items: [
                            for (
                              var groupIndex = 0;
                              groupIndex < _groupNames.length;
                              groupIndex++
                            )
                              DropdownMenuItem(
                                value: groupIndex,
                                child: Text(
                                  _groupNames[groupIndex],
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(
                              () => _groupAssignments[playerIndex] = value,
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_allAssigned) ...[
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < _groupNames.length; index++)
                    SizedBox(
                      width: constraints.maxWidth < 560
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 12) / 2,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _groupNames[index],
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              for (final player in _assignedGroups()[index])
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(player),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _copyText,
                  icon: const Icon(Icons.copy),
                  label: const Text('Text kopieren'),
                ),
                FilledButton.icon(
                  onPressed: _exportImage,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Grafik exportieren'),
                ),
              ],
            ),
          ],
        ],
      ],
    ),
  );
}

class _DrawToolWheelPainter extends CustomPainter {
  const _DrawToolWheelPainter({
    required this.names,
    required this.drawnPlayers,
    required this.selectedPlayer,
    required this.rotation,
    required this.colors,
  });

  final List<String> names;
  final Set<int> drawnPlayers;
  final int? selectedPlayer;
  final double rotation;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (names.isEmpty) {
      canvas.drawCircle(
        size.center(Offset.zero),
        size.shortestSide / 2 - 8,
        Paint()..color = colors.surfaceContainerHighest,
      );
      return;
    }
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 8;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final segmentAngle = 2 * pi / names.length;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.translate(-center.dx, -center.dy);
    for (var index = 0; index < names.length; index++) {
      final selected = selectedPlayer == index;
      final fill = Paint()
        ..color = selected
            ? colors.tertiaryContainer
            : index.isEven
            ? colors.primaryContainer
            : colors.secondaryContainer;
      canvas.drawArc(rect, index * segmentAngle, segmentAngle, true, fill);
      canvas.drawArc(
        rect,
        index * segmentAngle,
        segmentAngle,
        true,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = colors.outlineVariant,
      );
      final angle = (index + 0.5) * segmentAngle;
      final labelRadius = radius * 0.68;
      final label = TextPainter(
        text: TextSpan(
          text: names[index],
          style: TextStyle(
            color: drawnPlayers.contains(index)
                ? colors.onSurface.withValues(alpha: 0.48)
                : colors.onSurface,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: names.length > 24
                ? 8
                : names.length > 14
                ? 9
                : 11,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: radius * 0.55);
      canvas.save();
      canvas.translate(
        center.dx + cos(angle) * labelRadius,
        center.dy + sin(angle) * labelRadius,
      );
      canvas.rotate(angle > pi / 2 && angle < 3 * pi / 2 ? angle + pi : angle);
      label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
      canvas.restore();
    }
    canvas.restore();
    canvas.drawCircle(center, radius * 0.2, Paint()..color = colors.surface);
    canvas.drawCircle(
      center,
      radius * 0.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = colors.primary,
    );
    canvas.drawPath(
      Path()
        ..moveTo(center.dx - 14, 0)
        ..lineTo(center.dx + 14, 0)
        ..lineTo(center.dx, 20)
        ..close(),
      Paint()..color = colors.error,
    );
  }

  @override
  bool shouldRepaint(covariant _DrawToolWheelPainter oldDelegate) =>
      oldDelegate.names != names ||
      oldDelegate.drawnPlayers != drawnPlayers ||
      oldDelegate.selectedPlayer != selectedPlayer ||
      oldDelegate.rotation != rotation ||
      oldDelegate.colors != colors;
}
