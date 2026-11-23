import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

import 'package:dart_tournament_manager/features/live/application/live_tournament_config.dart';

/// Generates the printable QR code for the stable spectator URL.
void main() {
  const url = LiveTournamentConfig.viewerUrl;
  const modulesPerPixel = 12;
  const quietZone = 4;

  final code = QrCode.fromData(
    data: url,
    errorCorrectLevel: QrErrorCorrectLevel.H,
  );
  final image = QrImage(code);
  final moduleCount = image.moduleCount;
  final side = (moduleCount + quietZone * 2) * modulesPerPixel;

  final png = img.Image(width: side, height: side);
  png.clear(img.ColorUint8.rgb(255, 255, 255));
  for (var row = 0; row < moduleCount; row++) {
    for (var column = 0; column < moduleCount; column++) {
      if (!image.isDark(row, column)) continue;
      final startX = (column + quietZone) * modulesPerPixel;
      final startY = (row + quietZone) * modulesPerPixel;
      for (var y = 0; y < modulesPerPixel; y++) {
        for (var x = 0; x < modulesPerPixel; x++) {
          png.setPixelRgb(startX + x, startY + y, 0, 0, 0);
        }
      }
    }
  }

  final output = File('docs/live_tournament_qr.png');
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(img.encodePng(png));
  stdout.writeln('QR: ${output.path} ($side x $side px)');
  stdout.writeln('URL: $url');
}
