import 'package:dart_tournament_manager/app/app_theme.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart';

void main() {
  const previewFont = String.fromEnvironment('LAYOUT_PREVIEW_FONT');
  setUpAll(() async {
    if (previewFont.isNotEmpty) {
      await (FontLoader('Roboto')..addFont(
            File(
              previewFont,
            ).readAsBytes().then((b) => ByteData.sublistView(b)),
          ))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('creation choices $size scale $scale', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        final previewKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: buildDartTournamentTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: previewKey,
              child: const TournamentCreationPage(),
            ),
          ),
        );
        final expert = find.text('Normales- oder Ranglistenturnier erstellen');
        await tester.scrollUntilVisible(
          expert,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(expert);
        await tester.pumpAndSettle();
        expect(find.text('Passende Turnierform'), findsOneWidget);
        expect(expert, findsNothing);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('tournament-name-field')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.byType(TextField), findsWidgets);
        if (previewFont.isNotEmpty) {
          await tester.runAsync(() async {
            final boundary =
                previewKey.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/layout_previews/ExpertCreation_${size.width}_$scale.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await tester.enterText(
          find.byKey(const ValueKey('tournament-name-field')),
          'Open Cup',
        );
        expect(
          find.byKey(const ValueKey('tournament-name-field')),
          findsOneWidget,
        );
        expect(expert, findsNothing);
        expect(find.text('Geräte hinzufügen / verwalten'), findsNothing);
        tester.view.physicalSize = const Size(360, 800);
        await tester.pumpAndSettle();
        expect(expert, findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
