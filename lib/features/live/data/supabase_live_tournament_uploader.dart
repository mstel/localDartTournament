import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../accounts/data/supabase_account_config.dart';
import '../application/live_tournament_config.dart';
import 'live_tournament_uploader.dart';

/// Writes only the dedicated live bucket. The private backup bucket is never
/// touched here.
class SupabaseLiveTournamentUploader implements LiveTournamentUploader {
  SupabaseLiveTournamentUploader({SupabaseClient? client})
    : _injectedClient = client;

  final SupabaseClient? _injectedClient;
  SupabaseClient? get _client => SupabaseAccountBootstrap.isInitialized
      ? (_injectedClient ?? Supabase.instance.client)
      : _injectedClient;

  @override
  String? get currentUserId {
    try {
      return _client?.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  SupabaseClient get _requiredClient {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase ist nicht initialisiert.');
    }
    return client;
  }

  @override
  Future<void> uploadJson(String path, List<int> bytes) async {
    await _requiredClient.storage
        .from(LiveTournamentConfig.bucket)
        .uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'application/json',
          ),
        );
  }

  @override
  Future<void> uploadViewer(String path, String html) async {
    final client = _requiredClient;
    final storage = client.storage;
    final bucket = LiveTournamentConfig.bucket;
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final encodedPath = normalizedPath
        .split('/')
        .map(Uri.encodeComponent)
        .join('/');
    final uri = Uri.parse('${storage.url}/object/$bucket/$encodedPath');

    // Supabase object metadata (especially content-type) can stick on upsert.
    // Replace the viewer object to ensure browsers receive text/html.
    try {
      await storage.from(bucket).remove([normalizedPath]);
    } catch (_) {
      // Best effort: upload below will still attempt to replace/create.
    }

    final headers = <String, String>{...storage.headers};
    final session = client.auth.currentSession;
    final hasAuthorization = headers.keys.any(
      (k) => k.toLowerCase() == 'authorization',
    );
    if (!hasAuthorization && session?.accessToken != null) {
      headers['Authorization'] = 'Bearer ${session!.accessToken}';
    }
    if (!headers.keys.any((k) => k.toLowerCase() == 'apikey')) {
      final anonKey = SupabaseAccountConfig.anonKey;
      if (anonKey.isNotEmpty) {
        headers['apikey'] = anonKey;
      }
    }
    if (!headers.keys.any((k) => k.toLowerCase() == 'authorization')) {
      throw StateError(
        'Live-Viewer Upload fehlgeschlagen: fehlende Anmeldung/Authorization.',
      );
    }

    // Raw upload: sets the object Content-Type metadata directly. Multipart
    // uploads can leave stale/wrong mimetype metadata on Supabase Storage.
    headers['Content-Type'] = 'text/html; charset=utf-8';
    headers['x-upsert'] = 'true';
    headers['cache-control'] = '60';

    final response = await http.post(
      uri,
      headers: headers,
      body: utf8.encode(html),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Live-Viewer Upload fehlgeschlagen (${response.statusCode}): ${response.body}',
      );
    }
  }

  @override
  Future<void> deleteJson(String path) async {
    await _requiredClient.storage
        .from(LiveTournamentConfig.bucket)
        .remove([path]);
  }
}
