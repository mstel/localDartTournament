// Kleine, versionierte Signalmodelle für Dialoge auf dem Zweitmonitor.
//
// Die Modelle werden als optionale Felder im Turnier-JSON gespeichert. Ältere
// Turniere ohne diese Felder werden dadurch unverändert gelesen.

class SecondScreenAssignmentGroup {
  const SecondScreenAssignmentGroup({
    required this.name,
    required this.members,
  });

  final String name;
  final List<String> members;

  factory SecondScreenAssignmentGroup.fromJson(Object? value) {
    if (value is! Map) {
      return const SecondScreenAssignmentGroup(name: '', members: []);
    }
    final members = value['members'];
    return SecondScreenAssignmentGroup(
      name: value['name']?.toString() ?? '',
      members: members is List
          ? members.map((member) => member.toString()).toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'members': members};
}

class SecondScreenGroupAssignmentRequest {
  const SecondScreenGroupAssignmentRequest({
    required this.id,
    required this.modeLabel,
    required this.groups,
    required this.createdAt,
  });

  factory SecondScreenGroupAssignmentRequest.create({
    required String modeLabel,
    required List<SecondScreenAssignmentGroup> groups,
  }) {
    return SecondScreenGroupAssignmentRequest(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      modeLabel: modeLabel,
      groups: groups,
      createdAt: DateTime.now(),
    );
  }

  final String id;
  final String modeLabel;
  final List<SecondScreenAssignmentGroup> groups;
  final DateTime createdAt;

  static SecondScreenGroupAssignmentRequest? fromJson(Object? value) {
    if (value is! Map) return null;
    final groups = value['groups'];
    return SecondScreenGroupAssignmentRequest(
      id: value['id']?.toString() ?? '',
      modeLabel: value['modeLabel']?.toString() ?? '',
      groups: groups is List
          ? groups
                .map((group) => SecondScreenAssignmentGroup.fromJson(group))
                .toList()
          : const [],
      createdAt:
          _dateTimeFromJson(value['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'modeLabel': modeLabel,
    'groups': groups.map((group) => group.toJson()).toList(),
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

class SecondScreenTournamentInfoRequest {
  const SecondScreenTournamentInfoRequest({
    required this.id,
    required this.visible,
    required this.updatedAt,
  });

  factory SecondScreenTournamentInfoRequest.show() {
    return SecondScreenTournamentInfoRequest(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      visible: true,
      updatedAt: DateTime.now(),
    );
  }

  final String id;
  final bool visible;
  final DateTime updatedAt;

  SecondScreenTournamentInfoRequest hide() => SecondScreenTournamentInfoRequest(
    id: id,
    visible: false,
    updatedAt: DateTime.now(),
  );

  static SecondScreenTournamentInfoRequest? fromJson(Object? value) {
    if (value is! Map) return null;
    return SecondScreenTournamentInfoRequest(
      id: value['id']?.toString() ?? '',
      visible: value['visible'] as bool? ?? false,
      updatedAt:
          _dateTimeFromJson(value['updatedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'visible': visible,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

DateTime? _dateTimeFromJson(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
