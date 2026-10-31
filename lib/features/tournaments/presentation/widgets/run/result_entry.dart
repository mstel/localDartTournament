import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/tournament_models.dart';
import '../../../domain/set_result_validation.dart';
import '../../models/match_result.dart';
import 'set_result_dialog.dart';
import 'best_performance_editor.dart';
import '../../../../statistics/domain/best_performance.dart';
import '../../../../statistics/presentation/tournament_match_statistics_page.dart';

class MatchResultTile extends StatelessWidget {
  const MatchResultTile({
    super.key,
    required this.match,
    required this.onEditResult,
    required this.canEditResult,
    this.tournament,
    this.originLabel,
    this.leadingLabel,
    this.showRoundLabel = true,
    this.compact = false,
    this.onPlayerTap,
  });

  final GroupMatch match;
  final void Function(GroupMatch match) onEditResult;
  final bool canEditResult;
  final CreatedTournament? tournament;
  final String? originLabel;
  final String? leadingLabel;
  final bool showRoundLabel;
  final bool compact;
  final ValueChanged<TournamentPlayer>? onPlayerTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canEdit = canEditResult && match.hasPlayers;
    String playerLabel(bool home) {
      return (home ? match.homePlayer : match.awayPlayer)?.name ??
          (match.allowsBye ? 'Freilos' : 'offen');
    }

    Widget playerName(bool home, {TextAlign textAlign = TextAlign.start}) {
      final player = home ? match.homePlayer : match.awayPlayer;
      final label = playerLabel(home);
      final winner = match.winner;
      final isWinner = match.hasResult && player != null && winner == player;
      final isLoser =
          match.hasResult && player != null && winner != null && !isWinner;
      final text = Align(
        alignment: textAlign == TextAlign.right
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isWinner
                ? const Color(0xFF4ED9A4)
                : isLoser
                ? const Color(0xFFFF7777)
                : null,
            fontWeight: isWinner ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      );
      if (player == null || onPlayerTap == null) {
        return SizedBox(height: 48, child: text);
      }
      return Tooltip(
        message: 'Spiele von ${player.name} anzeigen',
        child: InkWell(
          onTap: () => onPlayerTap!(player),
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(height: 48, child: text),
        ),
      );
    }

