import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../rankings/application/tournament_ranking_changes_service.dart';
import '../../statistics/domain/best_performance.dart';

class TournamentCompletionPodiumEntry {
  const TournamentCompletionPodiumEntry({
    required this.place,
    required this.playerName,
    required this.wins,
    required this.losses,
    required this.legsFor,
    required this.legsAgainst,
  });

  final int place;
  final String playerName;
  final int wins;
  final int losses;
  final int legsFor;
  final int legsAgainst;
}

class TournamentCompletionImageData {
  const TournamentCompletionImageData({
    required this.tournamentName,
    required this.tournamentType,
    required this.participantCount,
    required this.matchCount,
    required this.legCount,
    required this.averageLegsPerMatch,
    required this.durationSummary,
    required this.podium,
    required this.rankingChanges,
    required this.bestPerformances,
  });

  final String tournamentName;
  final String tournamentType;
  final int participantCount;
  final int matchCount;
  final int legCount;
  final double averageLegsPerMatch;
  final String durationSummary;
  final List<TournamentCompletionPodiumEntry> podium;
  final List<TournamentRankingPlayerChange> rankingChanges;
  final List<BestPerformance> bestPerformances;
}

class TournamentCompletionImageGenerator {
  const TournamentCompletionImageGenerator();

  Future<Uint8List> generatePortraitPng({
    required TournamentCompletionImageData data,
    required ColorScheme colorScheme,
  }) async {
    const width = 1080.0;
    const padding = 56.0;
    const contentWidth = width - padding * 2;
    const sectionGap = 20.0;
    final leagueMoves = data.rankingChanges
        .where((change) => change.hasTierChange)
        .toList();
    final height =
        padding * 2 +
        126 +
        220 +
        sectionGap +
        92 +
        data.podium.length * 58 +
        sectionGap +
        92 +
        data.rankingChanges.length * 58 +
        (leagueMoves.isEmpty ? 0 : sectionGap + 92 + leagueMoves.length * 58) +
        sectionGap +
        92 +
        data.bestPerformances.length * 54;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = colorScheme.surface,
    );

    var y = padding;
    _text(
      canvas,
      data.tournamentName,
      Offset(padding, y),
      maxWidth: contentWidth,
      fontSize: 42,
      color: colorScheme.onSurface,
      bold: true,
    );
    y += 58;
    _text(
      canvas,
      '${data.tournamentType} · Turnier abgeschlossen',
      Offset(padding, y),
      maxWidth: contentWidth,
      fontSize: 22,
      color: colorScheme.onSurfaceVariant,
    );
    y += 68;

    final summaryHeight = 220.0;
    _section(canvas, padding, y, contentWidth, summaryHeight, colorScheme);
    _sectionTitle(
      canvas,
      'Turnierübersicht',
      padding + 24,
      y + 20,
      colorScheme,
    );
    const metricGap = 12.0;
    final metricWidth = (contentWidth - 48 - metricGap) / 2;
    final metrics = [
      ('Teilnehmer', '${data.participantCount}'),
      ('Begegnungen', '${data.matchCount}'),
      ('Gespielte Legs', '${data.legCount}'),
      ('Legs / Match', data.averageLegsPerMatch.toStringAsFixed(1)),
    ];
    for (var index = 0; index < metrics.length; index++) {
      final row = index ~/ 2;
      final column = index % 2;
      final x = padding + 24 + column * (metricWidth + metricGap);
      final top = y + 66 + row * 54;
      _text(
        canvas,
        '${metrics[index].$1}: ${metrics[index].$2}',
        Offset(x, top),
        maxWidth: metricWidth,
        fontSize: 21,
        color: colorScheme.onSurface,
        bold: true,
      );
    }
    if (data.durationSummary.isNotEmpty) {
      _text(
        canvas,
        data.durationSummary,
        Offset(padding + 24, y + 180),
        maxWidth: contentWidth - 48,
        fontSize: 18,
        color: colorScheme.onSurfaceVariant,
      );
    }
    y += summaryHeight + sectionGap;

    _section(
      canvas,
      padding,
      y,
      contentWidth,
      92 + data.podium.length * 58,
      colorScheme,
    );
    _sectionTitle(canvas, 'Podium', padding + 24, y + 20, colorScheme);
    for (var index = 0; index < data.podium.length; index++) {
      final entry = data.podium[index];
      _text(
        canvas,
        '${entry.place}. ${entry.playerName} · ${entry.wins} Siege · '
        '${entry.losses} Niederlagen · ${entry.legsFor}:${entry.legsAgainst} Legs',
        Offset(padding + 24, y + 66 + index * 58),
        maxWidth: contentWidth - 48,
        fontSize: 19,
        color: colorScheme.onSurface,
      );
    }
    y += 92 + data.podium.length * 58 + sectionGap;

