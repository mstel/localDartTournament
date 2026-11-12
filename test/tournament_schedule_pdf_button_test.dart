import 'dart:typed_data';

import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/tournament_schedule_pdf_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';

CreatedTournament _tournament(TournamentRunStage? stage) => CreatedTournament(
  name: 'Testturnier',
  players: const [],
  stages: const [],
  runStages: stage == null ? const [] : [stage],
);

class _CapturingPrintingPlatform extends PrintingPlatform {
  String? name;
  PdfPageFormat? format;
  Uint8List? bytes;

  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
    bool windowsModernDialog,
  ) async {
    this.name = name;
    this.format = format;
    bytes = await onLayout(format);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Swiss and Kratzer schedule exports are disabled with a reason', (
    tester,
  ) async {
    final swiss = GroupTournamentRunStage(
      name: 'Swiss',
      groupPlayType: 'swiss',
      groups: [],
      qualificationPlan: null,
      tieBreakers: const [],
    );
    final kratzer = KnockoutTournamentRunStage(
      name: 'Kratzer',
      rounds: const [],
      isKratzer: true,
    );

    for (final stage in [swiss, kratzer]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TournamentSchedulePdfButton(tournament: _tournament(stage)),
          ),
        ),
      );

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        find.byTooltip(
          'Druck / Exportfunktionen des Spielplans für diesen Modus deaktiviert',
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('supported tournament schedules expose the print action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSchedulePdfButton(tournament: _tournament(null)),
        ),
      ),
    );

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('KO PDF uses a bounded bracket and supplies a filename', (
    tester,
  ) async {
    final previousPlatform = PrintingPlatform.instance;
    final platform = _CapturingPrintingPlatform();
    PrintingPlatform.instance = platform;
    addTearDown(() => PrintingPlatform.instance = previousPlatform);

    final players = [
      for (var index = 1; index <= 128; index++)
        TournamentPlayer.generated(index),
    ];
    var matchCount = players.length ~/ 2;
    final rounds = <List<GroupMatch>>[];
    var round = 1;
    while (matchCount > 0) {
      rounds.add([
        for (var index = 0; index < matchCount; index++)
          GroupMatch(
            homePlayer: round == 1 ? players[index * 2] : null,
            awayPlayer: round == 1 ? players[index * 2 + 1] : null,
            round: round,
          ),
      ]);
      matchCount ~/= 2;
      round++;
    }
    final tournament = CreatedTournament(
      name: 'Vereinsmeisterschaft',
      players: players,
      stages: const [],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppenphase',
          groupPlayType: 'round_robin',
          groups: [],
          qualificationPlan: null,
          tieBreakers: const [],
        ),
        KnockoutTournamentRunStage(name: 'KO-Finale', rounds: rounds),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSchedulePdfButton(tournament: tournament),
        ),
      ),
    );
    await tester.tap(find.text('Spielplan als .PDF generieren/drucken'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KO-Finale'));
    await tester.pumpAndSettle();

    expect(platform.name, 'Vereinsmeisterschaft_KO-Finale.pdf');
    expect(platform.format, PdfPageFormat.a4.landscape);
    expect(platform.bytes, isNotEmpty);
    expect(platform.bytes!.length, lessThan(500000));
    expect(tester.takeException(), isNull);
  });
}
