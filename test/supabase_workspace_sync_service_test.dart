import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/backups/application/supabase_workspace_sync_service.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('workspace_proof_test_');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'copies an exact schema 22 proof beside matching account data',
    () async {
      final active = File('${root.path}/account/tournaments.json');
      final sourceProof = File('${root.path}/legacy/tournaments.json.v22.bak');
      await active.parent.create(recursive: true);
      await sourceProof.parent.create(recursive: true);
      await active.writeAsString(
        '{"schemaVersion":24,"tournaments":[{"id":"safe-match"}]}',
      );
      await sourceProof.writeAsString(
        '{"schemaVersion":22,"tournaments":[{"id":"safe-match"}]}',
      );

      final copied =
          await SupabaseWorkspaceSyncService.copyMatchingSchema24Proof(
            activeTournamentFile: active,
            sourceProofFile: sourceProof,
          );

      expect(copied, isTrue);
      expect(
        await File('${active.path}.v22.bak').readAsString(),
        await sourceProof.readAsString(),
      );
    },
  );

  test('does not copy a proof for a different local dataset', () async {
    final active = File('${root.path}/account/tournaments.json');
    final sourceProof = File('${root.path}/legacy/tournaments.json.v22.bak');
    await active.parent.create(recursive: true);
    await sourceProof.parent.create(recursive: true);
    await active.writeAsString(
      '{"schemaVersion":24,"tournaments":[{"id":"A"}]}',
    );
    await sourceProof.writeAsString(
      '{"schemaVersion":22,"tournaments":[{"id":"B"}]}',
    );
    final activeBefore = await active.readAsBytes();
    final proofBefore = await sourceProof.readAsBytes();

    final copied = await SupabaseWorkspaceSyncService.copyMatchingSchema24Proof(
      activeTournamentFile: active,
      sourceProofFile: sourceProof,
    );

    expect(copied, isFalse);
    expect(await File('${active.path}.v22.bak').exists(), isFalse);
    expect(await active.readAsBytes(), activeBefore);
    expect(await sourceProof.readAsBytes(), proofBefore);
  });

  test('never overwrites an existing proof', () async {
    final active = File('${root.path}/account/tournaments.json');
    final existingProof = File('${active.path}.v22.bak');
    final sourceProof = File('${root.path}/legacy/tournaments.json.v22.bak');
    await active.parent.create(recursive: true);
    await sourceProof.parent.create(recursive: true);
    await active.writeAsString(
      jsonEncode({'schemaVersion': 24, 'tournaments': <Object>[]}),
    );
    await existingProof.writeAsString('existing proof');
    await sourceProof.writeAsString(
      jsonEncode({'schemaVersion': 22, 'tournaments': <Object>[]}),
    );

    final copied = await SupabaseWorkspaceSyncService.copyMatchingSchema24Proof(
      activeTournamentFile: active,
      sourceProofFile: sourceProof,
    );

    expect(copied, isFalse);
    expect(await existingProof.readAsString(), 'existing proof');
  });

  test('only resumes after a valid tournament archive contains data', () async {
    final file = File('${root.path}/tournaments.json');
    await file.writeAsString(
      '{"schemaVersion":27,"tournaments":[{"id":"kept"}]}',
    );
    final originalBytes = await file.readAsBytes();

    expect(
      await SupabaseWorkspaceSyncService.hasLocalTournamentData(file),
      isTrue,
    );
    expect(await file.readAsBytes(), originalBytes);

    await file.writeAsString('{"schemaVersion":27,"tournaments":[]}');
    expect(
      await SupabaseWorkspaceSyncService.hasLocalTournamentData(file),
      isFalse,
    );
    expect(
      await SupabaseWorkspaceSyncService.hasLocalTournamentData(
        File('${root.path}/missing.json'),
      ),
      isFalse,
    );
  });
}
