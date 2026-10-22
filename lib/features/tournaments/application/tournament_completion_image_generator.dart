import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/theme/tournament_display_palette.dart';
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
  }) async {
    const width = 1080.0;
    const padding = 56.0;
    const contentWidth = width - padding * 2;
    const sectionGap = 20.0;
    final leagueMoves = data.rankingChanges
        .where((change) => change.hasTierChange)
        .toList();
    final gains =
        data.rankingChanges.where((change) => change.delta > 0).toList()
          ..sort((left, right) => right.delta.compareTo(left.delta));
    final losses =
        data.rankingChanges.where((change) => change.delta < 0).toList()
          ..sort((left, right) => left.delta.compareTo(right.delta));
    final positionChanges = data.rankingChanges
        .where((change) => change.hasPositionChange)
        .toList();
    final rankingSectionRows = math.max(
      1,
      math.max(gains.length, losses.length),
    );
    final height =
        padding * 2 +
        126 +
        220 +
        sectionGap +
        92 +
        data.podium.length * 58 +
        sectionGap +
        92 +
        rankingSectionRows * 58 +
        (positionChanges.isEmpty
            ? 0
            : sectionGap + 92 + positionChanges.length * 58) +
        (leagueMoves.isEmpty ? 0 : sectionGap + 92 + leagueMoves.length * 58) +
        sectionGap +
        92 +
        data.bestPerformances.length * 54;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = TournamentDisplayPalette.background,
    );

    var y = padding;
    _text(
      canvas,
      data.tournamentName,
      Offset(padding, y),
      maxWidth: contentWidth,
      fontSize: 42,
      color: TournamentDisplayPalette.text,
      bold: true,
    );
    y += 58;
    _text(
      canvas,
      '${data.tournamentType} · Turnier abgeschlossen',
      Offset(padding, y),
      maxWidth: contentWidth,
      fontSize: 22,
      color: TournamentDisplayPalette.mutedText,
    );
    y += 68;

    final summaryHeight = 220.0;
    _section(canvas, padding, y, contentWidth, summaryHeight);
    _sectionTitle(canvas, 'Turnierübersicht', padding + 24, y + 20);
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
        color: TournamentDisplayPalette.text,
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
        color: TournamentDisplayPalette.mutedText,
      );
    }
    y += summaryHeight + sectionGap;

    _section(canvas, padding, y, contentWidth, 92 + data.podium.length * 58);
    _sectionTitle(canvas, 'Podium', padding + 24, y + 20);
    for (var index = 0; index < data.podium.length; index++) {
      final entry = data.podium[index];
      _text(
        canvas,
        '${entry.place}. ${entry.playerName} · ${entry.wins} Siege · '
        '${entry.losses} Niederlagen · ${entry.legsFor}:${entry.legsAgainst} Legs',
        Offset(padding + 24, y + 66.0 + index * 58.0),
        maxWidth: contentWidth - 48,
        fontSize: 19,
        color: TournamentDisplayPalette.text,
      );
    }
    y += 92 + data.podium.length * 58 + sectionGap;

    final rankingSectionHeight = 92.0 + rankingSectionRows * 58.0;
    _section(canvas, padding, y, contentWidth, rankingSectionHeight);
    _sectionTitle(canvas, 'Änderungen der Rangliste', padding + 24, y + 20);
    const columnGap = 24.0;
    final columnWidth = (contentWidth - 48 - columnGap) / 2;
    final leftX = padding + 24;
    final rightX = leftX + columnWidth + columnGap;
    _text(
      canvas,
      'Größter Punktezuwachs',
      Offset(leftX, y + 62),
      maxWidth: columnWidth,
      fontSize: 19,
      color: TournamentDisplayPalette.accent,
      bold: true,
    );
    _text(
      canvas,
      'Größter Punkteverlust',
      Offset(rightX, y + 62),
      maxWidth: columnWidth,
      fontSize: 19,
      color: TournamentDisplayPalette.accent,
      bold: true,
    );
    for (var index = 0; index < rankingSectionRows; index++) {
      final gain = index < gains.length ? gains[index] : null;
      final loss = index < losses.length ? losses[index] : null;
      _text(
        canvas,
        gain == null
            ? (index == 0 && gains.isEmpty ? 'Keine Punktegewinne' : '')
            : '${gain.rankingName} · ${gain.playerName} · +${gain.delta} Elo '
                  '(${gain.ratingBefore} → ${gain.ratingAfter})',
        Offset(leftX, y + 94.0 + index * 58.0),
        maxWidth: columnWidth,
        fontSize: 17,
        color: gain == null
            ? TournamentDisplayPalette.mutedText
            : TournamentDisplayPalette.text,
      );
      _text(
        canvas,
        loss == null
            ? (index == 0 && losses.isEmpty ? 'Keine Punkteverluste' : '')
            : '${loss.rankingName} · ${loss.playerName} · ${loss.delta} Elo '
                  '(${loss.ratingBefore} → ${loss.ratingAfter})',
        Offset(rightX, y + 94.0 + index * 58.0),
        maxWidth: columnWidth,
        fontSize: 17,
        color: loss == null
            ? TournamentDisplayPalette.mutedText
            : TournamentDisplayPalette.text,
      );
    }
    y += rankingSectionHeight + sectionGap;

    if (positionChanges.isNotEmpty) {
      _section(
        canvas,
        padding,
        y,
        contentWidth,
        92 + positionChanges.length * 58,
      );
      _sectionTitle(canvas, 'Ranglistenplätze', padding + 24, y + 20);
      for (var index = 0; index < positionChanges.length; index++) {
        final change = positionChanges[index];
        final movedUp = change.positionChange! > 0;
        _text(
          canvas,
          '${movedUp ? '↑' : '↓'} ${change.rankingName} · '
          '${change.playerName} · Platz ${change.rankingPositionBefore} '
          '→ ${change.rankingPositionAfter}',
          Offset(padding + 24, y + 66.0 + index * 58.0),
          maxWidth: contentWidth - 48,
          fontSize: 18,
          color: TournamentDisplayPalette.text,
        );
      }
      y += 92 + positionChanges.length * 58 + sectionGap;
    }

    if (leagueMoves.isNotEmpty) {
      _section(canvas, padding, y, contentWidth, 92 + leagueMoves.length * 58);
      _sectionTitle(canvas, 'Liga-Auf- und Abstiege', padding + 24, y + 20);
      for (var index = 0; index < leagueMoves.length; index++) {
        final change = leagueMoves[index];
        final promoted = change.isPromotion;
        _text(
          canvas,
          '${promoted ? '↑' : '↓'} ${change.rankingName} · '
          '${change.playerName} · ${change.tierBefore.name} → ${change.tierAfter.name}',
          Offset(padding + 24, y + 66.0 + index * 58.0),
          maxWidth: contentWidth - 48,
          fontSize: 18,
          color: TournamentDisplayPalette.text,
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
    );
    _sectionTitle(canvas, 'Benannte Bestleistungen', padding + 24, y + 20);
    if (data.bestPerformances.isEmpty) {
      _text(
        canvas,
        'Keine Bestleistungen erfasst',
        Offset(padding + 24, y + 66),
        maxWidth: contentWidth - 48,
        fontSize: 18,
        color: TournamentDisplayPalette.mutedText,
      );
    } else {
      for (var index = 0; index < data.bestPerformances.length; index++) {
        final performance = data.bestPerformances[index];
        _text(
          canvas,
          '${performance.playerName} · ${_performanceLabel(performance.type)}'
          '${performance.value == null ? '' : ' · ${performance.value}'}',
          Offset(padding + 24, y + 66.0 + index * 54.0),
          maxWidth: contentWidth - 48,
          fontSize: 18,
          color: TournamentDisplayPalette.text,
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
  ) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, width, height),
      const Radius.circular(18),
    );
    canvas
      ..drawRRect(rect, Paint()..color = TournamentDisplayPalette.card)
      ..drawRRect(
        rect,
        Paint()
          ..color = TournamentDisplayPalette.border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
  }

  void _sectionTitle(Canvas canvas, String text, double x, double y) => _text(
    canvas,
    text,
    Offset(x, y),
    maxWidth: 900,
    fontSize: 26,
    color: TournamentDisplayPalette.accent,
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