    _section(
      canvas,
      padding,
      y,
      contentWidth,
      92 + data.rankingChanges.length * 58,
      colorScheme,
    );
    _sectionTitle(
      canvas,
      'Elo und Ranglistenplätze',
      padding + 24,
      y + 20,
      colorScheme,
    );
    for (var index = 0; index < data.rankingChanges.length; index++) {
      final change = data.rankingChanges[index];
      final elo = '${change.delta >= 0 ? '+' : ''}${change.delta} Elo';
      final positions =
          change.rankingPositionBefore == null ||
              change.rankingPositionAfter == null
          ? 'Platzierung nicht verfügbar'
          : 'Platz ${change.rankingPositionBefore} → ${change.rankingPositionAfter}';
      final movement = switch (change.positionChange) {
        final value? when value > 0 => '↑ $positions',
        final value? when value < 0 => '↓ $positions',
        0 => '↔ $positions',
        _ => '– $positions',
      };
      _text(
        canvas,
        '${change.rankingName} · ${change.playerName} · $elo · $movement',
        Offset(padding + 24, y + 66 + index * 58),
        maxWidth: contentWidth - 48,
        fontSize: 18,
        color: colorScheme.onSurface,
      );
    }
    y += 92 + data.rankingChanges.length * 58 + sectionGap;

    if (leagueMoves.isNotEmpty) {
      _section(
        canvas,
        padding,
        y,
        contentWidth,
        92 + leagueMoves.length * 58,
        colorScheme,
      );
      _sectionTitle(
        canvas,
        'Liga-Auf- und Abstiege',
        padding + 24,
        y + 20,
        colorScheme,
      );
      for (var index = 0; index < leagueMoves.length; index++) {
        final change = leagueMoves[index];
        final promoted = change.isPromotion;
        _text(
          canvas,
          '${promoted ? '↑' : '↓'} ${change.rankingName} · '
          '${change.playerName} · ${change.tierBefore.name} → ${change.tierAfter.name}',
          Offset(padding + 24, y + 66 + index * 58),
          maxWidth: contentWidth - 48,
          fontSize: 18,
          color: colorScheme.onSurface,
        );
      }
      y += 92 + leagueMoves.length * 58 + sectionGap;
    }

    _section(
      canvas,
      padding,
      y,
      contentWidth,
      92 + data.bestPerformances.length * 54,
      colorScheme,
    );
    _sectionTitle(
      canvas,
      'Benannte Bestleistungen',
      padding + 24,
      y + 20,
      colorScheme,
    );
    if (data.bestPerformances.isEmpty) {
      _text(
        canvas,
        'Keine Bestleistungen erfasst',
        Offset(padding + 24, y + 66),
        maxWidth: contentWidth - 48,
        fontSize: 18,
        color: colorScheme.onSurfaceVariant,
      );
    } else {
      for (var index = 0; index < data.bestPerformances.length; index++) {
        final performance = data.bestPerformances[index];
        _text(
          canvas,
          '${performance.playerName} · ${_performanceLabel(performance.type)}'
          '${performance.value == null ? '' : ' · ${performance.value}'}',
          Offset(padding + 24, y + 66 + index * 54),
          maxWidth: contentWidth - 48,
          fontSize: 18,
          color: colorScheme.onSurface,
        );
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.ceil());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  void _section(
    Canvas canvas,
    double x,
    double y,
    double width,
    double height,
    ColorScheme colors,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, width, height),
        const Radius.circular(18),
      ),
      Paint()..color = colors.surfaceContainerHigh,
    );
  }

  void _sectionTitle(
    Canvas canvas,
    String text,
    double x,
    double y,
    ColorScheme colors,
  ) => _text(
    canvas,
    text,
    Offset(x, y),
    maxWidth: 900,
    fontSize: 26,
    color: colors.primary,
    bold: true,
  );

  String _performanceLabel(BestPerformanceType type) => switch (type) {
    BestPerformanceType.score170 => '170+ Aufnahme',
    BestPerformanceType.score180 => '180er',
    BestPerformanceType.highFinish => 'High Finish',
    BestPerformanceType.shortLeg => 'Shortleg',
  };

  void _text(
    Canvas canvas,
    String value,
    Offset offset, {
    required double maxWidth,
    required double fontSize,
    required Color color,
    bool bold = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }
}
