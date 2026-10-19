import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../domain/local_ranking.dart';
import 'ranking_year_review_service.dart';

enum RankingReviewImageOrientation { portrait, landscape }

/// Generates a complete, high-resolution PNG graphic of the yearly review
/// without clipping or truncating diagram bars or statistics.
class RankingYearReviewImageGenerator {
  const RankingYearReviewImageGenerator();

  Future<Uint8List> generatePng({
    required LocalRanking ranking,
    required RankingYearReview review,
    RankingReviewImageOrientation orientation =
        RankingReviewImageOrientation.portrait,
    ColorScheme? colorScheme,
  }) async {
    final width = orientation == RankingReviewImageOrientation.portrait
        ? 1080.0
        : 1920.0;
    final padding = orientation == RankingReviewImageOrientation.portrait
        ? 48.0
        : 80.0;
    final contentWidth = width - (padding * 2);
    final colors =
        colorScheme ?? ColorScheme.fromSeed(seedColor: const Color(0xFF356C8C));

    // Prepare leaderboard data
    final rows = review.players.entries.toList();
    List<MapEntry<String, int>> leadersFor(
      int Function(RankingYearPlayerStats) metric,
    ) {
      return rows
          .where((r) => metric(r.value) > 0)
          .map((r) => MapEntry(r.key, metric(r.value)))
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
    }

    final topWins = leadersFor((s) => s.tournamentWins);
    final topParts = leadersFor((s) => s.participations);
    final topLegs = leadersFor((s) => s.legsWon);
    final topBests = leadersFor((s) => s.bestPerformances);
    final top180 = leadersFor((s) => s.scores180);
    final top170 = leadersFor((s) => s.scores170);
    final topShort = leadersFor((s) => s.shortLegs);
    final topHigh = leadersFor((s) => s.highFinishes);

    final leaderboardSections = <(String, List<MapEntry<String, int>>)>[
      ('Meiste Turniersiege', topWins),
      ('Meiste Teilnahmen', topParts),
      ('Meiste gewonnene Legs', topLegs),
      ('Meiste Bestleistungen', topBests),
      if (top180.isNotEmpty) ('Meiste 180+', top180),
      if (top170.isNotEmpty) ('Meiste 170+', top170),
      if (topShort.isNotEmpty) ('Meiste Shortlegs', topShort),
      if (topHigh.isNotEmpty) ('Meiste High Finishes', topHigh),
    ];

    // Compute dynamic height
    // Header: ~140
    // Cards: ~220
    // Chart: ~500
    // Leaderboard cards: ceil(sections / 2) * ~260
    final rowsCount = (leaderboardSections.length / 2).ceil();
    final double totalHeight =
        140.0 + 220.0 + 500.0 + (rowsCount * 280.0) + 120.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, totalHeight));

    // Paint background
    final bgPaint = Paint()..color = colors.surface;
    canvas.drawRect(Rect.fromLTWH(0, 0, width, totalHeight), bgPaint);

    final cardPaint = Paint()..color = colors.surfaceContainerHigh;
    final accentPaint = Paint()..color = colors.primary;
    final trackPaint = Paint()..color = colors.surfaceContainerHighest;
    final foreground = colors.onSurface;
    final muted = colors.onSurfaceVariant;

    double currentY = padding;

    // Header Title
    final titlePainter = TextPainter(
      text: TextSpan(
        text: ranking.name,
        style: TextStyle(
          color: foreground,
          fontSize: 38,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentWidth);
    titlePainter.paint(canvas, Offset(padding, currentY));
    currentY += titlePainter.height + 6;

    // Subtitle
    final subPainter = TextPainter(
      text: TextSpan(
        text:
            'Jahresrückblick ${review.year ?? "Gesamter Zeitraum"} · Statistiken & Ranglistenübersicht',
        style: TextStyle(
          color: accentPaint.color,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentWidth);
    subPainter.paint(canvas, Offset(padding, currentY));
    currentY += subPainter.height + 28;

    // KPI Cards: 4 columns in row 1, 3 in row 2
    final kpis = [
      ('Turniere', '${review.tournaments}'),
      ('Gewonnene Legs', '${review.totalLegs}'),
      ('Bestleistungen', '${review.totalBestPerformances}'),
      ('180+ Aufnahmen', '${review.total180}'),
      ('170+ Aufnahmen', '${review.total170}'),
      ('Shortlegs', '${review.totalShortLegs}'),
      ('High Finishes', '${review.totalHighFinishes}'),
    ];

    const double cardGap = 16.0;
    const int cols = 4;
    final double cardWidth = (contentWidth - (cardGap * (cols - 1))) / cols;
    const double cardHeight = 88.0;

    for (var i = 0; i < kpis.length; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      final x = padding + (col * (cardWidth + cardGap));
      final y = currentY + (row * (cardHeight + cardGap));

      final cardRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, cardWidth, cardHeight),
        const Radius.circular(12),
      );
      canvas.drawRRect(cardRect, cardPaint);

      // Value
      final valPainter = TextPainter(
        text: TextSpan(
          text: kpis[i].$2,
          style: TextStyle(
            color: colors.primary,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: cardWidth - 24);
      valPainter.paint(canvas, Offset(x + 14, y + 12));

      // Label
      final lblPainter = TextPainter(
        text: TextSpan(
          text: kpis[i].$1,
          style: TextStyle(
            color: muted,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: cardWidth - 24);
      lblPainter.paint(canvas, Offset(x + 14, y + 50));
    }

    currentY += (2 * cardHeight) + cardGap + 36;

    // Monthly Chart Card
    final maxMonth = review.monthlyTournaments.fold<int>(
      0,
      (a, b) => a > b ? a : b,
    );
    const double chartCardHeight = 440.0;
    final chartCardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(padding, currentY, contentWidth, chartCardHeight),
      const Radius.circular(16),
    );
    canvas.drawRRect(chartCardRect, cardPaint);

    final chartTitlePainter = TextPainter(
      text: TextSpan(
        text: 'Turniere pro Monat',
        style: TextStyle(
          color: foreground,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentWidth - 40);
    chartTitlePainter.paint(canvas, Offset(padding + 24, currentY + 20));

    double barY = currentY + 65.0;
    const monthNames = [
      'Jan',
      'Feb',
      'Mär',
      'Apr',
      'Mai',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Okt',
      'Nov',
      'Dez',
    ];
    final double maxTrackWidth = contentWidth - 160.0;

    for (var m = 0; m < 12; m++) {
      final count = review.monthlyTournaments[m];
      final monthLabel = TextPainter(
        text: TextSpan(
          text: '${monthNames[m]}.',
          style: TextStyle(
            color: muted,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 50);
      monthLabel.paint(canvas, Offset(padding + 24, barY));

      // Track
      final trackLeft = padding + 80.0;
      final trackRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(trackLeft, barY + 3, maxTrackWidth, 14),
        const Radius.circular(7),
      );
      canvas.drawRRect(trackRect, trackPaint);

      // Active bar
      if (maxMonth > 0 && count > 0) {
        final fillWidth = (count / maxMonth) * maxTrackWidth;
        final fillRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            trackLeft,
            barY + 3,
            fillWidth.clamp(14.0, maxTrackWidth),
            14,
          ),
          const Radius.circular(7),
        );
        canvas.drawRRect(fillRect, accentPaint);
      }

      // Value label
      final countPainter = TextPainter(
        text: TextSpan(
          text: '$count',
          style: TextStyle(
            color: count > 0 ? foreground : muted,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 50);
      countPainter.paint(canvas, Offset(trackLeft + maxTrackWidth + 14, barY));

      barY += 28.0;
    }

    currentY += chartCardHeight + 32;

    // Leaderboards Section
    const double colGap = 20.0;
    final double colWidth = (contentWidth - colGap) / 2;

    for (var i = 0; i < leaderboardSections.length; i++) {
      final section = leaderboardSections[i];
      final col = i % 2;
      final row = i ~/ 2;
      final x = padding + (col * (colWidth + colGap));
      final y = currentY + (row * 270.0);

      final boxRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, colWidth, 250),
        const Radius.circular(14),
      );
      canvas.drawRRect(boxRect, cardPaint);

      // Section title
      final stPainter = TextPainter(
        text: TextSpan(
          text: section.$1,
          style: TextStyle(
            color: colors.primary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: colWidth - 32);
      stPainter.paint(canvas, Offset(x + 18, y + 16));

      // Items
      final items = section.$2.take(5).toList();
      double itemY = y + 50.0;
      if (items.isEmpty) {
        final emptyPainter = TextPainter(
          text: TextSpan(
            text: 'Keine Daten vorhanden',
            style: TextStyle(color: muted, fontSize: 14),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        emptyPainter.paint(canvas, Offset(x + 18, itemY + 10));
      } else {
        for (var rank = 0; rank < items.length; rank++) {
          final entry = items[rank];
          // Rank
          final rPainter = TextPainter(
            text: TextSpan(
              text: '${rank + 1}.',
              style: TextStyle(
                color: muted,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: 30);
          rPainter.paint(canvas, Offset(x + 18, itemY));

          // Name
          final nPainter = TextPainter(
            text: TextSpan(
              text: entry.key,
              style: TextStyle(
                color: foreground,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            ellipsis: '…',
          )..layout(maxWidth: colWidth - 120);
          nPainter.paint(canvas, Offset(x + 46, itemY));

          // Count
          final cPainter = TextPainter(
            text: TextSpan(
              text: '${entry.value}',
              style: TextStyle(
                color: colors.primary,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          cPainter.paint(
            canvas,
            Offset(x + colWidth - 18 - cPainter.width, itemY),
          );

          itemY += 34.0;
        }
      }
    }

    currentY += (rowsCount * 270.0) + 16;

    // Footer
    final now = DateTime.now();
    final footerPainter = TextPainter(
      text: TextSpan(
        text:
            'Dart Turnierverwaltung · Erstellt am ${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}',
        style: TextStyle(color: muted, fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentWidth);
    footerPainter.paint(canvas, Offset(padding, currentY));

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), totalHeight.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
