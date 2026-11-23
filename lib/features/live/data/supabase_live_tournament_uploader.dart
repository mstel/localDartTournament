import 'dart:convert';
import 'dart:typed_data';

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
    await _requiredClient.storage
        .from(LiveTournamentConfig.bucket)
        .uploadBinary(
          path,
          Uint8List.fromList(utf8.encode(html)),
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'text/html; charset=utf-8',
          ),
        );
  }

  @override
  Future<void> deleteJson(String path) async {
    await _requiredClient.storage
        .from(LiveTournamentConfig.bucket)
        .remove([path]);
  }
}
