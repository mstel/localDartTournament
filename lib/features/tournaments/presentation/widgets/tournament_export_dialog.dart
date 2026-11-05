import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../rankings/application/tournament_ranking_changes_service.dart';
import '../../application/tournament_export.dart';
import '../../application/tournament_completion_image_generator.dart';
import '../../domain/tournament_models.dart';
import '../../data/app_database.dart';
import '../../data/tournament_storage.dart';
import '../../../../shared/utils/png_image_export.dart';

class TournamentExportDialog {
  static Future<void> show(
    BuildContext context,
    CreatedTournament tournament, {
    Map<String, Object?>? resultSummary,
    required TournamentCompletionImageData completionImageData,
    LocalAppDatabase? database,
    TournamentStorage? storage,
  }) async {
    final data = TournamentExport.encode(tournament);
    var changes = const <TournamentRankingPlayerChange>[];
    try {
      changes = await TournamentRankingChangesService(
        database: database,
        storage: storage,
      ).calculate(tournament);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ranglistenänderungen konnten nicht exportiert werden: $error',
            ),
          ),
        );
      }
    }
    if (!context.mounted) return;
    final rankingChanges = changes
        .map((change) => change.toExportJson())
        .toList();
    final imageData = TournamentCompletionImageData(
      tournamentName: completionImageData.tournamentName,
      tournamentType: completionImageData.tournamentType,
      participantCount: completionImageData.participantCount,
      matchCount: completionImageData.matchCount,
      legCount: completionImageData.legCount,
      averageLegsPerMatch: completionImageData.averageLegsPerMatch,
      durationSummary: completionImageData.durationSummary,
      podium: completionImageData.podium,
      rankingChanges: changes,
      bestPerformances: completionImageData.bestPerformances,
    );
    final html = TournamentExport.html(
      tournament,
      resultSummary: resultSummary,
      rankingChanges: rankingChanges,
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Turnierdaten exportieren'),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: SelectableText(data, style: const TextStyle(fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Schließen'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: data));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Turnierdaten kopiert.')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('JSON kopieren'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: html));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('HTML-Übersicht kopiert.')),
                );
              }
            },
            icon: const Icon(Icons.language),
            label: const Text('HTML kopieren'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final bytes = await const TournamentCompletionImageGenerator()
                  .generatePortraitPng(
                    data: imageData,
                    colorScheme: Theme.of(context).colorScheme,
                  );
              if (!context.mounted) return;
              await exportPngImage(
                context,
                bytes: bytes,
                fileName:
                    'turnierabschluss-${tournament.name.trim().replaceAll(RegExp(r'\s+'), '-').toLowerCase()}.png',
                successMessage: 'Turnierabschluss-Grafik exportiert.',
              );
            },
            icon: const Icon(Icons.image_outlined),
            label: const Text('Hochformat-Grafik exportieren'),
          ),
        ],
      ),
    );
  }
}
