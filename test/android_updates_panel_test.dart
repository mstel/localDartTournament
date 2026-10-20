import 'dart:io';

import 'package:dart_tournament_manager/features/updates/application/app_update_service.dart';
import 'package:dart_tournament_manager/features/updates/data/update_channel_preferences.dart';
import 'package:dart_tournament_manager/features/updates/domain/android_release.dart';
import 'package:dart_tournament_manager/features/updates/presentation/android_updates_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FailingUpdateService extends AppUpdateService {
  @override
  bool get supported => true;

  @override
  Future<({String version, int build})> installed() async =>
      (version: '1.0.0', build: 1);

  @override
  Future<AndroidRelease?> check(
    int installedBuild, {
    bool includePrereleases = false,
  }) async {
    throw const HttpException('Verbindung fehlgeschlagen');
  }

  @override
  Future<File> download(
    AndroidRelease release,
    void Function(double) progress,
  ) async => throw UnimplementedError();

  @override
  Future<bool> install() async => throw UnimplementedError();
}

class _MemoryUpdatePreferences extends UpdateChannelPreferences {
  @override
  Future<bool> load() async => false;
}

void main() {
  testWidgets('update-check HTTP errors remain visible and retryable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AndroidUpdatesPanel(
            service: _FailingUpdateService(),
            preferences: _MemoryUpdatePreferences(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Nach Updates suchen'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Nach Updates suchen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Update fehlgeschlagen:'), findsOneWidget);
    expect(find.textContaining('Verbindung fehlgeschlagen'), findsOneWidget);
    expect(find.text('Nach Updates suchen'), findsOneWidget);
  });
}
