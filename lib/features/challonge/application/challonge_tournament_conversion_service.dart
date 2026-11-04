import '../../tournaments/domain/imported_tournament_archive.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../data/challonge_client.dart';
import '../domain/challonge_tournament.dart';
import 'challonge_native_import.dart';

typedef ChallongeTournamentFetcher =
    Future<ChallongeTournament> Function(String url);

class ChallongeTournamentConversionService {
  ChallongeTournamentConversionService({ChallongeTournamentFetcher? fetch})
    : _fetch = fetch ?? _fetchPublicTournament;

  final ChallongeTournamentFetcher _fetch;

  Future<CreatedTournament> convert(CreatedTournament archived) async {
    final archive = archived.importedArchive;
    if (archive == null) {
      throw const FormatException('Dieses Turnier stammt nicht aus Challonge.');
    }
    if (archive.usesNativeLogic) {
      throw const FormatException(
        'Dieses Challonge-Turnier wurde bereits konvertiert.',
      );
    }
    _validatePlayerAssignments(archive);
    if (_needsGroupNames(archive) && archive.url.isNotEmpty) {
      try {
        final fresh = await _fetch(archive.url);
        if (fresh.id != archive.sourceId) {
          throw const FormatException(
            'Der Challonge-Link gehört zu einem anderen Turnier.',
          );
        }
        return ChallongeNativeImport.convert(
          _refreshArchive(archived, archive, fresh),
        );
      } on FormatException catch (refreshError) {
        try {
          final converted = ChallongeNativeImport.convert(archived);
          return _withValidationIssue(
            converted,
            'Gruppennamen konnten nicht erneut von Challonge geladen werden; '
            'die gespeicherten Gruppenkennungen wurden beibehalten: '
            '$refreshError',
          );
        } on FormatException catch (localError) {
          throw FormatException(
            '${localError.message} Fehlende Daten konnten auch nicht über den '
            'Challonge-Link ergänzt werden: $refreshError',
          );
        }
      }
    }
    try {
      return ChallongeNativeImport.convert(archived);
    } on FormatException catch (localError) {
      if (archive.url.isEmpty) rethrow;
      try {
        final fresh = await _fetch(archive.url);
        if (fresh.id != archive.sourceId) {
          throw const FormatException(
            'Der Challonge-Link gehört zu einem anderen Turnier.',
          );
        }
        final refreshed = _refreshArchive(archived, archive, fresh);
        return ChallongeNativeImport.convert(refreshed);
      } on FormatException catch (refreshError) {
        final detail = refreshError.message;
        throw FormatException(
          '${localError.message} Fehlende Daten konnten auch nicht über den '
          'Challonge-Link ergänzt werden: $detail',
        );
      }
    }
  }

  bool _needsGroupNames(ImportedTournamentArchive archive) {
    final groups = archive.matches
        .map((match) => match['group_id'])
        .where((id) => id != null)
        .map((id) => '$id')
        .toSet();
    return groups.any((id) => RegExp(r'^\d+$').hasMatch(id));
  }

  CreatedTournament _withValidationIssue(
    CreatedTournament tournament,
    String issue,
  ) {
    final data = tournament.toJson();
    final archive = Map<String, dynamic>.from(data['importedArchive'] as Map);
    final validation = Map<String, dynamic>.from(
      archive['nativeValidation'] as Map,
    );
    final issues = List<String>.from(validation['issues'] as List)..add(issue);
    validation
      ..['status'] = 'differences'
      ..['issues'] = issues;
    archive['nativeValidation'] = validation;
    data['importedArchive'] = archive;
    return CreatedTournament.fromJson(data);
  }

  static Future<ChallongeTournament> _fetchPublicTournament(String url) async {
    // Imported public tournaments need no API key; private tournaments can
    // still be converted from the data already stored in the local archive.
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        (uri.host != 'challonge.com' && !uri.host.endsWith('.challonge.com'))) {
      throw const FormatException('Ungültiger öffentlicher Challonge-Link.');
    }
    // The public reader is deliberately used without credentials here.
    return ChallongeClient().tournament('', url);
  }

  CreatedTournament _refreshArchive(
    CreatedTournament archived,
    ImportedTournamentArchive archive,
    ChallongeTournament fresh,
  ) {
    final profilesBySourceId = <String, String>{};
    final profilesByName = <String, List<String>>{};
    for (final participant in archive.participants) {
      final profileId = participant['profileId'] as String?;
      if (profileId == null) continue;
      profilesBySourceId['${participant['id']}'] = profileId;
      final key = ChallongeTournament.normalizedName(
        '${participant['name'] ?? ''}',
      );
      profilesByName.putIfAbsent(key, () => []).add(profileId);
    }
    final profiles = <String, String>{};
    for (final participant in fresh.participants) {
      final id = '${participant['id']}';
      final exact = profilesBySourceId[id];
      final matchesByName =
          profilesByName[ChallongeTournament.normalizedName(
            ChallongeTournament.name(participant),
          )] ??
          const <String>[];
      final profileId =
          exact ?? (matchesByName.length == 1 ? matchesByName.single : null);
      if (profileId != null) profiles[id] = profileId;
    }
    if (profiles.values.toSet().length != profiles.length ||
        fresh.participants.any(
          (participant) => profiles['${participant['id']}'] == null,
        )) {
      throw const FormatException(
        'Die aktualisierten Challonge-Teilnehmer konnten nicht eindeutig den '
        'zugewiesenen Spielerprofilen zugeordnet werden. Bitte Zuordnung prüfen.',
      );
    }

    final source = fresh.convert(
      profiles,
      countsForRanking: archived.countsForRanking,
      rankingIds: archived.rankingIds,
    );
    final oldBestPerformances = {
      for (final match in archive.matches)
        if (match['id'] != null && match['bestPerformances'] is List)
          '${match['id']}': match['bestPerformances'],
    };
    final refreshedMatches = [
      for (final match in source.importedArchive!.matches)
        {
          ...match,
          if (oldBestPerformances['${match['id']}'] != null)
            'bestPerformances': oldBestPerformances['${match['id']}'],
        },
    ];
    final refreshedArchive = source.importedArchive!.copyWithMatches(
      refreshedMatches,
    );
    final freshData = source.toJson();
    final data = archived.toJson()
      ..['players'] = freshData['players']
      ..['startedAt'] = freshData['startedAt']
      ..['finishedAt'] = freshData['finishedAt']
      ..['importedArchive'] = refreshedArchive.toJson();
    return CreatedTournament.fromJson(data);
  }

  void _validatePlayerAssignments(ImportedTournamentArchive archive) {
    final profileIds = <String>[];
    for (final participant in archive.participants) {
      final profileId = participant['profileId'] as String?;
      if (profileId == null || profileId.isEmpty) {
        throw const FormatException(
          'Bitte zuerst alle Challonge-Teilnehmer einem Spieler im '
          'Spielerkatalog zuordnen.',
        );
      }
      profileIds.add(profileId);
    }
    if (profileIds.toSet().length != profileIds.length) {
      throw const FormatException(
        'Jeder Challonge-Teilnehmer muss einem eigenen Spielerprofil '
        'zugeordnet sein.',
      );
    }
  }
}
