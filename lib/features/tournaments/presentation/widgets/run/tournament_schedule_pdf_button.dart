import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../../settings/data/app_presentation_preferences.dart';

import '../../../application/order_of_play/order_of_play_controller.dart';
import '../../../application/tournament_flow_priority.dart';
import '../../../domain/tournament_flow_priority_settings.dart';
import '../../../../league/domain/league_match.dart';
import '../../../domain/tournament_models.dart';
import '../../utils/match_display_label.dart';

class TournamentSchedulePdfButton extends StatelessWidget {
  const TournamentSchedulePdfButton({super.key, required this.tournament});

  final CreatedTournament tournament;

  bool get _isUnsupported =>
      tournament.isKratzerTournament ||
      tournament.stages.any(
        (stage) => stage.type == 'swiss' || stage.groupPlayType == 'swiss',
      ) ||
      tournament.runStages.any((stage) {
        if (stage is GroupTournamentRunStage) {
          return stage.groupPlayType.toLowerCase().contains('swiss');
        }
        return stage is KnockoutTournamentRunStage && stage.isKratzer;
      });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _isUnsupported
          ? 'Druck / Exportfunktionen des Spielplans für diesen Modus deaktiviert'
          : 'Spielplan mit offenen Ergebnisfeldern als PDF öffnen',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.picture_as_pdf_outlined),
                  const SizedBox(width: 8),
                  Text(
                    'Spielplan Exportieren',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _isUnsupported ? null : () => _print(context),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.print_outlined),
                label: const Text('Spielplan als .PDF generieren/drucken'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _print(BuildContext context) async {
    try {
      int? selectedStage;
      if (tournament.leagueMatch == null && tournament.runStages.length > 1) {
        selectedStage = await showDialog<int>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Phase für den Export auswählen'),
            children: [
              for (var index = 0; index < tournament.runStages.length; index++)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop(index),
                  child: Text(tournament.runStages[index].name),
                ),
            ],
          ),
        );
        if (selectedStage == null || !context.mounted) return;
      }
      final preferences = await AppPresentationPreferences.load();
      final document = _buildDocument(
        stageIndex: selectedStage,
        preferences: preferences,
      );
      final stageSuffix = selectedStage == null
          ? ''
          : '_${_safeFileName(tournament.runStages[selectedStage].name)}';
      final fileName = '${_safeFileName(tournament.name)}$stageSuffix.pdf';
      await Printing.layoutPdf(
        onLayout: (_) => document.save(),
        format: preferences.pdfLandscape
            ? PdfPageFormat.a4.landscape
            : PdfPageFormat.a4,
        name: fileName,
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('PDF konnte nicht erstellt werden: $error')),
      );
    }
  }

  pw.Document _buildDocument({
    int? stageIndex,
    required AppPresentationPreferences preferences,
  }) {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: preferences.pdfLandscape
            ? PdfPageFormat.a4.landscape
            : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Seite ${context.pageNumber} von ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        build: (context) => [
          pw.Text(
            tournament.name,
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          if (preferences.pdfShowDate)
            pw.Text(
              'Datum: ${tournament.tournamentDate == null ? '__.__.____' : _formatDate(tournament.tournamentDate!)}',
            ),
          pw.SizedBox(height: 18),
          if (tournament.leagueMatch != null)
            ..._leagueContent(tournament.leagueMatch!, preferences)
          else
            ..._tournamentContent(
              stageIndex: stageIndex,
              preferences: preferences,
            ),
        ],
      ),
    );
    return document;
  }

  List<pw.Widget> _leagueContent(
    LeagueMatch league,
    AppPresentationPreferences preferences,
  ) {
    final rows = <List<String>>[
      ['Nr.', 'Begegnung', 'Spielstand'],
    ];
    for (var index = 0; index < league.games.length; index++) {
      final game = league.games[index];
      final home = _leaguePlayers(league.homePlayers, game.home);
      final away = _leaguePlayers(league.awayPlayers, game.away);
      final score = game.complete
          ? '${game.homeScore(league.gameFormat) ?? ''} : '
                '${game.awayScore(league.gameFormat) ?? ''}'
          : '__________';
      rows.add(['${index + 1}', '$home  –  $away', score]);
    }
    return [
      pw.Text(
        '${league.homeTeam}  –  ${league.awayTeam}',
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      _table(rows, [1, 7, 2]),
      if (preferences.pdfShowNotes) ...[
        pw.SizedBox(height: 18),
        pw.Text('Spielbericht / Notizen'),
        pw.SizedBox(height: 8),
        pw.Container(
          height: 75,
          decoration: pw.BoxDecoration(border: pw.Border.all()),
        ),
      ],
      if (preferences.pdfShowSignatures) ...[
        pw.SizedBox(height: 24),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Text('Unterschrift ${league.homeTeam}'),
                  pw.SizedBox(height: 36),
                  pw.Divider(),
                ],
              ),
            ),
            pw.SizedBox(width: 36),
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Text('Unterschrift ${league.awayTeam}'),
                  pw.SizedBox(height: 36),
                  pw.Divider(),
                ],
              ),
            ),
          ],
        ),
      ],
      if (preferences.pdfShowBestPerformances) ...[
        pw.SizedBox(height: 14),
        pw.Text('Bestleistungen'),
        pw.SizedBox(height: 6),
        pw.Container(
          height: 40,
          decoration: pw.BoxDecoration(border: pw.Border.all()),
        ),
      ],
    ];
  }

  List<pw.Widget> _tournamentContent({
    int? stageIndex,
    required AppPresentationPreferences preferences,
  }) {
    final content = <pw.Widget>[];
    final stages = stageIndex == null
        ? tournament.runStages
        : [tournament.runStages[stageIndex]];
    for (final stage in stages) {
      final stageIndex = tournament.runStages.indexOf(stage);
      final priority = TournamentFlowPriority.forStage(
        stage,
        settings: TournamentFlowPrioritySettings(
          playerMatchDeficitThreshold:
              tournament.tournamentSettings.playerMatchDeficitThreshold,
          groupMatchDeficitThreshold:
              tournament.tournamentSettings.groupMatchDeficitThreshold,
          usePercentageForGroups:
              tournament.tournamentSettings.usePercentageForGroups,
          enabled: tournament.tournamentSettings.priorityHintsEnabled,
        ),
      );
      final orderedEntries = stageIndex < 0
          ? const <PlayEntry>[]
          : const OrderOfPlayController().orderedEntriesForStage(
              tournament,
              stageIndex,
              prioritizedMatches: priority.prioritizedMatches,
              deprioritizedMatches: priority.deprioritizedMatches,
            );
      final scheduleOrder = {
        for (var index = 0; index < orderedEntries.length; index++)
          orderedEntries[index].match: index,
      };
      content.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
          child: pw.Text(
            stage.name,
            style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold),
          ),
        ),
      );
      if (stage is GroupTournamentRunStage) {
        final roundLabels = <GroupMatch, String>{};
        for (final group in stage.groups) {
          for (final match in group.matches) {
            roundLabels[match] = 'Gruppe ${group.name} · Runde ${match.round}';
          }
        }
        final matches = roundLabels.keys.toList()
          ..sort(
            (a, b) => (scheduleOrder[a] ?? 1 << 30).compareTo(
              scheduleOrder[b] ?? 1 << 30,
            ),
          );
        content.add(
          _table(
            [
              ['Runde / Gruppe', 'Heim', 'Gast', 'Ergebnis'],
              for (final match in matches)
                _matchRow(match, roundLabels[match]!),
            ],
            [2, 4, 4, 2],
          ),
        );
        for (final group in stage.groups) {
          content.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 5, bottom: 8),
              child: pw.Text(
                '${group.name} · Tie-Breaker: ${stage.tieBreakers.map(tieBreakerLabel).join(' → ')}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          );
        }
      } else if (stage is KnockoutTournamentRunStage) {
        if (stage.eliminationLossLimit >= 3) {
          content.addAll(_tripleKoContent(stage));
        } else {
          content.add(_bracketDiagram(stage.rounds));
        }
        if (stage.placementMatches.isNotEmpty) {
          content
            ..add(
              pw.Text(
                'Platzierungsspiele',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            )
            ..add(
              _table(
                [
                  ['Begegnung', 'Heim', 'Gast', 'Ergebnis'],
                  for (
                    var index = 0;
                    index < stage.placementMatches.length;
                    index++
                  )
                    _matchRow(
                      stage.placementMatches[index],
                      matchDisplayLabel(
                        stage.placementMatches[index].label,
                        fallback: 'Begegnung ${index + 1}',
                      ),
                    ),
                ],
                [2, 4, 4, 2],
              ),
            );
        }
      }
    }
    if (preferences.pdfShowAdvancement) {
      for (final stage in stages.whereType<GroupTournamentRunStage>()) {
        final advancing = stage.qualificationPlan?.totalQualifiers;
        if (advancing != null) {
          content.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                '$advancing Teilnehmende werden in die nächste Etappe übertragen.',
              ),
            ),
          );
        }
      }
    }
    if (preferences.pdfShowBestPerformances) {
      final performances = <String>[];
      for (final stage in stages) {
        if (stage is GroupTournamentRunStage) {
          for (final group in stage.groups) {
            for (final match in [
              ...group.matches,
              ...group.knockoutRounds.expand((round) => round),
            ]) {
              performances.addAll(
                match.bestPerformances.map(
                  (item) =>
                      '${item.playerName} · ${item.type}${item.value == null ? '' : ' · ${item.value}'}',
                ),
              );
            }
          }
        } else if (stage is KnockoutTournamentRunStage) {
          for (final match in stage.matches) {
            performances.addAll(
              match.bestPerformances.map(
                (item) =>
                    '${item.playerName} · ${item.type}${item.value == null ? '' : ' · ${item.value}'}',
              ),
            );
          }
        }
      }
      content.addAll([
        pw.SizedBox(height: 12),
        pw.Text(
          'Bestleistungen',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        if (performances.isEmpty)
          pw.Container(
            height: 40,
            decoration: pw.BoxDecoration(border: pw.Border.all()),
          )
        else
          ...performances.map(pw.Text.new),
      ]);
    }
    if (preferences.pdfShowNotes) {
      content.addAll([
        pw.SizedBox(height: 12),
        pw.Text('Notizen'),
        pw.SizedBox(height: 6),
        pw.Container(
          height: 65,
          decoration: pw.BoxDecoration(border: pw.Border.all()),
        ),
      ]);
    }
    return content;
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

  List<pw.Widget> _tripleKoContent(KnockoutTournamentRunStage stage) {
    final matches = stage.rounds.expand((round) => round).toList();
    final winners = <int, List<GroupMatch>>{};
    final losers = <int, List<GroupMatch>>{};
    final elimination = <int, List<GroupMatch>>{};
    final finals = <GroupMatch>[];
    for (final match in matches) {
      final label = match.label ?? '';
      if (label == 'Triple-KO Finalrunde') {
        finals.add(match);
        continue;
      }
      final labelParts = label.split(' Runde ');
      final losses = int.tryParse(labelParts.first.split(' ').first);
      final round = labelParts.length == 2
          ? int.tryParse(labelParts.last)
          : null;
      if (losses == null || round == null) continue;
      final target = losses == 0
          ? winners
          : losses == 1
          ? losers
          : elimination;
      (target[round] ??= []).add(match);
    }
    return [
      _tripleTree('Winners Bracket · 0 Niederlagen', winners),
      _tripleTree('Losers Bracket · 1 Niederlage', losers),
      _tripleTree('Elimination Bracket · 2 Niederlagen', elimination),
      _tripleTree('Finale', {1: finals}),
    ];
  }

  pw.Widget _tripleTree(String title, Map<int, List<GroupMatch>> rounds) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          _bracketDiagram([
            for (final round in rounds.keys.toList()..sort())
              rounds[round]!
                ..sort((left, right) => left.round.compareTo(right.round)),
          ]),
          pw.SizedBox(height: 8),
        ],
      );

  pw.Widget _bracketDiagram(List<List<GroupMatch>> rounds) {
    if (rounds.isEmpty || rounds.first.isEmpty) {
      return pw.Container(
        height: 120,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey500),
        ),
        child: pw.Text('Turnierbaum-Vorschau'),
      );
    }
    const drawingWidth = 740.0;
    const drawingHeight = 320.0;
    const roundGap = 20.0;
    final columnWidth =
        (drawingWidth - roundGap * (rounds.length - 1)) / rounds.length;
    final nodeWidth = (columnWidth - 8).clamp(12.0, 150.0).toDouble();
    final baseMatchCount = rounds.first.length;
    final nodeHeight = (drawingHeight / baseMatchCount * 0.72)
        .clamp(4.0, 28.0)
        .toDouble();
    double xForRound(int roundIndex) => roundIndex * (columnWidth + roundGap);
    double yForMatch(int roundIndex, int matchIndex) {
      final matchCount = rounds[roundIndex].length;
      return drawingHeight - (matchIndex + 0.5) * drawingHeight / matchCount;
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          'Unausgefüllter Turnierbaum',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          children: [
            for (var roundIndex = 0; roundIndex < rounds.length; roundIndex++)
              pw.Expanded(
                child: pw.Text(
                  _roundLabel(roundIndex, rounds.length),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.CustomPaint(
          size: const PdfPoint(drawingWidth, drawingHeight),
          painter: (canvas, _) {
            canvas
              ..setStrokeColor(PdfColors.grey700)
              ..setLineWidth(0.8);
            for (
              var roundIndex = 0;
              roundIndex < rounds.length - 1;
              roundIndex++
            ) {
              final currentRound = rounds[roundIndex];
              final nextRound = rounds[roundIndex + 1];
              for (
                var parentIndex = 0;
                parentIndex < nextRound.length;
                parentIndex++
              ) {
                final firstChild = parentIndex * 2;
                if (firstChild + 1 >= currentRound.length) continue;
                final firstY = yForMatch(roundIndex, firstChild);
                final secondY = yForMatch(roundIndex, firstChild + 1);
                final parentY = yForMatch(roundIndex + 1, parentIndex);
                final startX = xForRound(roundIndex) + nodeWidth;
                final endX = xForRound(roundIndex + 1);
                final middleX = (startX + endX) / 2;
                canvas
                  ..drawLine(startX, firstY, middleX, firstY)
                  ..drawLine(startX, secondY, middleX, secondY)
                  ..drawLine(middleX, firstY, middleX, secondY)
                  ..drawLine(middleX, parentY, endX, parentY)
                  ..strokePath();
              }
            }
            for (var roundIndex = 0; roundIndex < rounds.length; roundIndex++) {
              for (
                var matchIndex = 0;
                matchIndex < rounds[roundIndex].length;
                matchIndex++
              ) {
                final y = yForMatch(roundIndex, matchIndex) - nodeHeight / 2;
                canvas
                  ..drawRect(xForRound(roundIndex), y, nodeWidth, nodeHeight)
                  ..drawLine(
                    xForRound(roundIndex),
                    y,
                    xForRound(roundIndex) + nodeWidth,
                    y,
                  )
                  ..strokePath();
              }
            }
          },
        ),
      ],
    );
  }

  String _roundLabel(int roundIndex, int roundCount) {
    if (roundIndex == roundCount - 1) return 'Finale';
    if (roundIndex == roundCount - 2) return 'Halbfinale';
    return 'Runde ${roundIndex + 1}';
  }

  List<String> _matchRow(GroupMatch match, String label) => [
    matchDisplayLabel(label, fallback: ''),
    match.homePlayer?.name ?? '________________',
    match.awayPlayer?.name ?? '________________',
    match.hasResult
        ? '${match.homeScore ?? 0} : ${match.awayScore ?? 0}'
        : '__________',
  ];

  pw.Widget _table(List<List<String>> rows, List<double> widths) => pw.Table(
    border: pw.TableBorder.all(width: 0.5),
    columnWidths: {
      for (var index = 0; index < widths.length; index++)
        index: pw.FlexColumnWidth(widths[index]),
    },
    children: [
      for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
        pw.TableRow(
          decoration: rowIndex == 0
              ? const pw.BoxDecoration(color: PdfColors.grey300)
              : null,
          children: [
            for (final cell in rows[rowIndex])
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                  cell,
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: rowIndex == 0
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                  ),
                ),
              ),
          ],
        ),
    ],
  );

  String _leaguePlayers(List<String> roster, List<int> indices) => indices
      .map((index) => index >= 0 && index < roster.length ? roster[index] : '?')
      .join(' / ');

  String _safeFileName(String value) {
    final normalized = value
        .trim()
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('Ä', 'Ae')
        .replaceAll('Ö', 'Oe')
        .replaceAll('Ü', 'Ue')
        .replaceAll('ß', 'ss')
        .replaceAll(RegExp(r'[^\w-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return normalized.isEmpty ? 'Turnier' : normalized;
  }
}
