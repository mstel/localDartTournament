part of '../../../../../tournament_workspace.dart';

class _RandomDrawDialog extends StatefulWidget {
  const _RandomDrawDialog({
    required this.stageName,
    required this.participantLabels,
    required this.bracketSize,
    required this.useBracketSlots,
    this.groupSizes = const [],
  });

  final String stageName;
  final List<String> participantLabels;
  final int bracketSize;
  final bool useBracketSlots;
  final List<int> groupSizes;

  @override
  State<_RandomDrawDialog> createState() => _RandomDrawDialogState();
}

class _RandomDrawDialogState extends State<_RandomDrawDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<int> _remainingSeeds;
  late List<int> _wheelSeeds;
  late final TextEditingController _autoRollSecondsController;
  final List<int> _drawnSeeds = [];
  final Random _random = Random();
  Timer? _autoRollTimer;
  double _currentRotation = 0;
  int? _selectedSeed;
  bool _isSpinning = false;
  bool _autoRollEnabled = false;

  @override
  void initState() {
    super.initState();
    _remainingSeeds = [
      for (var seed = 1; seed <= widget.participantLabels.length; seed++) seed,
    ];
    _wheelSeeds = _shuffledRemainingSeeds();
    _autoRollSecondsController = TextEditingController(text: '3');
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
  }

  @override
  void dispose() {
    _autoRollTimer?.cancel();
    _autoRollSecondsController.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool get _isComplete => _drawnSeeds.length == widget.participantLabels.length;

  List<int> _shuffledRemainingSeeds() {
    return List<int>.from(_remainingSeeds)..shuffle(_random);
  }

  int get _autoRollSeconds {
    final parsed = int.tryParse(_autoRollSecondsController.text);
    if (parsed == null || parsed < 1) {
      return 3;
    }
    return parsed.clamp(1, 60).toInt();
  }

  void _scheduleAutoRoll() {
    _autoRollTimer?.cancel();
    if (!_autoRollEnabled || _isComplete || _isSpinning) {
      return;
    }

    _autoRollTimer = Timer(Duration(seconds: _autoRollSeconds), () {
      if (!mounted || !_autoRollEnabled || _isSpinning || _isComplete) {
        return;
      }
      _spin();
    });
  }

  void _setAutoRollEnabled(bool enabled) {
    setState(() {
      _autoRollEnabled = enabled;
    });
    if (enabled) {
      _scheduleAutoRoll();
    } else {
      _autoRollTimer?.cancel();
    }
  }

  Future<void> _spin() async {
    if (_isSpinning || _remainingSeeds.isEmpty) {
      return;
    }

    _autoRollTimer?.cancel();
    final wheelSeeds = _shuffledRemainingSeeds();
    final selectedIndex = _random.nextInt(wheelSeeds.length);
    final selectedSeed = wheelSeeds[selectedIndex];
    final segmentAngle = 2 * pi / wheelSeeds.length;
    final selectedSegmentCenter = (selectedIndex + 0.5) * segmentAngle;
    final currentTurns = _currentRotation / (2 * pi);
    final baseTurns = currentTurns.ceil() + 3;
    final targetRotation =
        (baseTurns * 2 * pi) - selectedSegmentCenter - (pi / 2);

    setState(() {
      _isSpinning = true;
      _selectedSeed = null;
      _wheelSeeds = wheelSeeds;
    });

    _controller
      ..reset()
      ..duration = const Duration(milliseconds: 3600);
    final animation = Tween<double>(
      begin: _currentRotation,
      end: targetRotation,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    animation.addListener(() {
      setState(() {
        _currentRotation = animation.value;
      });
    });

    await _controller.forward();
    if (!mounted) {
      return;
    }

    setState(() {
      _isSpinning = false;
      _selectedSeed = selectedSeed;
      _remainingSeeds.remove(selectedSeed);
      _drawnSeeds.add(selectedSeed);
      _wheelSeeds = _shuffledRemainingSeeds();
    });
    _scheduleAutoRoll();
  }

  List<int?> _slotOrderFromDrawnSeeds() {
    if (!widget.useBracketSlots) {
      return List<int?>.from(_drawnSeeds);
    }

    var drawnIndex = 0;
    return [
      for (final bracketSeed in _seedOrderForSize(widget.bracketSize))
        bracketSeed <= _drawnSeeds.length ? _drawnSeeds[drawnIndex++] : null,
    ];
  }

  void _submit() {
    if (!_isComplete) {
      return;
    }

    Navigator.of(context).pop(_slotOrderFromDrawnSeeds());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedLabel = _selectedSeed == null
        ? 'Bereit'
        : widget.participantLabels[_selectedSeed! - 1];

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      title: Text('Auslosung: ${widget.stageName}'),
      content: SizedBox(
        width: 1180,
        height: min(MediaQuery.sizeOf(context).height * 0.72, 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 380,
                    child: Column(
                      children: [
                        Expanded(
                          child: CustomPaint(
                            painter: _DrawWheelPainter(
                              labels: widget.participantLabels,
                              wheelSeeds: _wheelSeeds,
                              selectedSeed: _selectedSeed,
                              rotation: _currentRotation,
                              colorScheme: colorScheme,
                            ),
                            child: Center(
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: colorScheme.surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: colorScheme.primary,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: colorScheme.shadow.withValues(
                                        alpha: 0.12,
                                      ),
                                      blurRadius: 18,
                                    ),
                                  ],
                                ),
                                alignment: Alignment.center,
                                padding: const EdgeInsets.all(10),
                                child: Text(
                                  selectedLabel,
                                  textAlign: TextAlign.center,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: widget.participantLabels.isEmpty
                              ? 0
                              : _drawnSeeds.length /
                                    widget.participantLabels.length,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_drawnSeeds.length} von ${widget.participantLabels.length} gezogen',
                        ),
                        const SizedBox(height: 10),
                        _AutoRollControls(
                          enabled: _autoRollEnabled,
                          secondsController: _autoRollSecondsController,
                          onEnabledChanged: _setAutoRollEnabled,
                          onSecondsChanged: (_) => _scheduleAutoRoll(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  SizedBox(
                    width: 300,
                    child: _DrawCandidateList(
                      remainingSeeds: _remainingSeeds,
                      drawnSeeds: _drawnSeeds,
                      participantLabels: widget.participantLabels,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: widget.useBracketSlots
                        ? _DrawBracketPreview(
                            bracketSize: widget.bracketSize,
                            participantLabels: widget.participantLabels,
                            drawnSeeds: _drawnSeeds,
                          )
                        : _DrawGroupPreview(
                            groupSizes: widget.groupSizes,
                            groups: GroupDrawAssignment.previewPartitionDraw(
                              items: widget.participantLabels,
                              drawnSeeds: _drawnSeeds,
                              groupSizes: widget.groupSizes,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var index = 0; index < _drawnSeeds.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Chip(
                          avatar: CircleAvatar(child: Text('${index + 1}')),
                          label: Text(
                            widget.participantLabels[_drawnSeeds[index] - 1],
                          ),
                        ),
                      ),
                    if (_drawnSeeds.isEmpty)
                      Text(
                        'Noch kein Spieler gezogen.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSpinning ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: _isSpinning || _remainingSeeds.isEmpty ? null : _spin,
          icon: const Icon(Icons.casino_outlined),
          label: Text(_drawnSeeds.isEmpty ? 'Rad drehen' : 'Nächsten ziehen'),
        ),
        FilledButton(
          onPressed: _isComplete ? _submit : null,
          child: const Text('Auslosung übernehmen'),
        ),
      ],
    );
  }
}

class _DrawCandidateList extends StatelessWidget {
  const _DrawCandidateList({
    required this.remainingSeeds,
    required this.drawnSeeds,
    required this.participantLabels,
  });

  final List<int> remainingSeeds;
  final List<int> drawnSeeds;
  final List<String> participantLabels;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Im Rad', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView(
              children: [
                for (final seed in remainingSeeds)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(radius: 13, child: Text('$seed')),
                    title: Text(
                      participantLabels[seed - 1],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('Gezogen', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SizedBox(
          height: 96,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView(
              children: [
                for (var index = 0; index < drawnSeeds.length; index++)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 13,
                      child: Text('${index + 1}'),
                    ),
                    title: Text(
                      participantLabels[drawnSeeds[index] - 1],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (drawnSeeds.isEmpty)
                  const ListTile(dense: true, title: Text('Noch leer')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AutoRollControls extends StatelessWidget {
  const _AutoRollControls({
    required this.enabled,
    required this.secondsController,
    required this.onEnabledChanged,
    required this.onSecondsChanged,
  });

  final bool enabled;
  final TextEditingController secondsController;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<String> onSecondsChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Switch(value: enabled, onChanged: onEnabledChanged),
          const Expanded(child: Text('Auto-Roll')),
          SizedBox(
            width: 72,
            child: TextField(
              controller: secondsController,
              enabled: enabled,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                suffixText: 's',
              ),
              onChanged: onSecondsChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawGroupPreview extends StatelessWidget {
  const _DrawGroupPreview({required this.groupSizes, required this.groups});

  final List<int> groupSizes;
  final List<List<String?>> groups;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Gruppen-Zulosung', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (
                  var groupIndex = 0;
                  groupIndex < groupSizes.length;
                  groupIndex++
                )
                  SizedBox(
                    width: 210,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.all(color: colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            groupLabel(groupIndex + 1),
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          for (
                            var slot = 0;
                            slot < groupSizes[groupIndex];
                            slot++
                          )
                            Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: groups[groupIndex][slot] != null
                                    ? colorScheme.primaryContainer
                                    : colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: groups[groupIndex][slot] != null
                                      ? colorScheme.primary
                                      : colorScheme.outlineVariant,
                                ),
                              ),
                              child: Text(
                                groups[groupIndex][slot] ?? 'Platz ${slot + 1}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DrawBracketPreview extends StatelessWidget {
  const _DrawBracketPreview({
    required this.bracketSize,
    required this.participantLabels,
    required this.drawnSeeds,
  });

  final int bracketSize;
  final List<String> participantLabels;
  final List<int> drawnSeeds;

  @override
  Widget build(BuildContext context) {
    final labelsBySeed = <String>[
      for (var index = 0; index < participantLabels.length; index++)
        index < drawnSeeds.length
            ? participantLabels[drawnSeeds[index] - 1]
            : 'Noch offen',
    ];
    final slots = [
      for (final bracketSeed in _seedOrderForSize(bracketSize))
        bracketSeed <= participantLabels.length ? bracketSeed : null,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Live-Bracket', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: _CompactKnockoutPreviewTree(
                bracketSize: bracketSize,
                slotOrder: slots,
                participantLabels: labelsBySeed,
                onSwapSlot: (_, _) {},
                qualifyingRank: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DrawWheelPainter extends CustomPainter {
  _DrawWheelPainter({
    required this.labels,
    required this.wheelSeeds,
    required this.selectedSeed,
    required this.rotation,
    required this.colorScheme,
  });

  final List<String> labels;
  final List<int> wheelSeeds;
  final int? selectedSeed;
  final double rotation;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 8;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final segmentAngle = wheelSeeds.isEmpty ? 0.0 : 2 * pi / wheelSeeds.length;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.translate(-center.dx, -center.dy);

    for (var index = 0; index < wheelSeeds.length; index++) {
      final seed = wheelSeeds[index];
      final isSelected = selectedSeed == seed;
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = isSelected
            ? colorScheme.tertiaryContainer
            : (index.isEven
                  ? colorScheme.primaryContainer
                  : colorScheme.secondaryContainer);
      canvas.drawArc(rect, index * segmentAngle, segmentAngle, true, paint);

      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = colorScheme.outlineVariant;
      canvas.drawArc(
        rect,
        index * segmentAngle,
        segmentAngle,
        true,
        strokePaint,
      );

      final angle = index * segmentAngle + segmentAngle / 2;
      final innerRadius = radius * 0.35;
      final labelTrackWidth = (radius - innerRadius) * 0.9;
      final labelRadius = innerRadius + labelTrackWidth / 2 + 4;
      final labelOffset = Offset(
        center.dx + cos(angle) * labelRadius,
        center.dy + sin(angle) * labelRadius,
      );
      final name = seed - 1 < labels.length
          ? labels[seed - 1]
          : 'Spieler $seed';
      final numberPainter = TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w700,
            fontSize: wheelSeeds.length > 22
                ? 9
                : wheelSeeds.length > 14
                ? 10
                : 11,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '.',
      )..layout(maxWidth: labelTrackWidth - 12);
      canvas.save();
      canvas.translate(labelOffset.dx, labelOffset.dy);
      canvas.rotate(angle > pi / 2 && angle < 3 * pi / 2 ? angle + pi : angle);
      final backgroundRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: labelTrackWidth,
          height: numberPainter.height + 6,
        ),
        const Radius.circular(10),
      );
      canvas.drawRRect(
        backgroundRect,
        Paint()..color = colorScheme.surface.withValues(alpha: 0.88),
      );
      numberPainter.paint(
        canvas,
        Offset(-numberPainter.width / 2, -numberPainter.height / 2),
      );
      canvas.restore();
    }

    canvas.restore();

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = colorScheme.primary,
    );

    final pointerPath = Path()
      ..moveTo(center.dx, center.dy - radius - 4)
      ..lineTo(center.dx - 13, center.dy - radius + 28)
      ..lineTo(center.dx + 13, center.dy - radius + 28)
      ..close();
    canvas.drawPath(pointerPath, Paint()..color = colorScheme.error);
  }

  @override
  bool shouldRepaint(covariant _DrawWheelPainter oldDelegate) {
    return oldDelegate.rotation != rotation ||
        oldDelegate.selectedSeed != selectedSeed ||
        oldDelegate.wheelSeeds.length != wheelSeeds.length ||
        oldDelegate.wheelSeeds.join(',') != wheelSeeds.join(',');
  }
}
