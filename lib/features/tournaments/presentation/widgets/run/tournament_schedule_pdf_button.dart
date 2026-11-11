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
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
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
      final document = _buildDocument();
      await Printing.layoutPdf(
        onLayout: (_) => document.save(),
        name: '${_safeFileName(tournament.name)}-spielplan.pdf',
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('PDF konnte nicht erstellt werden: $error')),
      );
    }
  }

  pw.Document _buildDocument() {
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
          pw.Text(_formatDate(tournament.effectiveDate)),
          pw.SizedBox(height: 18),
          if (tournament.leagueMatch != null)
            ..._leagueContent(tournament.leagueMatch!)
          else
            ..._tournamentContent(),
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
      pw.SizedBox(height: 18),
      pw.Text('Unterschrift Heimteam: ____________________'),
      pw.SizedBox(height: 8),
      pw.Text('Unterschrift Gastteam: ____________________'),
    ];
  }

  List<pw.Widget> _tournamentContent() {
    final content = <pw.Widget>[];
    for (final stage in tournament.runStages) {
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
          content.add(_bracketTable(stage.rounds));
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
          _bracketTable([
            for (final round in rounds.keys.toList()..sort())
              rounds[round]!
                ..sort((left, right) => left.round.compareTo(right.round)),
          ]),
          pw.SizedBox(height: 8),
        ],
      );

  pw.Widget _bracketTable(List<List<GroupMatch>> rounds) {
    if (rounds.isEmpty || rounds.first.isEmpty) {
      return _table(
        [
          ['Noch keine Begegnungen'],
        ],
        [1],
      );
    }
    final slotCount = rounds.first.length * 2;
    return _table(
      [
        [
          for (var index = 0; index < rounds.length; index++)
            'Runde ${index + 1}',
        ],
        for (var slot = 0; slot < slotCount; slot++)
          [
            for (var round = 0; round < rounds.length; round++)
              _bracketCell(rounds, slot, round),
          ],
      ],
      [for (var index = 0; index < rounds.length; index++) 1],
    );
  }

  String _bracketCell(List<List<GroupMatch>> rounds, int slot, int round) {
    final span = 1 << (round + 1);
    if (slot % span != span ~/ 2 - 1) return '';
    final matchIndex = slot ~/ span;
    if (matchIndex >= rounds[round].length) return '';
    final match = rounds[round][matchIndex];
    return '${matchDisplayLabel(match.label, fallback: 'Begegnung ${match.round}')}\n'
        '${match.homePlayer?.name ?? '________________'}\n'
        'vs. ${match.awayPlayer?.name ?? '________________'}\n'
        'Ergebnis: ${match.hasResult ? '${match.homeScore ?? 0} : ${match.awayScore ?? 0}' : '__________'}';
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

  String _formatDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}.${value.year}';

  String _safeFileName(String value) =>
      value.replaceAll(RegExp(r'[^\w-]+'), '_').replaceAll(RegExp(r'_+'), '_');
}
