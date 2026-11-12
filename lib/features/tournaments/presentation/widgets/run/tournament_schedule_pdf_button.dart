import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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
      final document = _buildDocument(stageIndex: selectedStage);
      final stageName = tournament.leagueMatch != null
          ? 'Spielplan'
          : tournament.runStages[selectedStage ?? 0].name;
      await Printing.layoutPdf(
        onLayout: (_) => document.save(),
        format: PdfPageFormat.a4.landscape,
        name:
            '${_safeFileName(tournament.name)}_${_safeFileName(stageName)}.pdf',
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('PDF konnte nicht erstellt werden: $error')),
      );
    }
  }

  pw.Document _buildDocument({int? stageIndex}) {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
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
          pw.Text('Datum: __.__.____'),
          pw.SizedBox(height: 18),
          if (tournament.leagueMatch != null)
            ..._leagueContent(tournament.leagueMatch!)
          else
            ..._tournamentContent(stageIndex: stageIndex),
        ],
      ),
    );
    return document;
  }

  List<pw.Widget> _leagueContent(LeagueMatch league) {
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
      pw.SizedBox(height: 18),
      pw.Text('Spielbericht / Notizen'),
      pw.SizedBox(height: 8),
      pw.Container(
        height: 75,
        decoration: pw.BoxDecoration(border: pw.Border.all()),
      ),
    ];
  }

  List<pw.Widget> _tournamentContent({int? stageIndex}) {
    final content = <pw.Widget>[];
    final stages = stageIndex == null
        ? tournament.runStages
        : [tournament.runStages[stageIndex]];
    for (final stage in stages) {
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
        for (final group in stage.groups) {
          content
            ..add(pw.Text(group.name, style: pw.TextStyle(fontSize: 13)))
            ..add(
              _table(
                [
                  ['Runde', 'Heim', 'Gast', 'Ergebnis'],
                  for (final match in group.matches)
                    _matchRow(match, match.round.toString()),
                ],
                [1, 4, 4, 2],
              ),
            )
            ..add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 5, bottom: 8),
                child: pw.Text(
                  'Tie-Breaker: ${stage.tieBreakers.map(tieBreakerLabel).join(' → ')}',
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
    return content;
  }

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
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          'Unausgefüllter Turnierbaum',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            for (var roundIndex = 0; roundIndex < rounds.length; roundIndex++)
              pw.Expanded(
                child: pw.Padding(
                  padding: pw.EdgeInsets.only(
                    right: roundIndex == rounds.length - 1 ? 0 : 10,
                  ),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Text(
                        _roundLabel(roundIndex, rounds.length),
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      for (
                        var matchIndex = 0;
                        matchIndex < rounds[roundIndex].length;
                        matchIndex++
                      )
                        _bracketMatchCard(
                          rounds[roundIndex][matchIndex],
                          roundIndex: roundIndex,
                          matchIndex: matchIndex,
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _roundLabel(int roundIndex, int roundCount) {
    if (roundIndex == roundCount - 1) return 'Finale';
    if (roundIndex == roundCount - 2) return 'Halbfinale';
    return 'Runde ${roundIndex + 1}';
  }

  pw.Widget _bracketMatchCard(
    GroupMatch match, {
    required int roundIndex,
    required int matchIndex,
  }) {
    final home = roundIndex == 0
        ? match.homePlayer?.name ?? 'Teilnehmer ${matchIndex * 2 + 1}'
        : 'Sieger Spiel ${matchIndex * 2 + 1}';
    final away = roundIndex == 0
        ? match.awayPlayer?.name ?? 'Teilnehmer ${matchIndex * 2 + 2}'
        : 'Sieger Spiel ${matchIndex * 2 + 2}';
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 3),
      padding: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey600, width: 0.7),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            matchDisplayLabel(match.label, fallback: 'Spiel ${match.round}'),
            style: const pw.TextStyle(fontSize: 7),
          ),
          pw.Divider(height: 5, thickness: 0.4),
          pw.Text(home, maxLines: 1, style: const pw.TextStyle(fontSize: 8)),
          pw.Divider(height: 5, thickness: 0.4),
          pw.Text(away, maxLines: 1, style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
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

  String _safeFileName(String value) =>
      value.replaceAll(RegExp(r'[^\w-]+'), '_').replaceAll(RegExp(r'_+'), '_');
}
