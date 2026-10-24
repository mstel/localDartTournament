import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class RandomDrawImageGenerator {
  const RandomDrawImageGenerator();

  Future<Uint8List> generate({
    required String title,
    required List<String> groupNames,
    required List<List<String>> groups,
  }) async {
    if (groupNames.length != groups.length || groups.isEmpty) {
      throw ArgumentError('Each group must have exactly one name.');
    }

    const width = 1200.0;
    const padding = 40.0;
    const gap = 24.0;
    const columnWidth = (width - padding * 2 - gap) / 2;
    final rowHeights = <double>[];
    for (var index = 0; index < groups.length; index += 2) {
      final first = _groupHeight(groups[index], columnWidth);
      final second = index + 1 < groups.length
          ? _groupHeight(groups[index + 1], columnWidth)
          : 0.0;
      rowHeights.add(math.max(first, second));
    }

    const titleHeight = 88.0;
    final height =
        padding * 2 +
        titleHeight +
        rowHeights.fold<double>(0, (sum, value) => sum + value) +
        gap * rowHeights.length;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    canvas.drawColor(const Color(0xFF10263D), BlendMode.src);
    _drawText(
      canvas,
      title,
      const Offset(padding, padding),
      width - padding * 2,
      const TextStyle(
        color: Colors.white,
        fontSize: 34,
        fontWeight: FontWeight.w700,
      ),
    );

    var top = padding + titleHeight;
    for (var row = 0; row < rowHeights.length; row++) {
      for (var column = 0; column < 2; column++) {
        final index = row * 2 + column;
        if (index >= groups.length) continue;
        final left = padding + column * (columnWidth + gap);
        _drawGroup(
          canvas,
          Rect.fromLTWH(left, top, columnWidth, rowHeights[row]),
          groupNames[index],
          groups[index],
        );
      }
      top += rowHeights[row] + gap;
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.ceil());
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('Gruppen-Grafik konnte nicht codiert werden.');
      }
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  double _groupHeight(List<String> players, double width) {
    var height = 84.0;
    for (final player in players) {
      final painter = _textPainter(
        player,
        width - 48,
        const TextStyle(color: Color(0xFF172A3B), fontSize: 22),
      );
      height += math.max(42.0, painter.height + 16);
    }
    return math.max(height, 132);
  }

  void _drawGroup(Canvas canvas, Rect rect, String name, List<String> players) {
    final paint = Paint()..color = const Color(0xFFF4F7FA);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(18)),
      paint,
    );
    _drawText(
      canvas,
      name,
      Offset(rect.left + 24, rect.top + 20),
      rect.width - 48,
      const TextStyle(
        color: Color(0xFF10263D),
        fontSize: 26,
        fontWeight: FontWeight.w700,
      ),
    );
    var top = rect.top + 68;
    for (final player in players) {
      final style = const TextStyle(color: Color(0xFF172A3B), fontSize: 22);
      final painter = _textPainter(player, rect.width - 48, style);
      final rowHeight = math.max(42.0, painter.height + 16);
      final playerRect = Rect.fromLTWH(
        rect.left + 18,
        top,
        rect.width - 36,
        rowHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(playerRect, const Radius.circular(8)),
        Paint()..color = const Color(0xFFE6EDF3),
      );
      painter.paint(canvas, Offset(playerRect.left + 12, playerRect.top + 8));
      top += rowHeight;
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    double maxWidth,
    TextStyle style,
  ) => _textPainter(text, maxWidth, style).paint(canvas, offset);

  TextPainter _textPainter(String text, double maxWidth, TextStyle style) =>
      TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);
}