    return MatchStatisticsTapTarget(
      match: match,
      tournament: tournament,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withAlpha(120),
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingLabel != null)
              Padding(
                padding: const EdgeInsets.only(left: 2, top: 2),
                child: Text(
                  leadingLabel!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.secondary,
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.only(bottom: compact ? 0 : 4),
              child: Row(
                children: [
                  Expanded(child: playerName(true)),
                  _ScoreBadge(
                    match: match,
                    compact: compact,
                    onTap: canEdit
                        ? () => onEditResult(match)
                        : match.hasResult
                        ? () => MatchStatisticsTapTarget.open(
                            context,
                            match,
                            tournament: tournament,
                          )
                        : null,
                  ),
                  Expanded(
                    child: playerName(false, textAlign: TextAlign.right),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ResultDialog extends StatefulWidget {
  const ResultDialog({
    super.key,
    required this.match,
    this.format = const TournamentGameFormat(),
    this.allowAdministration = true,
  });

  final TournamentGameFormat format;
  final bool allowAdministration;

  final GroupMatch match;

  @override
  State<ResultDialog> createState() => _ResultDialogState();
}

class _ResultDialogState extends State<ResultDialog> {
  String? _error;
  bool _recordBestPerformances = false;
  List<BestPerformance> _bestPerformances = [];
  late final TextEditingController _homeLegsController;
  late final TextEditingController _awayLegsController;
  late final FocusNode _homeFocusNode;
  late final FocusNode _awayFocusNode;

  @override
  void initState() {
    super.initState();
    _bestPerformances = [...widget.match.bestPerformances];
    _recordBestPerformances = _bestPerformances.isNotEmpty;
    _homeLegsController = TextEditingController(
      text: widget.match.homeLegs?.toString() ?? '0',
    );
    _awayLegsController = TextEditingController(
      text: widget.match.awayLegs?.toString() ?? '0',
    );
    _homeFocusNode = FocusNode();
    _awayFocusNode = FocusNode();
    _homeFocusNode.addListener(() {
      if (_homeFocusNode.hasFocus) {
        _selectInitialZero(_homeLegsController);
      }
    });
    _awayFocusNode.addListener(() {
      if (_awayFocusNode.hasFocus) {
        _selectInitialZero(_awayLegsController);
      }
    });
  }

  @override
  void dispose() {
    _homeFocusNode.dispose();
    _awayFocusNode.dispose();
    _homeLegsController.dispose();
    _awayLegsController.dispose();
    super.dispose();
  }

  void _selectInitialZero(TextEditingController controller) {
    if (controller.text != '0') return;
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  void _save() {
    final homeLegs = int.tryParse(_homeLegsController.text);
    final awayLegs = int.tryParse(_awayLegsController.text);
    if (homeLegs == null ||
        awayLegs == null ||
        !isValidLegResult(
          widget.format,
          homeLegs: homeLegs,
          awayLegs: awayLegs,
        )) {
      setState(
        () => _error =
            'Das Ergebnis muss zum Spielformat passen; pro Seite sind höchstens ${widget.format.bestOfLegs ~/ 2 + 1} Legs möglich.',
      );
      return;
    }
    if (widget.match.isDecider && homeLegs == awayLegs) {
      setState(
        () => _error =
            'Unentschieden nur bei gerader Leg-Zahl und vollständig gespieltem Match. Entscheidungsspiele benötigen einen Sieger.',
      );
      return;
    }

    Navigator.of(context).pop(
      MatchResult(
        homeLegs: homeLegs,
        awayLegs: awayLegs,
        bestPerformances: _recordBestPerformances
            ? _bestPerformances
            : const [],
      ),
    );
  }

  Widget _stepperSuffix(TextEditingController controller, int max) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          canRequestFocus: false,
          onTap: () {
            final current = int.tryParse(controller.text) ?? 0;
            if (current < max) {
              controller.text = '${current + 1}';
              controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: controller.text.length,
              );
            }
          },
          child: const Icon(Icons.arrow_drop_up, size: 22),
        ),
        InkWell(
          canRequestFocus: false,
          onTap: () {
            final current = int.tryParse(controller.text) ?? 0;
            if (current > 0) {
              controller.text = '${current - 1}';
              controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: controller.text.length,
              );
            }
          },
          child: const Icon(Icons.arrow_drop_down, size: 22),
        ),
      ],
    );
  }

  void _annul() {
    Navigator.of(context).pop(const MatchResult.annulled());
  }

  @override
  Widget build(BuildContext context) {
    if (widget.format.bestOfSets > 1) {
      return SetResultDialog(
        match: widget.match,
        format: widget.format,
        allowAdministration: widget.allowAdministration,
      );
    }
    return AlertDialog(
      title: const Text('Ergebnis eingeben'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (widget.format.allowsDraws)
              Text(
                widget.match.isDecider
                    ? 'Entscheidungsspiel: bei Gleichstand ein zusätzliches Leg spielen.'
                    : 'Unentschieden: 1 Punkt je Spieler',
              ),
            Text(
              '${widget.match.homePlayer?.name ?? 'offen'} vs '
              '${widget.match.awayPlayer?.name ?? 'offen'}',
            ),
            const SizedBox(height: 16),
            Builder(
              builder: (context) {
                final maxLegs = widget.format.bestOfLegs ~/ 2 + 1;
                return Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('home-legs-field'),
                        controller: _homeLegsController,
                        focusNode: _homeFocusNode,
                        autofocus: true,
                        onTap: () => _selectInitialZero(_homeLegsController),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [_ScoreLimitInputFormatter(maxLegs)],
                        onSubmitted: (_) {
                          _awayFocusNode.requestFocus();
                          _selectInitialZero(_awayLegsController);
                        },
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: widget.match.homePlayer?.name ?? 'offen',
                          suffixIcon: _stepperSuffix(
                            _homeLegsController,
                            maxLegs,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('away-legs-field'),
                        controller: _awayLegsController,
                        focusNode: _awayFocusNode,
                        onTap: () => _selectInitialZero(_awayLegsController),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [_ScoreLimitInputFormatter(maxLegs)],
                        onSubmitted: (_) => _save(),
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: widget.match.awayPlayer?.name ?? 'offen',
                          suffixIcon: _stepperSuffix(
                            _awayLegsController,
                            maxLegs,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _recordBestPerformances,
              title: const Text('Bestleistung erfassen'),
              onChanged: (value) => setState(() {
                _recordBestPerformances = value ?? false;
                if (!_recordBestPerformances) _bestPerformances = [];
              }),
            ),
            if (_recordBestPerformances)
              BestPerformanceEditor(
                match: widget.match,
                initial: _bestPerformances,
                onChanged: (items) => _bestPerformances = items,
              ),
          ],
        ),
      ),
      actions: [
        if (widget.allowAdministration &&
            (widget.match.homeLegs != null ||
                widget.match.awayLegs != null ||
                widget.match.isAnnulled))
          TextButton.icon(
            onPressed: () =>
                Navigator.of(context).pop(const MatchResult.cleared()),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Ergebnis entfernen'),
          ),
        if (widget.allowAdministration)
          TextButton.icon(
            onPressed: _annul,
            icon: const Icon(Icons.block_outlined),
            label: const Text('Spiel annullieren'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _save, child: const Text('Speichern')),
      ],
    );
  }
}

class _ScoreLimitInputFormatter extends TextInputFormatter {
  const _ScoreLimitInputFormatter(this.maximum);

  final int maximum;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final value = int.tryParse(newValue.text);
    return value != null && value <= maximum ? newValue : oldValue;
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.match, required this.compact, this.onTap});

  final GroupMatch match;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final badge = Container(
      width: match.isAnnulled
          ? 72
          : compact
          ? 40
          : 48,
      height: compact ? 32 : 36,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: match.isAnnulled
            ? colorScheme.errorContainer
            : match.hasResult
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        match.isAnnulled
            ? 'annulliert'
            : match.hasResult
            ? match.scoreLabel
            : '-:-',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: compact ? 11 : 12,
        ),
      ),
    );

    if (onTap == null) {
      return SizedBox(width: 48, height: 48, child: Center(child: badge));
    }

    return Tooltip(
      message: match.hasResult ? 'Ergebnis bearbeiten' : 'Ergebnis eingeben',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: SizedBox(width: 48, height: 48, child: Center(child: badge)),
      ),
    );
  }
}
