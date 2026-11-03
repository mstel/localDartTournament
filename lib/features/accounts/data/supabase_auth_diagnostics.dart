import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../../../shared/persistence/app_data_directory.dart';
import 'supabase_account_config.dart';

class SupabaseAuthDiagnostics {
  SupabaseAuthDiagnostics({
    Directory? directory,
    Future<PackageInfo> Function()? packageInfoLoader,
  }) : _directory = directory,
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform;

  static const _maxLogBytes = 2 * 1024 * 1024;
  final Directory? _directory;
  final Future<PackageInfo> Function() _packageInfoLoader;

  Future<File> get logFile async {
    final directory =
        _directory ??
        Directory(
          p.join(
            (await appDataDirectory(includeSupabaseAccount: false)).path,
            'diagnostics',
          ),
        );
    return File(p.join(directory.path, 'supabase-auth.log'));
  }

  Future<void> recordSignInStarted() async {
    await _append('sign_in_started', const {});
  }

  Future<void> recordSignInSucceeded(Duration duration) async {
    await _append('sign_in_succeeded', {'durationMs': duration.inMilliseconds});
  }

  Future<void> recordSignInFailed(
    Object error, {
    required Duration duration,
    required StackTrace stackTrace,
    bool probeConnectivity = true,
  }) async {
    await _append('sign_in_failed', {
      'durationMs': duration.inMilliseconds,
      'errorType': error.runtimeType.toString(),
      ..._safeErrorDetails(error),
      'stackTrace': _sanitize(stackTrace.toString()),
    });
    if (probeConnectivity) await _probeConnectivity();
  }

  Future<void> _probeConnectivity() async {
    final host = Uri.parse(SupabaseAccountConfig.url).host;
    try {
      final addresses = await InternetAddress.lookup(
        host,
      ).timeout(const Duration(seconds: 8));
      await _append('dns_probe_succeeded', {
        'host': host,
        'addressCount': addresses.length,
        'addresses': addresses.map((address) => address.address).toList(),
      });
    } on Object catch (error) {
      await _append('dns_probe_failed', {
        'host': host,
        'errorType': error.runtimeType.toString(),
        ..._safeErrorDetails(error),
      });
      return;
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.https(host, '/auth/v1/settings');
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      final key = SupabaseAccountConfig.anonKey;
      if (key.isNotEmpty) request.headers.set('apikey', key);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      await response.drain<void>();
      await _append('https_probe_completed', {
        'host': host,
        'statusCode': response.statusCode,
      });
    } on Object catch (error) {
      await _append('https_probe_failed', {
        'host': host,
        'errorType': error.runtimeType.toString(),
        ..._safeErrorDetails(error),
      });
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _append(String event, Map<String, Object?> details) async {
    final file = await logFile;
    await file.parent.create(recursive: true);
    if (await file.exists() && await file.length() >= _maxLogBytes) {
      final previous = File('${file.path}.1');
      if (await previous.exists()) await previous.delete();
      await file.rename(previous.path);
    }

    final packageInfo = await _packageInfoLoader();
    final record = <String, Object?>{
      'timestampUtc': DateTime.now().toUtc().toIso8601String(),
      'event': event,
      'appVersion': packageInfo.version,
      'appBuild': packageInfo.buildNumber,
      'platform': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'dartVersion': Platform.version,
      'projectHost': Uri.tryParse(SupabaseAccountConfig.url)?.host,
      ...details,
    };
    await file.writeAsString(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Map<String, Object?> _safeErrorDetails(Object error) {
    if (error is HttpException) {
      return {'message': _sanitize(error.message)};
    }
    if (error is SocketException) {
      return {
        'message': _sanitize(error.message),
        if (error.osError != null) 'osErrorCode': error.osError!.errorCode,
      };
    }
    if (error is HandshakeException) {
      return {'message': _sanitize(error.message)};
    }
    if (error is TlsException) {
      return {'message': _sanitize(error.message)};
    }
    return {'message': _sanitize(error.toString())};
  }

  String _sanitize(String value) {
    var safe = value;
    final key = SupabaseAccountConfig.anonKey;
    if (key.isNotEmpty) safe = safe.replaceAll(key, '[REDACTED_API_KEY]');
    safe = safe.replaceAll(
      RegExp(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b'),
      '[REDACTED_TOKEN]',
    );
    safe = safe.replaceAll(
      RegExp(r'\b(password|passwort)\s*[:=]?\s*[^;\s,]+', caseSensitive: false),
      '[REDACTED_CREDENTIAL]',
    );
    safe = safe.replaceAll(
      RegExp(
        r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
        caseSensitive: false,
      ),
      '[REDACTED_EMAIL]',
    );
    return safe;
  }
}
