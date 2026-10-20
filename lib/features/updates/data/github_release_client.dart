import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../domain/android_release.dart';
import '../domain/update_platform.dart';

class GitHubReleaseClient {
  GitHubReleaseClient({Uri? releasesUri})
    : _releasesUri =
          releasesUri ??
          Uri.https(
            'api.github.com',
            '/repos/${AndroidRelease.repository}/releases',
            {'per_page': '100'},
          );

  final Uri _releasesUri;

  Future<AndroidRelease?> check(
    int installedBuild, {
    bool includePrereleases = false,
    UpdatePlatform platform = UpdatePlatform.android,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _checkOnce(
          installedBuild,
          includePrereleases: includePrereleases,
          platform: platform,
        );
      } on SocketException catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
      } on HttpException catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
      } on TimeoutException catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
      }
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  Future<AndroidRelease?> _checkOnce(
    int installedBuild, {
    required bool includePrereleases,
    required UpdatePlatform platform,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(_releasesUri);
      request.persistentConnection = false;
      request.headers.set('User-Agent', 'DartTournamentPro');
      request.headers.set('Accept', 'application/vnd.github+json');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != 200) {
        final guidance =
            response.statusCode == 403 || response.statusCode == 429
            ? 'GitHub begrenzt die Update-Anfragen. Bitte später erneut prüfen.'
            : 'GitHub antwortet mit ${response.statusCode}. Bitte später erneut prüfen.';
        throw UpdateCheckException(guidance);
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        bytes.addAll(chunk);
        if (bytes.length > 4 * 1024 * 1024) {
          throw const FormatException('Release-Antwort zu groß.');
        }
      }
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! List) {
        throw const FormatException('Ungültige Release-Antwort.');
      }
      return AndroidRelease.newest(
        json,
        installedBuild,
        includePrereleases: includePrereleases,
        platform: platform,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<File> download(
    AndroidRelease release,
    void Function(double) progress,
    File destination,
  ) async {
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.part');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      var uri = release.url;
      HttpClientResponse? response;
      for (var redirects = 0; redirects <= 5; redirects++) {
        if (uri.scheme != 'https' ||
            ![
              'github.com',
              'release-assets.githubusercontent.com',
              'objects.githubusercontent.com',
            ].contains(uri.host)) {
          throw const FormatException('Nicht erlaubter Download-Server.');
        }
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        response = await request.close().timeout(const Duration(seconds: 30));
        if (!response.isRedirect) break;
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) {
          throw const FormatException('Ungültige Weiterleitung.');
        }
        uri = uri.resolve(location);
        await response.drain<void>().timeout(const Duration(seconds: 15));
      }
      if (response?.statusCode != 200) {
        throw const HttpException('Update konnte nicht geladen werden.');
      }
      final output = await temporary.open(mode: FileMode.write);
      var count = 0;
      try {
        await for (final chunk in response!.timeout(
          const Duration(seconds: 30),
        )) {
          count += chunk.length;
          if (count > release.size) {
            throw const FormatException('Paket-Größe stimmt nicht.');
          }
          await output.writeFrom(chunk);
          progress(count / release.size);
        }
        await output.flush();
      } finally {
        await output.close();
      }
      if (count != release.size ||
          (await sha256.bind(temporary.openRead()).first).toString() !=
              release.sha256) {
        throw const FormatException(
          'Paket-Prüfsumme stimmt nicht. Installation abgebrochen.',
        );
      }
      return await temporary.rename(destination.path);
    } finally {
      client.close(force: true);
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}
