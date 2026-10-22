import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import '../domain/android_release.dart';
import '../domain/update_platform.dart';

class DesktopBundle {
  static const maxExpandedBytes = 2 * 1024 * 1024 * 1024;

  static String safePath(String name) {
    final normalized = name.replaceAll('\\', '/');
    final parts = normalized.split('/');
    if (normalized.startsWith('/') ||
        parts.contains('..') ||
        RegExp(r'[\x00-\x1f<>:"|?*]').hasMatch(normalized) ||
        parts.any(
          (part) =>
              part != '.' &&
              part.isNotEmpty &&
              (part.endsWith('.') ||
                  part.endsWith(' ') ||
                  RegExp(
                    r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)',
                    caseSensitive: false,
                  ).hasMatch(part)),
        )) {
      throw const FormatException('Unsicherer Pfad im Update-Paket.');
    }
    return p.posix.normalize(normalized);
  }

  static Future<void> extract(
    File source,
    Directory destination,
    AndroidRelease release,
  ) async {
    // The caller creates a new, empty directory for every attempt.
    if (await destination.exists()) {
      throw StateError('Update-Ziel existiert bereits.');
    }
    await destination.create();
    File inputFile = source;
    if (release.platform.isLinux) {
      inputFile = File('${source.path}.tar');
      final output = await inputFile.open(mode: FileMode.write);
      var total = 0;
      try {
        await for (final bytes in source.openRead().transform(gzip.decoder)) {
          total += bytes.length;
          if (total > maxExpandedBytes) {
            throw const FormatException('Update-Paket zu groß.');
          }
          await output.writeFrom(bytes);
        }
      } finally {
        await output.close();
      }
    }
    final input = InputFileStream(inputFile.path);
    try {
      final archive = release.platform == UpdatePlatform.windows
          ? ZipDecoder().decodeStream(input, verify: true)
          : TarDecoder().decodeStream(input);
      var size = 0;
      final names = <String>{};
      for (final entry in archive) {
        final name = safePath(entry.name);
        if (name == '.' && !entry.isFile) continue;
        size += entry.size;
        if (entry.isSymbolicLink ||
            name == '.' ||
            !names.add(name.toLowerCase()) ||
            size > maxExpandedBytes ||
            names.length > 50000) {
          throw const FormatException(
            'Ungültiges oder zu großes Update-Archiv.',
          );
        }
        final path = p.joinAll([destination.path, ...name.split('/')]);
        if (!entry.isFile) {
          await Directory(path).create(recursive: true);
          continue;
        }
        await File(path).parent.create(recursive: true);
        final output = OutputFileStream(path);
        try {
          entry.writeContent(output);
        } finally {
          await output.close();
        }
        if (await File(path).length() != entry.size) {
          throw const FormatException('Unvollständiges Update-Paket.');
        }
      }
      await validate(destination, release);
    } finally {
      await input.close();
      if (inputFile.path != source.path && await inputFile.exists()) {
        await inputFile.delete();
      }
    }
  }

  static Future<void> validate(
    Directory directory,
    AndroidRelease release,
  ) async {
    final manifestFile = File(
      p.join(directory.path, 'data', 'update-manifest.json'),
    );
    if (!await manifestFile.exists()) {
      throw const FormatException(
        'Dieses ältere Release-Paket unterstützt automatische Desktop-Updates noch nicht.',
      );
    }
    final manifestText = await manifestFile.readAsString();
    final manifest =
        jsonDecode(
              manifestText.startsWith('\uFEFF')
                  ? manifestText.substring(1)
                  : manifestText,
            )
            as Map;
    if (manifest['schemaVersion'] != 1 ||
        manifest['build'] != release.build ||
        manifest['version'] != release.version ||
        manifest['platform'] != release.platform.manifestPlatform ||
        manifest['architecture'] != release.platform.architecture) {
      throw const FormatException(
        'Version oder Plattform des Update-Pakets stimmt nicht.',
      );
    }
    final executable = release.platform == UpdatePlatform.windows
        ? 'dart_tournament_manager.exe'
        : 'dart_tournament_manager';
    for (final path in [
      executable,
      'data/icudtl.dat',
      release.platform == UpdatePlatform.windows
          ? 'flutter_windows.dll'
          : 'lib/libflutter_linux_gtk.so',
    ]) {
      if (!await File(p.join(directory.path, path)).exists()) {
        throw const FormatException('Unvollständiges Desktop-Paket.');
      }
    }
  }
}
