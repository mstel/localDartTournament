import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:dart_tournament_manager/app/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dart_tournament_manager/features/updates/data/update_channel_preferences.dart';
import 'package:dart_tournament_manager/features/updates/data/android_update_service.dart';
import 'package:dart_tournament_manager/features/updates/domain/android_release.dart';
import 'package:dart_tournament_manager/features/updates/domain/update_platform.dart';
import 'package:dart_tournament_manager/features/updates/presentation/android_updates_panel.dart';

class FakeUpdater extends AndroidUpdateService {
  FakeUpdater({this.desktop = false});
  final bool desktop;
  @override
  bool get isDesktop => desktop;
  @override
  String get platformLabel => desktop ? 'Windows' : 'Android';
  final channels = <bool>[];
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
    channels.add(includePrereleases);
    return null;
  }
}

class AvailableDesktopUpdater extends FakeUpdater {
  AvailableDesktopUpdater() : super(desktop: true);
  int downloads = 0;
  int installations = 0;
  @override
  Future<AndroidRelease?> check(
    int installedBuild, {
    bool includePrereleases = false,
  }) async => AndroidRelease(
    version: '1.1.0',
    build: 2,
    url: Uri.parse('https://github.com/example'),
    sha256: 'a' * 64,
    size: 100,
    notes: 'Verbesserungen für Desktop und Mobilgeräte.',
    platform: UpdatePlatform.windows,
  );
  @override
  Future<File> download(
    AndroidRelease release,
    void Function(double) progress,
  ) async {
    downloads++;
    progress(1);
    return File('unused-test-fixture');
  }

  @override
  Future<bool> install() async {
    installations++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const previewFont = String.fromEnvironment('LAYOUT_PREVIEW_FONT');
  setUpAll(() async {
    if (previewFont.isEmpty) return;
    await (FontLoader('Roboto')..addFont(
          File(previewFont).readAsBytes().then((b) => ByteData.sublistView(b)),
        ))
        .load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('stable default and beta preference survives a new store', () async {
    expect(await UpdateChannelPreferences().load(), isFalse);
    await UpdateChannelPreferences().save(true);
    expect(await UpdateChannelPreferences().load(), isTrue);
    await UpdateChannelPreferences().save(false);
    expect(await UpdateChannelPreferences().load(), isFalse);
  });
  testWidgets('desktop update panel surfaces the persistent failure log path', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDartTournamentTheme(),
        home: Scaffold(
          body: AndroidUpdatesPanel(
            service: FakeUpdater(desktop: true),
            failureDiagnosticLoader: () async =>
                'Update wurde nicht aktiviert.\nLog: C:\\Users\\Test\\restart.log',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Das letzte Desktop-Update ist fehlgeschlagen.'),
      findsOneWidget,
    );
    expect(find.textContaining('C:\\Users\\Test\\restart.log'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('desktop update requires explicit installation at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = AvailableDesktopUpdater();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDartTournamentTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(body: AndroidUpdatesPanel(service: service)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Nach Updates suchen'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Nach Updates suchen'));
      await tester.pumpAndSettle();
      expect(service.downloads, 0);
      expect(service.installations, 0);
      final install = find.text('Update installieren und neu starten');
      await tester.scrollUntilVisible(
        install,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(install);
      await tester.pumpAndSettle();
      await tester.tap(install);
      await tester.pumpAndSettle();
      expect(service.downloads, 1);
      expect(service.installations, 1);
      expect(tester.takeException(), isNull);
    });
    testWidgets('beta selection, search and restart at $size with large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FakeUpdater(desktop: true);
      final previewKey = GlobalKey();
      Widget page() => MaterialApp(
        theme: buildDartTournamentTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: previewKey,
          child: Scaffold(body: AndroidUpdatesPanel(service: service)),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      final channelTile = find.byType(SwitchListTile);
      Future<void> revealChannelTile() async {
        for (
          var attempt = 0;
          attempt < 20 && channelTile.hitTestable().evaluate().isEmpty;
          attempt++
        ) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -300));
          await tester.pumpAndSettle();
        }
        expect(channelTile.hitTestable(), findsOneWidget);
      }

      await revealChannelTile();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.tap(find.text('Beta-Updates einschließen'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await tester.scrollUntilVisible(
        find.text('Nach Updates suchen'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Nach Updates suchen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nach Updates suchen'));
      await tester.pumpAndSettle();
      expect(service.channels, [true]);
      if (previewFont.isNotEmpty) {
        await tester.runAsync(() async {
          final picture =
              await (previewKey.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final file = File(
            'build/layout_previews/beta_updates_${size.width}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      await revealChannelTile();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await tester.tap(find.text('Beta-Updates einschließen'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.scrollUntilVisible(
        find.text('Nach Updates suchen'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Nach Updates suchen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nach Updates suchen'));
      await tester.pumpAndSettle();
      expect(service.channels, [true, false]);
      expect(tester.takeException(), isNull);
    });
  }
}
