import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../../tournaments/data/app_database.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../data/live_tournament_uploader.dart';
import 'live_tournament_config.dart';
import 'live_tournament_payload_builder.dart';

enum LivePublishStatus { published, disabled, notSignedIn }

class LivePublishResult {
  const LivePublishResult({
    required this.status,
    this.url,
    this.generatedAt,
    this.message,
  });

  final LivePublishStatus status;
  final String? url;
  final DateTime? generatedAt;
  final String? message;

  bool get isPublished => status == LivePublishStatus.published;
}

/// Publishes the slim spectator document behind a fixed channel URL.
class LiveTournamentPublisher {
  LiveTournamentPublisher({
    required LiveTournamentUploader uploader,
    LiveTournamentPayloadBuilder? builder,
    String? viewerHtml,
  }) : _uploader = uploader,
       _builder = builder ?? const LiveTournamentPayloadBuilder(),
       _viewerHtml = viewerHtml;

  final LiveTournamentUploader _uploader;
  final LiveTournamentPayloadBuilder _builder;
  final String? _viewerHtml;
  bool _viewerUploaded = false;
  bool _payloadCleared = false;
  String? _lastPayloadHash;

  Future<LivePublishResult> publish(
    CreatedTournament tournament, {
    String channel = LiveTournamentConfig.channel,
    Map<String, PlayerProfile> profiles = const {},
  }) async {
    if (!tournament.tournamentSettings.liveVisible) {
      await _deleteIfNeeded(channel);
      return const LivePublishResult(status: LivePublishStatus.disabled);
    }
    _payloadCleared = false;
    if (_uploader.currentUserId == null) {
      return const LivePublishResult(
        status: LivePublishStatus.notSignedIn,
        message: 'Für Live bitte als Betreiber anmelden.',
      );
    }

    await _ensureViewer(channel);
    final payload = _builder.build(
      tournament,
      channel: channel,
      profiles: profiles,
    );
    final bytes = utf8.encode(jsonEncode(payload.toJson()));
    final hash = sha256.convert(bytes).toString();
    if (hash != _lastPayloadHash) {
      await _uploader.uploadJson(_payloadPath(channel), bytes);
      _lastPayloadHash = hash;
    }
    return LivePublishResult(
      status: LivePublishStatus.published,
      url: LiveTournamentConfig.viewerUrl,
      generatedAt: payload.generatedAt,
    );
  }

  Future<void> unpublish({
    String channel = LiveTournamentConfig.channel,
  }) async {
    await _deleteIfNeeded(channel);
  }

  Future<void> _deleteIfNeeded(String channel) async {
    if (_payloadCleared || _uploader.currentUserId == null) return;
    await _uploader.deleteJson(_payloadPath(channel));
    _lastPayloadHash = null;
    _payloadCleared = true;
  }

  Future<void> _ensureViewer(String channel) async {
    if (_viewerUploaded) return;
    final html =
        _viewerHtml ??
        await rootBundle.loadString('assets/live/live_viewer.html');
    await _uploader.uploadViewer(_viewerPath(channel), html);
    _viewerUploaded = true;
  }

  String _viewerPath(String channel) => '$channel/index.html';
  String _payloadPath(String channel) => '$channel/latest.json';
}
