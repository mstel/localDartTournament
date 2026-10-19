import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/local_elo_calculator.dart';
import '../domain/local_ranking.dart';

class RankingStandingImageRow {
  const RankingStandingImageRow({
    required this.name,
    required this.value,
    required this.details,
  });

  final String name;
  final String value;
  final String details;
}

class RankingStandingsImageGenerator {
  const RankingStandingsImageGenerator();

  Future<Uint8List> generatePng({
    required LocalRanking ranking,
    required LocalEloSnapshot snapshot,
    required ColorScheme colorScheme,
  }) => generateRows(
    title: ranking.name,
    subtitle: 'Ranglistenstand · ${snapshot.entries.length} Spieler',
    rows: [
      for (var index = 0; index < snapshot.entries.length; index++)
        RankingStandingImageRow(
          name: '${index + 1}. ${snapshot.entries[index].name}',
          value: '${snapshot.entries[index].rating} Elo',
          details:
              '${snapshot.entries[index].matches} Matches · ${snapshot.entries[index].wins} Siege · ${snapshot.entries[index].losses} Niederlagen',
        ),
    ],
    colorScheme: colorScheme,
  );

  Future<Uint8List> generateRows({
    required String title,
    required String subtitle,
    required List<RankingStandingImageRow> rows,
    required ColorScheme colorScheme,
  }) async {
    const width = 1080.0;
    const padding = 56.0;
    const rowHeight = 82.0;
    final height = padding * 2 + 220 + rows.length * rowHeight;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = colorScheme.surface,
    );
    _paintText(
      canvas,
      title,
      Offset(padding, padding),
      maxWidth: width - padding * 2,
      fontSize: 42,
      color: colorScheme.onSurface,
      bold: true,
    );
    _paintText(
      canvas,
      subtitle,
      Offset(padding, padding + 64),
      maxWidth: width - padding * 2,
      fontSize: 22,
      color: colorScheme.onSurfaceVariant,
    );

    var y = padding + 120;
    for (var index = 0; index < rows.length; index++) {
      final player = rows[index];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(padding, y, width - padding * 2, rowHeight - 8),
          const Radius.circular(12),
        ),
        Paint()..color = colorScheme.surfaceContainerHigh,
      );
      _paintText(
        canvas,
        '${index + 1}.',
        Offset(padding + 18, y + 22),
        maxWidth: 50,
        fontSize: 24,
        color: colorScheme.primary,
        bold: true,
      );
      _paintText(
        canvas,
        player.name,
        Offset(padding + 80, y + 14),
        maxWidth: width - padding * 2 - 300,
        fontSize: 23,
        color: colorScheme.onSurface,
        bold: true,
      );
      _paintText(
        canvas,
        player.details,
        Offset(padding + 80, y + 46),
        maxWidth: width - padding * 2 - 300,
        fontSize: 16,
        color: colorScheme.onSurfaceVariant,
      );
      _paintText(
        canvas,
        player.value,
        Offset(width - padding - 180, y + 24),
        maxWidth: 160,
        fontSize: 22,
        color: colorScheme.primary,
        bold: true,
      );
      y += rowHeight;
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  void _paintText(
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
