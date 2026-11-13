import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'backup_service.dart';
import 'incremental_workspace_archive.dart';
import '../../website/application/website_read_model_service.dart';

class SupabaseBackupRepository {
  SupabaseBackupRepository({SupabaseClient? client}) : _injectedClient = client;

  static const bucket = 'dart-app-backups';
  static const fileName = 'latest.dartbackup';
  static const incrementalManifestName = 'workspace-v3-manifest.json';
  static const _bucketAllowedContentType = 'application/octet-stream';
  final SupabaseClient? _injectedClient;
  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  String get _objectPath {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Bitte zuerst als Betreiber anmelden.');
    return '${user.id}/$fileName';
  }

  String get _incrementalManifestPath =>
      '$_websiteUserId/$incrementalManifestName';

  String get _incrementalObjectPrefix => '$_websiteUserId/workspace-v3/objects';

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
    return await backupUpdatedAt() != null;
  }

  Future<bool> hasIncrementalWorkspace() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Bitte zuerst als Betreiber anmelden.');
    final files = await _client.storage.from(bucket).list(path: user.id);
    return files.any((file) => file.name == incrementalManifestName);
  }

  /// Returns the server-side timestamp without downloading the backup bytes.
  Future<DateTime?> backupUpdatedAt() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Bitte zuerst als Betreiber anmelden.');
    final files = await _client.storage.from(bucket).list(path: user.id);
    for (final file in files) {
      if (file.name == incrementalManifestName) {
        return DateTime.tryParse(file.updatedAt ?? file.createdAt ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }
    }
    for (final file in files) {
      if (file.name != fileName) continue;
      return DateTime.tryParse(file.updatedAt ?? file.createdAt ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return null;
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
    // Keep the sync cursor aligned with Supabase's object timestamp. That
    // lets future checks use list metadata instead of downloading the backup.
    return await backupUpdatedAt() ?? preview.createdAt;
  }

  /// Uploads only changed logical stores and tournament records. The new
  /// manifest is committed last, so an interrupted migration leaves the
  /// previous full backup as the active cloud copy.
  Future<DateTime> uploadIncrementalWorkspace(
    Map<String, Uint8List?> storeFiles, {
    required BackupService backups,
  }) async {
    await backups.encodeStoreFiles(storeFiles);
    final archive = IncrementalWorkspaceArchive.fromStoreFiles(storeFiles);
    final previous = await _readIncrementalManifestIfPresent();
    final paths = <String, String>{};
    final changedObjectKeys = archive.changedObjectKeys(
      previous,
      objectPathPrefix: _incrementalObjectPrefix,
    );
    for (final entry in archive.objects.entries) {
      final digest = sha256.convert(entry.value).toString();
      final objectPath = '$_incrementalObjectPrefix/$digest.bin';
      paths[entry.key] = objectPath;
      if (!changedObjectKeys.contains(entry.key)) continue;
      await _client.storage
          .from(bucket)
          .uploadBinary(
            objectPath,
            entry.value,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: _bucketAllowedContentType,
            ),
          );
    }
    final manifestBytes = Uint8List.fromList(
      utf8.encode(jsonEncode(archive.toManifest(paths))),
    );
    await _client.storage
        .from(bucket)
        .uploadBinary(
          _incrementalManifestPath,
          manifestBytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: _bucketAllowedContentType,
          ),
        );
    return await backupUpdatedAt() ?? DateTime.now().toUtc();
  }

  Future<Map<String, dynamic>?> _readIncrementalManifestIfPresent() async {
    if (!await hasIncrementalWorkspace()) return null;
    final bytes = await _client.storage
        .from(bucket)
        .download(_incrementalManifestPath);
    final decoded = jsonDecode(utf8.decode(bytes));
    IncrementalWorkspaceArchive.fromManifest(decoded);
    return Map<String, dynamic>.from(decoded as Map);
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
    final existingFiles = await _client.storage
        .from(bucket)
        .list(
          path: _websiteUserId,
          searchOptions: const SearchOptions(limit: 1000),
        );
    final existingHashes = {
      for (final file in existingFiles)
        file.name: file.metadata?['sha256'] as String?,
    };
    // The private backup bucket only permits this MIME type; the read model
    // function decodes the JSON payload independently of the object metadata.
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(readModel)));
    await _uploadWebsiteObjectIfChanged(
      _websiteReadModelPath,
      bytes,
      existingHashes,
    );
    final tournamentIndex = WebsiteReadModelService.createTournamentIndex(
      readModel,
    );
    final indexBytes = Uint8List.fromList(
      utf8.encode(jsonEncode(tournamentIndex)),
    );
    await _uploadWebsiteObjectIfChanged(
      _websiteTournamentIndexPath,
      indexBytes,
      existingHashes,
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
      await _uploadWebsiteObjectIfChanged(
        '$_websiteUserId/$objectName',
        resourceBytes,
        existingHashes,
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
    await _uploadWebsiteObjectIfChanged(
      _websiteResourceManifestPath,
      manifestBytes,
      existingHashes,
    );
  }

  Future<void> _uploadWebsiteObjectIfChanged(
    String objectPath,
    Uint8List bytes,
    Map<String, String?> existingHashes,
  ) async {
    final digest = websiteContentHash(bytes);
    final objectName = objectPath.split('/').last;
    if (existingHashes[objectName] == digest) return;
    await _client.storage
        .from(bucket)
        .uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _bucketAllowedContentType,
            metadata: {'sha256': digest},
          ),
        );
  }

  @visibleForTesting
  static String websiteContentHash(List<int> bytes) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      decoded = null;
    }
    if (decoded is Map<String, dynamic>) {
      final content = Map<String, dynamic>.from(decoded)..remove('generatedAt');
      return sha256.convert(utf8.encode(jsonEncode(content))).toString();
    }
    return sha256.convert(bytes).toString();
  }

  Future<BackupPreview> download(BackupService backups) async {
    if (await hasIncrementalWorkspace()) {
      return downloadChangedObjects(
        backups,
        currentFiles: {for (final name in BackupService.names) name: null},
      );
    }
    final Uint8List bytes = await _client.storage
        .from(bucket)
        .download(_objectPath);
    return backups.inspect(bytes);
  }

  /// Reconciles a clean local baseline with the current manifest. Objects with
  /// matching local SHA-256 hashes stay on device; only changed/new objects
  /// are fetched, while deletions follow the remote manifest order.
  Future<BackupPreview> downloadChangedObjects(
    BackupService backups, {
    required Map<String, Uint8List?> currentFiles,
  }) async {
    if (!await hasIncrementalWorkspace()) return download(backups);
    final manifest = await _readIncrementalManifestIfPresent();
    if (manifest == null) {
      throw const FormatException('Delta-Backup-Manifest fehlt.');
    }
    final archive = IncrementalWorkspaceArchive.fromManifest(manifest);
    final local = IncrementalWorkspaceArchive.fromStoreFiles(currentFiles);
    final entries = manifest['objects'] as Map;
    for (final entry in entries.entries) {
      final objectKey = entry.key as String;
      final metadata = entry.value as Map;
      final digest = metadata['sha256'] as String;
      final objectPath = metadata['path'] as String;
      final expectedPath = '$_incrementalObjectPrefix/$digest.bin';
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
          objectPath != expectedPath ||
          objectPath.contains('..')) {
        throw const FormatException('Unsicherer Delta-Backup-Pfad.');
      }
      final localBytes = local.objects[objectKey];
      if (localBytes != null &&
          sha256.convert(localBytes).toString() == digest) {
        archive.objects[objectKey] = localBytes;
        continue;
      }
      final bytes = await _client.storage.from(bucket).download(objectPath);
      if (sha256.convert(bytes).toString() != digest) {
        throw FormatException('Prüfsumme stimmt nicht: $objectKey');
      }
      archive.objects[objectKey] = bytes;
    }
    final bytes = await backups.encodeStoreFiles(archive.toStoreFiles());
    return backups.inspect(bytes);
  }

  Future<File> restore(BackupService backups, BackupPreview preview) =>
      backups.restore(preview);
}
