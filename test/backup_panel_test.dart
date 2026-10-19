import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/backups/data/backup_service.dart';
import 'package:dart_tournament_manager/features/backups/presentation/backup_file_dialogs.dart';
import 'package:dart_tournament_manager/features/backups/presentation/backup_panel.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/shared/persistence/storage_access.dart';

class _Dialogs extends BackupFileDialogs {
  String? target;
  XFile? source;
  int openCalls = 0;
  @override
  Future<String?> savePath() async => target;
  @override
  Future<XFile?> open() async {
    openCalls++;
    return source;
  }
}

void main() {
  testWidgets('export, cancelled import and confirmed import use real stores', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('backup_widget_'),
    ))!;
    addTearDown(() async {
      StorageAccess.restartRequired.value = false;
      await root.delete(recursive: true);
    });
    final service = BackupService(
      files: {
        for (final name in BackupService.names)
          name: File('${root.path}/data/$name'),
      },
      backupDirectory: Directory('${root.path}/data/backups'),
    );
    final storage = TournamentStorage(file: service.files['tournaments.json']);
    final dialogs = _Dialogs()..target = '${root.path}/export.dartbackup';
    await tester.runAsync(
      () => storage.saveTournament(
        CreatedTournament(
          name: 'Original',
          players: [],
          stages: [],
          runStages: [],
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackupPanel(service: service, dialogs: dialogs),
        ),
      ),
    );
    await tester.tap(find.text('Backup exportieren'));
    await tester.pump();
    expect(find.text('Exportieren'), findsOneWidget);
    expect(
      tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      ).every((tile) => tile.value == true),
      isTrue,
    );
    await tester.tap(find.text('Exportieren'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsNothing);
    final listPosition = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final savedMessage = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableText &&
          (widget.data ?? '').contains('Backup gespeichert:'),
    );
    for (var i = 0; i < 100 && savedMessage.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      listPosition.jumpTo(listPosition.maxScrollExtent);
      await tester.pump();
    }
    expect(File(dialogs.target!).existsSync(), isTrue);
    expect(savedMessage, findsOneWidget);
    Future<void> waitUntilIdle() async {
      for (
        var i = 0;
        i < 100 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
        i++
      ) {
        listPosition.jumpTo(listPosition.maxScrollExtent);
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.byType(LinearProgressIndicator), findsNothing);
    }

    await waitUntilIdle();
    dialogs.source = XFile(dialogs.target!);
    await tester.runAsync(
      () => storage.saveTournament(
        CreatedTournament(
          name: 'Später',
          players: [],
          stages: [],
          runStages: [],
        ),
      ),
    );
    final importTitle = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Backup wiederherstellen'),
    );
    Future<void> openPreview() async {
      await tester.ensureVisible(find.text('Backup wiederherstellen'));
      expect(find.text('Backup wiederherstellen').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Backup wiederherstellen'));
      for (
        var i = 0;
        i < 100 && importTitle.evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
    }

    listPosition.jumpTo(0);
    await tester.pump();
    await openPreview();
    expect(dialogs.openCalls, 1);
    expect(
      importTitle,
      findsOneWidget,
      reason:
          'Status: ${tester.widgetList<SelectableText>(find.byType(SelectableText)).map((text) => text.data).join(' | ')}; '
          'busy: ${find.byType(LinearProgressIndicator).evaluate().isNotEmpty}; '
          'open calls: ${dialogs.openCalls}',
    );
    expect(find.textContaining('1 Turniere'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    listPosition.jumpTo(listPosition.maxScrollExtent);
    await tester.pump();
    await waitUntilIdle();
    expect(
      await tester.runAsync(
        () async => (await storage.loadTournaments()).length,
      ),
      2,
    );
    await openPreview();
    await tester.ensureVisible(find.text('Wiederherstellen'));
    await tester.tap(find.text('Wiederherstellen'));
    for (
      var i = 0;
      i < 100 && !StorageAccess.restartRequired.value;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    expect(StorageAccess.restartRequired.value, isTrue);
    for (
      var i = 0;
      i < 100 && find.textContaining('Bitte App neu starten.').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      listPosition.jumpTo(listPosition.maxScrollExtent);
      await tester.pump();
    }
    expect(find.textContaining('Bitte App neu starten.'), findsOneWidget);
  });
}
