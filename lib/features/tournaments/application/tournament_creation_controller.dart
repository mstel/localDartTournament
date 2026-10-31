import '../data/tournament_storage.dart';
import '../domain/tournament_models.dart';

class TournamentCreationController {
  const TournamentCreationController({TournamentStorage? storage})
    : _storage = storage;

  final TournamentStorage? _storage;

  bool hasRecordedResults(CreatedTournament tournament) =>
      tournament.runStages.any((stage) {
        if (stage is GroupTournamentRunStage) {
          return stage.groups.any(
            (group) => [
              ...group.matches,
              ...group.knockoutRounds.expand((round) => round),
              ...group.placementMatches,
            ].any((match) => match.hasResult),
          );
        }
        if (stage is KnockoutTournamentRunStage) {
          return [
            ...stage.rounds.expand((round) => round),
            ...stage.placementMatches,
          ].any((match) => match.hasResult);
        }
        return false;
      });

  Future<CreatedTournament> createTournament({
    int boardCount = 4,
    bool countsForRanking = false,
    List<String> rankingIds = const [],
    required String name,
    required List<TournamentPlayer> players,
    required List<TournamentStage> stages,
    required List<TournamentRunStage> runStages,
  }) async {
    final tournament = _buildTournament(
      boardCount: boardCount,
      name: name,
      players: players,
      stages: stages,
      runStages: runStages,
      countsForRanking: countsForRanking,
      rankingIds: rankingIds,
    );
    await (_storage ?? TournamentStorage()).saveTournament(tournament);
    return tournament;
  }

  Future<CreatedTournament> createTournamentCopy({
    int boardCount = 4,
    bool countsForRanking = false,
    List<String> rankingIds = const [],
    required String name,
    required List<TournamentPlayer> players,
    required List<TournamentStage> stages,
    required List<TournamentRunStage> runStages,
  }) async {
    final cleanDraft = CreatedTournament.fromJson({
      'name': name,
      'players': players.map((player) => player.toJson()).toList(),
      'stages': stages.map((stage) => stage.toJson()).toList(),
      'runStages': runStages.map(_runStageWithoutResults).toList(),
      'boardCount': boardCount,
      'countsForRanking': countsForRanking,
      'rankingIds': rankingIds,
    });
    return createTournament(
      boardCount: boardCount,
      countsForRanking: countsForRanking,
      rankingIds: rankingIds,
      name: name,
      players: players,
      stages: stages,
      runStages: cleanDraft.runStages,
    );
  }

  Future<CreatedTournament> updateTournament(
    CreatedTournament existing, {
    required int boardCount,
    required bool countsForRanking,
    required List<String> rankingIds,
    required String name,
    required List<TournamentPlayer> players,
    required List<TournamentStage> stages,
    required List<TournamentRunStage> runStages,
    required bool settingsChanged,
  }) async {
    if (hasRecordedResults(existing)) {
      throw StateError(
        'Ein Turnier mit eingetragenen Ergebnissen kann nicht überschrieben werden.',
      );
    }
    final updated = CreatedTournament.fromJson({
      ...existing.toJson(),
      'name': name,
      'players': players.map((player) => player.toJson()).toList(),
      'stages': stages.map((stage) => stage.toJson()).toList(),
      'runStages': runStages.map(_runStageToJson).toList(),
      'boardCount': boardCount,
      'countsForRanking': countsForRanking,
      'rankingIds': rankingIds,
      if (settingsChanged) 'activeStageIndex': 0,
      if (settingsChanged) 'completedStageIndexes': const <int>[],
      if (settingsChanged) 'startedAt': null,
      if (settingsChanged) 'finishedAt': null,
      if (settingsChanged) 'pausedAt': null,
      if (settingsChanged) 'blockedBoards': const <int>[],
      if (settingsChanged) 'totalPausedSeconds': 0,
    });
    await (_storage ?? TournamentStorage()).saveTournament(updated);
    return updated;
  }

  Map<String, dynamic> _runStageToJson(TournamentRunStage stage) {
    if (stage is GroupTournamentRunStage) return stage.toJson();
    if (stage is KnockoutTournamentRunStage) return stage.toJson();
    throw StateError('Nicht unterstützte Turnieretappe: ${stage.runtimeType}');
  }

  Map<String, dynamic> _runStageWithoutResults(TournamentRunStage stage) {
    final json = _runStageToJson(stage);
    if (stage is GroupTournamentRunStage) {
      for (final group in json['groups'] as List) {
        final groupJson = Map<String, dynamic>.from(group as Map);
        _clearMatchList(groupJson['matches'] as List);
        for (final round in groupJson['knockoutRounds'] as List) {
          _clearMatchList(round as List);
        }
        _clearMatchList(groupJson['placementMatches'] as List);
      }
    } else if (stage is KnockoutTournamentRunStage) {
      for (final round in json['rounds'] as List) {
        _clearMatchList(round as List);
      }
      _clearMatchList(json['placementMatches'] as List);
    }
    return json;
  }

  void _clearMatchList(List matches) {
    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      final matchJson = Map<String, dynamic>.from(match as Map);
      matchJson
        ..['homeLegs'] = null
        ..['awayLegs'] = null
        ..['homeSets'] = null
        ..['awaySets'] = null
        ..['isAnnulled'] = false
        ..['boardNumber'] = null
        ..['startedAt'] = null
        ..['finishedAt'] = null
        ..['startedPlayers'] = null
        ..['withdrawalSignature'] = null
        ..['withdrawalIgnored'] = false
        ..['withdrawalHadResult'] = false
        ..['bestPerformances'] = const [];
      matches[index] = matchJson;
    }
  }

  CreatedTournament _buildTournament({
    int boardCount = 4,
    required String name,
    required List<TournamentPlayer> players,
    required List<TournamentStage> stages,
    required List<TournamentRunStage> runStages,
    bool countsForRanking = true,
    List<String> rankingIds = const [],
  }) {
    return CreatedTournament(
      boardCount: boardCount.clamp(1, 64),
      name: name.trim().isEmpty ? 'Neues Turnier' : name.trim(),
      players: List.unmodifiable(players),
      stages: List.unmodifiable(stages),
      runStages: runStages,
      countsForRanking: countsForRanking,
      rankingIds: List.unmodifiable(rankingIds),
    );
  }
}
