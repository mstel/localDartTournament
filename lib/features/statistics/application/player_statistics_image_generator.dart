import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/best_performance.dart';
import '../domain/local_statistics.dart';

enum PlayerStatisticsImageOrientation { portrait, landscape }

class PlayerStatisticsImageGenerator {
  const PlayerStatisticsImageGenerator();

  Future<Uint8List> generatePng({
    required String playerName,
    required LocalPlayerStatistics statistics,
    required ColorScheme colorScheme,
    PlayerStatisticsImageOrientation orientation =
        PlayerStatisticsImageOrientation.portrait,
  }) async {
    final landscape = orientation == PlayerStatisticsImageOrientation.landscape;
    final width = landscape ? 1920.0 : 1080.0;
    final height = landscape ? 1080.0 : 1600.0;
    const padding = 64.0;
    final contentWidth = width - padding * 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = colorScheme.surface,
    );

    final cardPaint = Paint()..color = colorScheme.surfaceContainerHigh;
    _text(
      canvas,
      playerName,
      Offset(padding, padding),
      maxWidth: contentWidth,
      fontSize: 44,
      color: colorScheme.onSurface,
      bold: true,
    );
    _text(
      canvas,
      'Spielerprofil · Turniere, Spiele und Bestleistungen',
      Offset(padding, padding + 64),
      maxWidth: contentWidth,
      fontSize: 22,
      color: colorScheme.onSurfaceVariant,
    );

    final metrics = <(String, String)>[
      ('Turniere', '${statistics.tournaments}'),
      ('Turniersiege', '${statistics.tournamentWins}'),
      (
        'Turniersiegchance %',
        '${statistics.tournamentWinRate.toStringAsFixed(1)} %',
      ),
      ('Spiele', '${statistics.matches}'),
      ('Siege', '${statistics.wins}'),
      ('Niederlagen', '${statistics.losses}'),
      ('Unentschieden', '${statistics.draws}'),
      ('Siegquote', '${statistics.matchWinRate.toStringAsFixed(1)} %'),
      ('Legs gewonnen', '${statistics.legsWon}'),
      ('Legs verloren', '${statistics.legsLost}'),
      ('Leg-Siegquote', '${statistics.legWinRate.toStringAsFixed(1)} %'),
    ];
    final columns = landscape ? 3 : 2;
    const gap = 16.0;
    final cardWidth = (contentWidth - gap * (columns - 1)) / columns;
    const cardHeight = 104.0;
    var y = padding + 128;
    for (var index = 0; index < metrics.length; index++) {
      final x = padding + (index % columns) * (cardWidth + gap);
      final row = index ~/ columns;
      if (row > 0 && index % columns == 0) {
        y = padding + 128 + row * (cardHeight + gap);
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, cardWidth, cardHeight),
          const Radius.circular(16),
        ),
        cardPaint,
      );
      _text(
        canvas,
        metrics[index].$2,
        Offset(x + 20, y + 18),
        maxWidth: cardWidth - 40,
        fontSize: 30,
        color: colorScheme.primary,
        bold: true,
      );
      _text(
        canvas,
        metrics[index].$1,
        Offset(x + 20, y + 62),
        maxWidth: cardWidth - 40,
        fontSize: 17,
        color: colorScheme.onSurfaceVariant,
      );
    }

    final statsEnd =
        padding + 128 + (metrics.length / columns).ceil() * (cardHeight + gap);
    final performanceTop = statsEnd + 28;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          padding,
          performanceTop,
          contentWidth,
          height - performanceTop - padding,
        ),
        const Radius.circular(16),
      ),
      cardPaint,
    );
    _text(
      canvas,
      'Bestleistungen · ${statistics.bestPerformances.length}',
      Offset(padding + 24, performanceTop + 20),
      maxWidth: contentWidth - 48,
      fontSize: 26,
      color: colorScheme.onSurface,
      bold: true,
    );
    final performances = statistics.bestPerformances;
    if (performances.isEmpty) {
      _text(
        canvas,
        'Noch keine Bestleistungen erfasst',
        Offset(padding + 24, performanceTop + 72),
        maxWidth: contentWidth - 48,
        fontSize: 20,
        color: colorScheme.onSurfaceVariant,
      );
    } else {
      final rowHeight = landscape ? 42.0 : 46.0;
      final maxRows = ((height - performanceTop - padding - 76) / rowHeight)
          .floor();
      for (
        var index = 0;
        index < performances.length && index < maxRows;
        index++
      ) {
        final performance = performances[index];
        final typeLabel = _performanceLabel(performance.type);
        _text(
          canvas,
          '${performance.value ?? typeLabel} · $typeLabel',
          Offset(padding + 24, performanceTop + 72 + index * rowHeight),
          maxWidth: contentWidth - 48,
          fontSize: 18,
          color: colorScheme.onSurface,
        );
      }
      if (performances.length > maxRows) {
        _text(
          canvas,
          '… und ${performances.length - maxRows} weitere',
          Offset(padding + 24, height - padding - 32),
          maxWidth: contentWidth - 48,
          fontSize: 16,
          color: colorScheme.onSurfaceVariant,
        );
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  String _performanceLabel(BestPerformanceType type) => switch (type) {
    BestPerformanceType.score170 => '170+ Aufnahme',
    BestPerformanceType.score180 => '180+ Aufnahme',
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
