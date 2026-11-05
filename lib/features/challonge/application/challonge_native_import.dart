import 'package:dart_tournament_manager/tournament_workspace.dart'
    show ProductionTournamentRuntime;
import '../../tournaments/domain/tournament_models.dart';
import '../../tournaments/domain/imported_tournament_archive.dart';

/// Replays historical results through the same runtime used by the run page.
/// Source ranks remain evidence and never override calculated standings.
class ChallongeNativeImport {
  static CreatedTournament convert(CreatedTournament archived) {
    final source = archived.importedArchive!;
    final mode = source.mode;
    if (![
      'single elimination',
      'double elimination',
      'round robin',
      'swiss',
    ].contains(mode)) {
      throw FormatException(
        'Eigene Turnierlogik unterstützt diesen Challonge-Modus noch nicht: $mode.',
      );
    }
    final players = {for (final p in archived.players) p.profileId!: p};
    final bySourceId = <String, TournamentPlayer>{};
    for (final p in source.participants) {
      final player = players[p['profileId']]!;
      bySourceId['${p['id']}'] = player;
      for (final id in p['groupPlayerIds'] as List? ?? const []) {
        bySourceId['$id'] = player;
      }
    }
    final issues = <String>[];
    final groups = <String, List<Map<String, dynamic>>>{};
    final finals = <Map<String, dynamic>>[];
    for (final m in source.matches) {
      if (m['group_id'] != null) {
        groups.putIfAbsent('${m['group_id']}', () => []).add(m);
      } else {
        finals.add(m);
      }
    }
    final stages = <TournamentStage>[];
    final runs = <TournamentRunStage>[];
    CreatedTournament shell() => CreatedTournament.fromJson(
      archived.toJson()
        ..['stages'] = stages.map((s) => s.toJson()).toList()
        ..['runStages'] = runs
            .map(
              (s) => s is GroupTournamentRunStage
                  ? s.toJson()
                  : (s as KnockoutTournamentRunStage).toJson(),
            )
            .toList(),
    );
    List<TournamentPlayer> members(List<Map<String, dynamic>> matches) {
      final ids = <String>{
        for (final m in matches)
          for (final key in ['player1_id', 'player2_id'])
            if (m[key] != null) bySourceId['${m[key]}']!.profileId!,
      };
      return players.values.where((p) => ids.contains(p.profileId)).toList();
    }

    GroupMatch historical(Map<String, dynamic> m) {
      final a = bySourceId['${m['player1_id']}'],
          b = bySourceId['${m['player2_id']}'];
      final score = RegExp(
        r'^(\d+)-(\d+)$',
      ).firstMatch('${m['scores_csv'] ?? ''}');
      if (a == null || b == null) {
        if ((a == null) != (b == null)) {
          if (m['state'] != 'complete' ||
              bySourceId['${m['winner_id']}']?.profileId !=
                  (a ?? b)!.profileId) {
            throw FormatException(
              'Freilos ${m['id']} ist nicht eindeutig abgeschlossen.',
            );
          }
          return GroupMatch(
            homePlayer: a,
            awayPlayer: b,
            round: (m['round'] as int? ?? 1).abs(),
            allowsBye: true,
          );
        }
        throw FormatException(
          'Spiel ${m['id']} hat keine rekonstruierbaren Teilnehmer.',
        );
      }
      if (score == null || m['state'] != 'complete') {
        throw FormatException(
          'Spiel ${m['id']} (${archived.name}) kann nicht vollständig in eigene Ergebnisse übertragen werden.',
        );
      }
      final result = GroupMatch(
        homePlayer: a,
        awayPlayer: b,
        round: (m['round'] as int? ?? 1).abs(),
        homeLegs: int.parse(score[1]!),
        awayLegs: int.parse(score[2]!),
        startedAt: DateTime.tryParse('${m['started_at'] ?? ''}'),
        finishedAt: DateTime.tryParse('${m['completed_at'] ?? ''}'),
      );
      if (result.winner?.profileId !=
          bySourceId['${m['winner_id']}']?.profileId) {
        throw FormatException('Widersprüchlicher Sieger in Spiel ${m['id']}.');
      }
      return result;
    }

    if (groups.isEmpty && ['round robin', 'swiss'].contains(mode)) {
      groups['Turnier'] = finals.toList();
      finals.clear();
    }
    if (groups.isNotEmpty) {
      final playType = mode == 'swiss' ? 'swiss' : 'round_robin';
      final nativeGroups = <TournamentGroup>[];
      for (final entry in groups.entries) {
        final declaredTypes = entry.value
            .map((m) => m['group_type'])
            .whereType<String>()
            .toSet();
        if (declaredTypes.length > 1 ||
            declaredTypes.any(
              (type) => !['swiss', 'round robin'].contains(type),
            )) {
          throw FormatException(
            '${entry.key}: nicht unterstützter oder widersprüchlicher Gruppenmodus.',
          );
        }
        final groupType = declaredTypes.isEmpty
            ? playType
            : declaredTypes.single == 'swiss'
            ? 'swiss'
            : 'round_robin';
        final groupPlayers = members(entry.value);
        final seeds = <String, int>{};
        for (final m in entry.value) {
          for (final index in [1, 2]) {
            final seed = m['player${index}_seed'];
            if (seed is int && m['player${index}_id'] != null) {
              seeds[bySourceId['${m['player${index}_id']}']!.profileId!] = seed;
            }
          }
        }
        if (seeds.length == groupPlayers.length) {
          groupPlayers.sort(
            (a, b) => seeds[a.profileId]!.compareTo(seeds[b.profileId]!),
          );
        }
        nativeGroups.add(
          TournamentGroup(
            name: entry.key,
            playType: groupType,
            players: groupPlayers,
            matches: entry.value.map(historical).toList(),
          ),
        );
      }
      final repeats = <int>[];
      final limits = <int?>[];
      for (final group in nativeGroups) {
        if (group.playType == 'swiss') {
          limits.add(null);
          repeats.add(
            group.matches.fold<int>(
              0,
              (round, m) => m.round > round ? m.round : round,
            ),
          );
          final rounds = repeats.last;
          for (var round = 1; round <= rounds; round++) {
            final present = <TournamentPlayer>[];
            for (final m in group.matches.where((m) => m.round == round)) {
              if (m.homePlayer != null) present.add(m.homePlayer!);
              if (m.awayPlayer != null) present.add(m.awayPlayer!);
            }
            if (present.length != present.toSet().length) {
              throw FormatException(
                '${group.name}: doppelte Swiss-Paarung in Runde $round.',
              );
            }
            final missing = group.players
                .where((p) => !present.contains(p))
                .toList();
            if (missing.length == 1 && group.players.length.isOdd) {
              group.matches.add(
                GroupMatch(
                  homePlayer: missing.single,
                  round: round,
                  allowsBye: true,
                  label:
                      'Swiss · Runde $round · Freilos aus vollständiger Quellrunde',
                ),
              );
            } else if (missing.isNotEmpty) {
              throw FormatException(
                '${group.name}: unvollständige Swiss-Runde $round.',
              );
            }
          }
        } else {
          final pairCounts = <String, int>{};
          for (final m in group.matches.where((m) => m.hasPlayers)) {
            final pair = [m.homePlayer!.profileId!, m.awayPlayer!.profileId!]
              ..sort();
            final key = pair.join('\u0000');
            pairCounts[key] = (pairCounts[key] ?? 0) + 1;
          }
          final counts = pairCounts.values.toSet();
          if (pairCounts.length !=
                  group.players.length * (group.players.length - 1) ~/ 2 ||
              counts.length != 1) {
            final played =
                group.players
                    .map(
                      (p) => group.matches
                          .where(
                            (m) =>
                                m.hasPlayers &&
                                (m.homePlayer == p || m.awayPlayer == p),
                          )
                          .length,
                    )
                    .toList()
                  ..sort();
            if (played.isEmpty ||
                played.first < 1 ||
                played.last - played.first > 1) {
              throw FormatException(
                '${group.name}: unvollständige oder unausgewogene begrenzte Gruppenphase.',
              );
            }
            limits.add(played.last);
            repeats.add(counts.fold<int>(1, (a, b) => a > b ? a : b));
          } else {
            limits.add(null);
            repeats.add(counts.single);
          }
        }
      }
      final qualified = finals.isEmpty ? <TournamentPlayer>[] : members(finals);
      final fixed = nativeGroups
          .map((g) => g.players.where(qualified.contains).length)
          .toList();
      final plan = finals.isEmpty
          ? null
          : QualificationPlan(
              totalQualifiers: qualified.length,
              fixedPerGroup: 0,
              fixedByGroup: fixed,
              extraCount: 0,
              extraRank: 0,
              eligibleGroupSize: null,
              extraGroups: const [],
            );
      stages.add(
        TournamentStage(
          name: nativeGroups.every((g) => g.playType == 'swiss')
              ? 'Swiss'
              : 'Gruppenphase',
          type: 'groups',
          groupCount: nativeGroups.length,
          groupSizes: nativeGroups.map((g) => g.players.length).toList(),
          groupPlayType: nativeGroups.first.playType,
          groupPlayTypes: nativeGroups.map((g) => g.playType).toList(),
          groupRoundRobinRepeats: repeats,
          groupMaxGamesPerPlayer: limits,
          fixedQualifiersByGroup: fixed,
          qualifiedParticipantCount: plan?.totalQualifiers,
          qualificationAutoAdjust: false,
          finalEndsTournament: finals.isEmpty,
        ),
      );
      runs.add(
        GroupTournamentRunStage(
          name: stages.last.name,
          groupPlayType: nativeGroups.first.playType,
          groups: nativeGroups,
          qualificationPlan: plan,
          tieBreakers: defaultGroupTieBreakers,
        ),
      );
      final runtime = ProductionTournamentRuntime(shell());
      for (final group in nativeGroups) {
        final calculated = runtime.standings(group, defaultGroupTieBreakers);
        for (var i = 0; i < calculated.length; i++) {
          final p = source.participants.singleWhere(
            (p) => p['profileId'] == calculated[i].player.profileId,
          );
          final expected = finals.isEmpty
              ? p['finalRank']
              : (p['groupPlacements'] as List? ?? const [])
                    .where((g) => g['group'] == group.name)
                    .firstOrNull?['rank'];
          if (expected != null && expected != i + 1) {
            issues.add(
              '${group.name}: ${calculated[i].player.name} berechnet Platz ${i + 1}, Challonge Platz $expected.',
            );
          }
        }
      }
      if (plan != null) {
        final actual = runtime
            .qualifiers(runs.single)
            .map((p) => p.profileId)
            .toSet();
        final expected = qualified.map((p) => p.profileId).toSet();
        if (actual.length != expected.length || !actual.containsAll(expected)) {
          issues.add(
            'Weiterkommen aus der Gruppenphase unterscheidet sich von Challonge. Die historische K.-o.-Besetzung wird als tatsächliche Teilnehmerliste übernommen.',
          );
        }
      }
    }
    if (finals.isNotEmpty) {
      // Validate even source bye rows before replay or member creation.
      for (final m in finals) {
        historical(m);
      }
      final entrants = members(finals);
      final firstRound = finals
          .where((m) => (m['round'] as int? ?? 0) == 1)
          .toList();
      final slots = <TournamentPlayer?>[];
      for (final m in firstRound) {
        slots.add(bySourceId['${m['player1_id']}']);
        slots.add(bySourceId['${m['player2_id']}']);
      }
      for (final p in entrants.where((p) => !slots.contains(p))) {
        slots.add(p);
        slots.add(null);
      }
      var size = 2;
      while (size < entrants.length) {
        size *= 2;
      }
      while (slots.length < size) {
        slots.add(null);
      }
      if (slots.length != size) {
        throw FormatException(
          'Historische Startplätze von ${archived.name} sind nicht eindeutig rekonstruierbar.',
        );
      }
      final third = finals.any((m) => m['round'] == 0);
      var winnerRounds = 0;
      for (var width = size; width > 1; width ~/= 2) {
        winnerRounds++;
      }
      final hasReset =
          mode == 'double elimination' &&
          finals.any((m) => (m['round'] as int? ?? 0) > winnerRounds + 1);
      final setup = TournamentStage(
        name: mode == 'double elimination' ? 'Doppel-K.-o.' : 'K.-o.-Phase',
        type: mode == 'double elimination'
            ? 'double_knockout'
            : 'single_knockout',
        knockoutLives: mode == 'double elimination' ? 2 : 1,
        knockoutParticipantCount: entrants.length,
        knockoutBracketSize: size,
        knockoutSeedingMode: 'manual',
        knockoutSlotOrder: slots
            .map((p) => p == null ? null : entrants.indexOf(p) + 1)
            .toList(),
        placementPlaces: third ? [3] : const [],
        finalEndsTournament: !hasReset,
      );
      stages.add(setup);
      final runtime = ProductionTournamentRuntime(shell());
      final native =
          runtime.build(setup, entrants) as KnockoutTournamentRunStage;
      runs.add(native);
      // Runtime and destination share the same mutable run-stage objects.
      // shell() serializes them, so replay in its own restored model instead.
      final replayModel = shell();
      final replay = ProductionTournamentRuntime(replayModel)
        ..activate(runs.length - 1);
      var replayStage =
          replayModel.runStages.last as KnockoutTournamentRunStage;
      final pending = finals
          .where((m) => m['player1_id'] != null && m['player2_id'] != null)
          .toList();
      if (mode == 'double elimination') {
        List<Map<String, dynamic>> matchesAtRound(int round) => finals
            .where((match) => (match['round'] as int? ?? 1) == round)
            .toList();

        List<GroupMatch> targetsFor(String label) => replayStage.rounds
            .expand((round) => round)
            .where((match) => match.label == label)
            .toList();

        void applyResult(GroupMatch target, Map<String, dynamic> sourceMatch) {
          final result = historical(sourceMatch);
          target
            ..homePlayer = result.homePlayer
            ..awayPlayer = result.awayPlayer
            ..homeLegs = result.homeLegs
            ..awayLegs = result.awayLegs
            ..startedAt = result.startedAt
            ..finishedAt = result.finishedAt;
          pending.remove(sourceMatch);
        }

        void importRound(
          int roundNumber,
          List<GroupMatch> targets, {
          bool allowRewire = false,
        }) {
          final available = [...targets];
          for (final match in matchesAtRound(roundNumber)) {
            final home = bySourceId['${match['player1_id']}'];
            final away = bySourceId['${match['player2_id']}'];
            final target = available.cast<GroupMatch?>().firstWhere(
              (candidate) =>
                  candidate != null &&
                      candidate.homePlayer?.profileId == home?.profileId &&
                      candidate.awayPlayer?.profileId == away?.profileId ||
                  (candidate != null &&
                      candidate.homePlayer?.profileId == away?.profileId &&
                      candidate.awayPlayer?.profileId == home?.profileId),
              orElse: () => null,
            );
            final selected =
                target ??
                (allowRewire
                    ? available
                          .where((candidate) => !candidate.hasResult)
                          .firstOrNull
                    : null);
            if (selected == null) {
              throw FormatException(
                '${archived.name}: Challonge-Spiel ${match['id']} in Runde $roundNumber (${home?.name} gegen ${away?.name}) passt nicht in das rekonstruierte Doppel-K.-o.-Bracket. Zielspiele: ${available.map((target) => '${target.homePlayer?.name ?? 'offen'} gegen ${target.awayPlayer?.name ?? 'offen'}').join('; ')}.',
              );
            }
            applyResult(selected, match);
            available.remove(selected);
          }
        }

        replay.advance();
        importRound(1, replayStage.rounds.first);
        for (var round = 2; round <= winnerRounds; round++) {
          importRound(
            round,
            targetsFor('Winners Runde $round'),
            allowRewire: true,
          );
        }
        final losersRoundCount = replayStage.rounds
            .expand((round) => round)
            .map((match) {
              final label = match.label ?? '';
              final marker = 'Losers Runde ';
              return label.startsWith(marker)
                  ? int.tryParse(label.substring(marker.length)) ?? 0
                  : 0;
            })
            .fold<int>(0, (a, b) => a > b ? a : b);
        for (var round = 1; round <= losersRoundCount; round++) {
          importRound(
            -round,
            targetsFor('Losers Runde $round'),
            allowRewire: true,
          );
        }

        final positiveFinalRounds = finals
            .map((match) => match['round'] as int? ?? 0)
            .where((round) => round > winnerRounds)
            .toList();
        if (positiveFinalRounds.isNotEmpty) {
          final sourceGrandFinalRound = positiveFinalRounds.reduce(
            (a, b) => a > b ? a : b,
          );
          final hasReset = sourceGrandFinalRound > winnerRounds + 1;
          final grandFinalRound = hasReset
              ? sourceGrandFinalRound - 1
              : sourceGrandFinalRound;
          importRound(
            grandFinalRound,
            targetsFor('Grand Final'),
            allowRewire: true,
          );
          if (hasReset) {
            if (targetsFor('Reset Final').isEmpty) {
              replayStage.rounds.add([
                GroupMatch(
                  round: replayStage.rounds.length + 1,
                  label: 'Reset Final',
                ),
              ]);
            }
            importRound(
              sourceGrandFinalRound,
              targetsFor('Reset Final'),
              allowRewire: true,
            );
          }
        }
        final placementResults = matchesAtRound(0)
            .where(
              (match) =>
                  match['player1_id'] != null && match['player2_id'] != null,
            )
            .map((match) {
              final result = historical(match);
              pending.remove(match);
              return GroupMatch(
                homePlayer: result.homePlayer,
                awayPlayer: result.awayPlayer,
                round: 0,
                homeLegs: result.homeLegs,
                awayLegs: result.awayLegs,
                placementRank: 3,
                label: 'Spiel um Platz 3',
                startedAt: result.startedAt,
                finishedAt: result.finishedAt,
              );
            })
            .toList();
        if (placementResults.isNotEmpty) {
          replayStage = KnockoutTournamentRunStage(
            name: replayStage.name,
            rounds: replayStage.rounds,
            placementMatches: [
              ...replayStage.placementMatches,
              ...placementResults,
            ],
            eliminationLossLimit: replayStage.eliminationLossLimit,
            finalEndsTournament: replayStage.finalEndsTournament,
          );
          replayModel.runStages[runs.length - 1] = replayStage;
        }
      } else {
        for (
          var pass = 0;
          pass < finals.length + 3 && pending.isNotEmpty;
          pass++
        ) {
          replay.advance();
          var progress = false;
          for (final target
              in replay
                  .matches(replayStage)
                  .where((m) => m.hasPlayers && !m.hasResult)) {
            final placement =
                target.placementRank != null ||
                target.label == 'Spiel um Platz 3';
            final candidates = pending
                .where(
                  (m) =>
                      (m['round'] == 0) == placement &&
                      ({
                        bySourceId['${m['player1_id']}']!.profileId,
                        bySourceId['${m['player2_id']}']!.profileId,
                      }.containsAll([
                        target.homePlayer!.profileId,
                        target.awayPlayer!.profileId,
                      ])),
                )
                .toList();
            if (candidates.isEmpty) continue;
            final m = candidates.first;
            final result = historical(m);
            final reversed =
                result.homePlayer!.profileId != target.homePlayer!.profileId;
            target.homeLegs = reversed ? result.awayLegs : result.homeLegs;
            target.awayLegs = reversed ? result.homeLegs : result.awayLegs;
            target.startedAt = result.startedAt;
            target.finishedAt = result.finishedAt;
            pending.remove(m);
            progress = true;
          }
          if (!progress) break;
        }
        replay.advance();
      }
      if (pending.isNotEmpty || replay.hasOpen(replayStage)) {
        final unresolvedTargets = replay
            .matches(replayStage)
            .where((match) => match.hasPlayers && !match.hasResult)
            .map(
              (match) =>
                  '${match.homePlayer!.name} gegen ${match.awayPlayer!.name}',
            )
            .join('; ');
        throw FormatException(
          'Die eigene K.-o.-Weiterleitung konnte ${pending.length} historische Spiele von ${archived.name} nicht nachspielen: ${pending.map((m) => '${m['id']} (${bySourceId['${m['player1_id']}']?.name ?? 'Freilos'} gegen ${bySourceId['${m['player2_id']}']?.name ?? 'Freilos'})').join('; ')}. Offene Zielspiele: $unresolvedTargets. Import vor dem Speichern abgebrochen.',
        );
      }
      runs[runs.length - 1] = replayStage;
      final ranking = replay.ranking(replayStage, entrants);
      for (final p in source.participants.where(
        (p) => p['finalRank'] != null,
      )) {
        final i = ranking.indexWhere(
          (player) => player.profileId == p['profileId'],
        );
        if (i < 0) {
          issues.add(
            'Gesamtplatz ${p['name']} (${p['finalRank']}) liegt außerhalb der finalen K.-o.-Etappe und wurde nicht gegen deren Rangfolge geprüft. Die Gruppenwertung bleibt separat erhalten.',
          );
        }
        if (i >= 0 && i + 1 != p['finalRank']) {
          issues.add(
            'Endplatz ${p['name']}: berechnet ${i + 1}, Challonge ${p['finalRank']}. Geteilte Plätze und unterschiedliche Tie-Breaker beachten.',
          );
        }
      }
    }
    if (runs.isEmpty) {
      throw const FormatException(
        'Keine native Turnieretappe rekonstruierbar.',
      );
    }
    final archive = ImportedTournamentArchive(
      sourceId: source.sourceId,
      url: source.url,
      mode: source.mode,
      participants: source.participants,
      matches: source.matches,
      nativeValidation: {
        'version': 1,
        'status': issues.isEmpty ? 'matched' : 'differences',
        'issues': issues,
        'checkedMatches': source.matches.length,
        'runtime': 'production',
      },
    );
    return CreatedTournament.fromJson(
      archived.toJson()
        ..['stages'] = stages.map((s) => s.toJson()).toList()
        ..['runStages'] = runs
            .map(
              (s) => s is GroupTournamentRunStage
                  ? s.toJson()
                  : (s as KnockoutTournamentRunStage).toJson(),
            )
            .toList()
        ..['completedStageIndexes'] = [for (var i = 0; i < runs.length; i++) i]
        ..['activeStageIndex'] = runs.length - 1
        ..['importedArchive'] = archive.toJson(),
    );
  }
}
