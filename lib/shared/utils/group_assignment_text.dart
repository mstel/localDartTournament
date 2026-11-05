class GroupAssignmentText {
  const GroupAssignmentText._();

  static const header = 'Gruppen:';

  static String format({
    required List<String> groupNames,
    required List<List<String>> groups,
  }) {
    if (groups.isEmpty || groupNames.length != groups.length) {
      throw ArgumentError(
        'Für jede Gruppe muss genau ein Name vorhanden sein.',
      );
    }
    if (groups.any((group) => group.isEmpty)) {
      throw ArgumentError(
        'Jede Gruppe muss mindestens einen Spieler enthalten.',
      );
    }
    return [
      '$header ${groups.length}',
      '',
      for (var index = 0; index < groups.length; index++) ...[
        '${groupNames[index]}:',
        ...groups[index],
        if (index < groups.length - 1) '',
      ],
    ].join('\n');
  }

  static ParsedGroupAssignment parse(String text) {
    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    var firstLine = 0;
    while (firstLine < lines.length && lines[firstLine].trim().isEmpty) {
      firstLine++;
    }
    if (firstLine == lines.length ||
        !lines[firstLine].trim().startsWith(header)) {
      throw const FormatException(
        'Die erste Zeile muss „Gruppen: <Anzahl>“ enthalten.',
      );
    }
    final groupCount = int.tryParse(
      lines[firstLine].trim().substring(header.length).trim(),
    );
    if (groupCount == null || groupCount < 1 || groupCount > 32) {
      throw const FormatException(
        'Die Gruppenzahl muss zwischen 1 und 32 liegen.',
      );
    }

    final groupNames = <String>[];
    final groups = <List<String>>[];
    for (final rawLine in lines.skip(firstLine + 1)) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.endsWith(':')) {
        final groupName = line.substring(0, line.length - 1).trim();
        if (groupName.isEmpty ||
            groupNames.any((existing) => _key(existing) == _key(groupName))) {
          throw const FormatException(
            'Gruppenüberschriften müssen eindeutig und dürfen nicht leer sein.',
          );
        }
        groupNames.add(groupName);
        groups.add([]);
      } else {
        if (groups.isEmpty) {
          throw const FormatException(
            'Vor dem ersten Spielernamen muss eine Gruppenüberschrift stehen.',
          );
        }
        groups.last.add(line);
      }
    }

    if (groups.length != groupCount) {
      throw FormatException(
        'Angegeben sind $groupCount Gruppen, gefunden wurden ${groups.length}.',
      );
    }
    if (groups.any((group) => group.isEmpty)) {
      throw const FormatException(
        'Jede Gruppe muss mindestens einen Spieler enthalten.',
      );
    }
    final names = groups.expand((group) => group).toList();
    if (names.any((name) => name.isEmpty) ||
        names.map(_key).toSet().length != names.length) {
      throw const FormatException(
        'Spielernamen müssen vorhanden und eindeutig sein.',
      );
    }

    return ParsedGroupAssignment(
      groupNames: List.unmodifiable(groupNames),
      groups: [for (final group in groups) List.unmodifiable(group)],
    );
  }

  static String _key(String value) => value.trim().toLowerCase();
}

class ParsedGroupAssignment {
  const ParsedGroupAssignment({required this.groupNames, required this.groups});

  final List<String> groupNames;
  final List<List<String>> groups;

  List<String> get players => [for (final group in groups) ...group];
}
