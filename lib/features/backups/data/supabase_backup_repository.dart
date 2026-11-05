import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'backup_service.dart';
import '../../website/application/website_read_model_service.dart';

class SupabaseBackupRepository {
  SupabaseBackupRepository({SupabaseClient? client}) : _injectedClient = client;

  static const bucket = 'dart-app-backups';
  static const fileName = 'latest.dartbackup';
  static const _bucketAllowedContentType = 'application/octet-stream';
  final SupabaseClient? _injectedClient;
  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  String get _objectPath {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Bitte zuerst als Betreiber anmelden.');
    return '${user.id}/$fileName';
  }

  String get _websiteReadModelPath {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Bitte zuerst als Betreiber anmelden.');
    return '${user.id}/${WebsiteReadModelService.objectName}';
  }

  String get _websiteTournamentIndexPath {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Bitte zuerst als Betreiber anmelden.');
    return '${user.id}/${WebsiteReadModelService.tournamentIndexObjectName}';
  }

  String get _websiteUserId {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Bitte zuerst als Betreiber anmelden.');
    return user.id;
  }

  String get _websiteResourceManifestPath =>
      '$_websiteUserId/${WebsiteReadModelService.resourceManifestObjectName}';

  Future<bool> hasBackup() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Bitte zuerst als Betreiber anmelden.');
    final files = await _client.storage.from(bucket).list(path: user.id);
    return files.any((file) => file.name == fileName);
  }

  Future<DateTime> upload(BackupService backups) async {
    final bytes = await backups.exportBytes();
    return uploadBytes(bytes, backups: backups);
  }

  Future<DateTime> uploadBytes(
    Uint8List bytes, {
    required BackupService backups,
  }) async {
    final preview = await backups.inspect(bytes);
    await _client.storage
        .from(bucket)
        .uploadBinary(
          _objectPath,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'application/octet-stream',
          ),
        );
    return preview.createdAt;
  }

  Future<bool> hasWebsiteReadModel() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Bitte zuerst als Betreiber anmelden.');
    final files = await _client.storage.from(bucket).list(path: user.id);
    return files.any((file) => file.name == WebsiteReadModelService.objectName);
  }

  Future<bool> hasWebsiteTournamentIndex() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Bitte zuerst als Betreiber anmelden.');
    final files = await _client.storage.from(bucket).list(path: user.id);
    return files.any(
      (file) => file.name == WebsiteReadModelService.tournamentIndexObjectName,
    );
  }

  Future<bool> hasWebsiteResources() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Bitte zuerst als Betreiber anmelden.');
    final files = await _client.storage.from(bucket).list(path: user.id);
    return files.any(
      (file) => file.name == WebsiteReadModelService.resourceManifestObjectName,
    );
  }

  Future<void> uploadWebsiteReadModel(
    Map<String, dynamic> readModel, {
    required Map<String, Map<String, dynamic>> version2Resources,
  }) async {
    // The private backup bucket only permits this MIME type; the read model
    // function decodes the JSON payload independently of the object metadata.
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(readModel)));
    await _client.storage
        .from(bucket)
        .uploadBinary(
          _websiteReadModelPath,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'application/octet-stream',
          ),
        );
    final tournamentIndex = WebsiteReadModelService.createTournamentIndex(
      readModel,
    );
    final indexBytes = Uint8List.fromList(
      utf8.encode(jsonEncode(tournamentIndex)),
    );
    await _client.storage
        .from(bucket)
        .uploadBinary(
          _websiteTournamentIndexPath,
          indexBytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'application/octet-stream',
          ),
        );
    for (final entry in version2Resources.entries) {
      final page = entry.key.startsWith('tournaments:')
          ? int.parse(entry.key.substring('tournaments:'.length))
          : null;
      final resource = page == null ? entry.key : 'tournaments';
      final objectName = WebsiteReadModelService.version2ResourceObjectName(
        resource,
        page: page,
      );
      final resourceBytes = Uint8List.fromList(
        utf8.encode(jsonEncode(entry.value)),
      );
      await _client.storage
          .from(bucket)
          .uploadBinary(
            '$_websiteUserId/$objectName',
            resourceBytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: _bucketAllowedContentType,
            ),
          );
    }
    final publishedTournamentPages = version2Resources.keys
        .where((key) => key.startsWith('tournaments:'))
        .map(
          (key) => WebsiteReadModelService.version2ResourceObjectName(
            'tournaments',
            page: int.parse(key.substring('tournaments:'.length)),
          ),
        )
        .toSet();
    final existingFiles = await _client.storage
        .from(bucket)
        .list(
          path: _websiteUserId,
          searchOptions: const SearchOptions(limit: 1000),
        );
    final staleTournamentPages = existingFiles
        .map((file) => file.name)
        .where(
          (name) =>
              RegExp(
                r'^website-v2-tournaments-page-\d+\.json$',
              ).hasMatch(name) &&
              !publishedTournamentPages.contains(name),
        )
        .map((name) => '$_websiteUserId/$name')
        .toList();
    if (staleTournamentPages.isNotEmpty) {
      await _client.storage.from(bucket).remove(staleTournamentPages);
    }
    final manifest = {
      'schemaVersion': WebsiteReadModelService.resourceSchemaVersion,
      'generatedAt': readModel['generatedAt'],
      'resources': [
        for (final entry in version2Resources.entries)
          WebsiteReadModelService.version2ResourceObjectName(
            entry.key.startsWith('tournaments:') ? 'tournaments' : entry.key,
            page: entry.key.startsWith('tournaments:')
                ? int.parse(entry.key.substring('tournaments:'.length))
                : null,
          ),
      ],
    };
    final manifestBytes = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
    await _client.storage
        .from(bucket)
        .uploadBinary(
          _websiteResourceManifestPath,
          manifestBytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: _bucketAllowedContentType,
          ),
        );
  }

  Future<BackupPreview> download(BackupService backups) async {
    final Uint8List bytes = await _client.storage
        .from(bucket)
        .download(_objectPath);
    return backups.inspect(bytes);
  }

  Future<File> restore(BackupService backups, BackupPreview preview) =>
      backups.restore(preview);
}
