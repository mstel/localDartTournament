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
    final roundLabel = leadingLabel ?? 'Runde ${match.round}';
    String playerLabel(bool home) {
      return (home ? match.homePlayer : match.awayPlayer)?.name ??
          (match.allowsBye ? 'Freilos' : 'offen');
    }

    Widget playerName(bool home, {TextAlign textAlign = TextAlign.start}) {
      final player = home ? match.homePlayer : match.awayPlayer;
      final label = playerLabel(home);
      final text = Text(
        label,
        textAlign: textAlign,
        style: Theme.of(context).textTheme.titleMedium,
      );
      if (player == null || onPlayerTap == null) return text;
      return Tooltip(
        message: 'Spiele von ${player.name} anzeigen',
        child: InkWell(
          onTap: () => onPlayerTap!(player),
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Align(
              alignment: textAlign == TextAlign.right
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: text,
            ),
          ),
        ),
      );
    }

    return MatchStatisticsTapTarget(
      match: match,
      tournament: tournament,
      child: Container(
        margin: EdgeInsets.only(bottom: compact ? 4 : 8),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 5 : 10,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < (compact ? 420 : 620) ||
                MediaQuery.textScalerOf(context).scale(16) > 24) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showRoundLabel || originLabel != null) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (showRoundLabel)
                          Text(
                            roundLabel,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        if (originLabel != null)
                          _MatchOriginChip(label: originLabel!),
                      ],
                    ),
                    SizedBox(height: compact ? 4 : 8),
                  ],
                  playerName(true),
                  const SizedBox(height: 4),
                  playerName(false),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Flexible(
                        child: _ScoreBadge(
                          match: match,
                          onTap: match.hasResult
                              ? () => MatchStatisticsTapTarget.open(
                                  context,
                                  match,
                                  tournament: tournament,
                                )
                              : canEdit
                              ? () => onEditResult(match)
                              : null,
                        ),
                      ),
                      const Spacer(),
                      IconButton.filledTonal(
                        onPressed: canEdit ? () => onEditResult(match) : null,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        tooltip: 'Ergebnis',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }

            return Row(
              children: [
                if (showRoundLabel) ...[
                  SizedBox(
                    width: leadingLabel == null ? 74 : 148,
                    child: Text(
                      roundLabel,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (originLabel != null) ...[
                  _MatchOriginChip(label: originLabel!),
                  const SizedBox(width: 8),
                ],
                Expanded(child: playerName(true)),
                _ScoreBadge(
                  match: match,
                  onTap: match.hasResult
                      ? () => MatchStatisticsTapTarget.open(
                          context,
                          match,
                          tournament: tournament,
                        )
                      : canEdit
                      ? () => onEditResult(match)
                      : null,
                ),
                Expanded(child: playerName(false, textAlign: TextAlign.right)),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  onPressed: canEdit ? () => onEditResult(match) : null,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Ergebnis',
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            );
          },
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
  }

  @override
  void dispose() {
    _homeLegsController.dispose();
    _awayLegsController.dispose();
    super.dispose();
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('home-legs-field'),
                    controller: _homeLegsController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      _ScoreLimitInputFormatter(
                        widget.format.bestOfLegs ~/ 2 + 1,
                      ),
                    ],
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: widget.match.homePlayer?.name ?? 'offen',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const ValueKey('away-legs-field'),
                    controller: _awayLegsController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      _ScoreLimitInputFormatter(
                        widget.format.bestOfLegs ~/ 2 + 1,
                      ),
                    ],
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: widget.match.awayPlayer?.name ?? 'offen',
                    ),
                  ),
                ),
              ],
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

class _MatchOriginChip extends StatelessWidget {
  const _MatchOriginChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minWidth: 76),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.match, this.onTap});

  final GroupMatch match;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final badge = Container(
      constraints: BoxConstraints(
        minWidth: match.isAnnulled || match.hasSetScore ? 100 : 64,
        minHeight: 48,
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
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
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );

    if (onTap == null) {
      return badge;
    }

    return Tooltip(
      message: match.hasResult ? 'Spielstatistik öffnen' : 'Ergebnis eingeben',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: badge,
      ),
    );
  }
}
