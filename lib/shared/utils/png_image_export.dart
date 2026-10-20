import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> exportPngImage(
  BuildContext context, {
  required Uint8List bytes,
  required String fileName,
  required String successMessage,
}) async {
  try {
    if (kIsWeb) {
      final uri = Uri.dataFromBytes(bytes, mimeType: 'image/png');
      if (!await launchUrl(uri)) {
        throw StateError('Der Grafikexport konnte nicht geöffnet werden.');
      }
    } else if (Platform.isAndroid) {
      try {
        final saved = await const MethodChannel('dartturnier/backups')
            .invokeMethod<bool>('export', {
              'bytes': bytes,
              'fileName': fileName,
              'mimeType': 'image/png',
            });
        if (saved == false) return;
      } on MissingPluginException {
        await _openTemporaryPng(bytes, fileName);
      }
    } else {
      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: [
          const XTypeGroup(label: 'PNG-Grafik', extensions: ['png']),
        ],
      );
      if (location == null) return;
      await File(location.path).writeAsBytes(bytes, flush: true);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Grafikexport fehlgeschlagen: $error')),
      );
    }
  }
}

Future<void> _openTemporaryPng(Uint8List bytes, String fileName) async {
  final temporaryDirectory = await getTemporaryDirectory();
  final file = File('${temporaryDirectory.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  if (!await launchUrl(Uri.file(file.path))) {
    throw StateError('Die exportierte Grafik konnte nicht geöffnet werden.');
  }
}
