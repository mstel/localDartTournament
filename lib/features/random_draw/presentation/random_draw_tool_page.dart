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
  late final AnimationController _spinController;
  Animation<double>? _spinAnimation;
  double _rotation = 0;
  int? _selectedPlayer;
  bool _spinning = false;
  String? _inputError;

  @override
  void initState() {
    super.initState();
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

  bool get _drawComplete =>
      _players.isNotEmpty && _drawnPlayers.length == _players.length;

  List<String> get _remainingPlayers => [
    for (var index = 0; index < _players.length; index++)
      if (!_drawnPlayers.contains(index)) _players[index],
  ];

  List<String> _groupNames(int count) => [
    for (var index = 0; index < count; index++) _groupName(index),
  ];

  String _groupName(int index) {
    var value = index + 1;
    var label = '';
    while (value > 0) {
      value--;
      label = String.fromCharCode(65 + value % 26) + label;
      value ~/= 26;
    }
    return 'Gruppe $label';
  }

  void _resetDraw() {
    _drawnPlayers.clear();
    _selectedPlayer = null;
    _inputError = null;
  }

  void _onGroupCountChanged(String text) {
    final count = int.tryParse(text.trim());
    if (count != null && count >= 1 && count <= 32) {
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
    final selectedWheelIndex = remaining.indexOf(selected);
    final segmentAngle = 2 * pi / remaining.length;
    final selectedCenter = (selectedWheelIndex + 0.5) * segmentAngle;
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

  List<List<String?>> _groupSlots() => RandomDrawAssignment.groupSlots(
    drawnPlayers: [for (final index in _drawnPlayers) _players[index]],
    groupCount: _groupCount ?? 1,
    totalPlayerCount: _players.length,
  );

  List<List<String>> _assignedGroups() => [
    for (final group in _groupSlots()) [for (final player in group) ?player],
  ];

  List<String> get _groupNamesForExport => _groupNames(_groupCount ?? 1);

  Future<void> _copyText() async {
    try {
      await Clipboard.setData(
        ClipboardData(
          text: RandomDrawAssignment.formatText(
            groupNames: _groupNamesForExport,
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
        groupNames: _groupNamesForExport,
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
          'Ziehe die Namen zufällig. Jeder gezogene Name wird aus dem Rad '
          'entfernt und der Reihe nach in die Gruppenplätze eingetragen.',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 900) {
              return Column(
                key: const ValueKey('random-draw-workspace-stacked'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _configurationCard(),
                  const SizedBox(height: 12),
                  _wheelCard(),
                  const SizedBox(height: 12),
                  _groupsCard(),
                  if (_drawComplete) ...[
                    const SizedBox(height: 12),
                    _exportActions(),
                  ],
                ],
              );
            }
            return Row(
              key: const ValueKey('random-draw-workspace-wide'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      _configurationCard(),
                      const SizedBox(height: 12),
                      _wheelCard(),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      _groupsCard(),
                      if (_drawComplete) ...[
                        const SizedBox(height: 12),
                        _exportActions(),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );

  Widget _configurationCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 300,
            child: TextField(
              controller: _groupCountController,
              enabled: _drawnPlayers.isEmpty && !_spinning,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Anzahl der Gruppen',
                border: OutlineInputBorder(),
              ),
              onChanged: _onGroupCountChanged,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _playersController,
            enabled: _drawnPlayers.isEmpty && !_spinning,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Spielernamen',
              hintText: 'Namen mit Kommas trennen',
              helperText:
                  'Kommas, Semikolons oder Zeilen trennen Namen. '
                  'Nach der ersten Ziehung ist die Liste gesperrt.',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            onChanged: _onPlayersChanged,
          ),
          if (_inputError != null) ...[
            const SizedBox(height: 8),
            Text(
              _inputError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _wheelCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _selectedPlayer == null
                ? 'Bereit zur Ziehung'
                : 'Zuletzt gezogen: ${_players[_selectedPlayer!]}',
            key: const ValueKey('random-draw-last-selected'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = min(constraints.maxWidth, 380.0);
                final remaining = _remainingPlayers;
                final selectedWheelIndex = _selectedPlayer == null
                    ? null
                    : [
                        for (var index = 0; index < _players.length; index++)
                          if (!_drawnPlayers.contains(index)) index,
                      ].indexOf(_selectedPlayer!);
                return Semantics(
                  container: true,
                  label: 'Im Rad: ${remaining.join(', ')}',
                  child: AnimatedBuilder(
                    animation: _spinController,
                    builder: (context, _) => SizedBox.square(
                      dimension: size,
                      child: CustomPaint(
                        key: const ValueKey('random-draw-wheel'),
                        painter: _DrawToolWheelPainter(
                          names: remaining,
                          selectedPlayer:
                              selectedWheelIndex == null ||
                                  selectedWheelIndex < 0
                              ? null
                              : selectedWheelIndex,
                          rotation: _spinAnimation?.value ?? _rotation,
                          colors: Theme.of(context).colorScheme,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${_drawnPlayers.length} von ${_players.length} gezogen · '
            '${_remainingPlayers.length} noch im Rad',
            key: const ValueKey('random-draw-progress'),
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
  );

  Widget _groupsCard() {
    final slots = _groupSlots();
    final names = _groupNames(slots.length);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Gruppenzuweisung',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 620 ? 2 : 1;
                final gap = 8.0;
                final tileWidth =
                    (constraints.maxWidth - (columns - 1) * gap) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (
                      var groupIndex = 0;
                      groupIndex < slots.length;
                      groupIndex++
                    )
                      SizedBox(
                        width: tileWidth,
                        child: _groupCard(names[groupIndex], slots[groupIndex]),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupCard(String name, List<String?> players) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name, style: Theme.of(context).textTheme.titleSmall),
          if (players.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Keine Spielerplätze'),
            ),
          for (var index = 0; index < players.length; index++)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  players[index] ?? 'Spieler ${index + 1}',
                  key: ValueKey('draw-slot-$name-$index'),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _exportActions() => Wrap(
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
  );
}

class _DrawToolWheelPainter extends CustomPainter {
  const _DrawToolWheelPainter({
    required this.names,
    required this.selectedPlayer,
    required this.rotation,
    required this.colors,
  });

  final List<String> names;
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
            color: colors.onSurface,
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
      oldDelegate.selectedPlayer != selectedPlayer ||
      oldDelegate.rotation != rotation ||
      oldDelegate.colors != colors;
}
