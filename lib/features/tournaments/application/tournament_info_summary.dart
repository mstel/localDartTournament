import '../domain/tournament_models.dart';

/// Kompakte, testbaretexte für den Turnierinfo-Dialog auf dem Zweitmonitor.
class TournamentInfoSummary {
  const TournamentInfoSummary._();

  static String groupAssignmentModeLabel(String mode) => switch (mode) {
    'balanced' => 'Spielstärke gleichmäßig verteilen',
    'random' => 'Zufällige Verteilung',
    'manual' => 'Gruppen manuell festlegen',
    _ => 'Nach Spielstärke gruppieren',
  };

  static String knockoutSeedingModeLabel(String mode) => switch (mode) {
    'random_cross' => 'Gruppenplatzierung - Zufällige Kreuzpaarungen',
    'elo' => 'Leistungsbasierte Setzliste (ELO)',
    'manual' => 'Manuelle Paarungszuordnung',
    'random' => 'Zufallsauslosung beim Turnierstart',
    _ => 'Gruppenplatzierung - Feste Kreuzpaarungen',
  };

  static String tieBreakers(List<String> tieBreakers) => tieBreakers.isEmpty
      ? 'Keine definiert'
      : tieBreakers.map(tieBreakerLabel).join(' > ');

  static String format(TournamentGameFormat format) {
    final bestOf = format.bestOfSets == 1
        ? 'Bo${format.bestOfLegs} Legs'
        : 'Bo${format.bestOfSets} Sets';
    final checkout = format.gameType == 'cricket'
        ? 'Cricket'
        : '${format.x01Score} ${switch (format.checkoutType) {
            'single_out' => 'SO',
            'master_out' => 'MO',
            _ => 'DO',
          }}';
    return '$bestOf, $checkout';
  }

  static String playType(TournamentStage stage) {
    final repeats = stage.groupRoundRobinRepeats.isEmpty
        ? 1
        : stage.groupRoundRobinRepeats.first;
    return switch (stage.groupPlayType) {
      'swiss' => 'Schweizer System',
      'round_robin' => 'Round Robin (${repeats < 1 ? 1 : repeats}x)',
      _ => 'Jeder gegen jeden',
    };
  }

  static String advancement(TournamentStage stage) {
    final plan = stage.qualificationSummary;
    if (plan != null && plan.isNotEmpty) return plan;
    final count = stage.qualifiedParticipantCount;
    return count == null ? 'Keine Weiterkommen-Regel' : '$count weiter';
  }

  /// Kurzform für die Kopfzeile „Tabellen & Zwischenstände“.
  static String compactFormat(TournamentStage stage) {
    final parts = <String>[
      format(stage.gameFormat),
      playType(stage),
      advancement(stage),
    ];
    return parts.join(', ');
  }

  static String duration(int? minutes) {
    final value = minutes ?? 0;
    if (value <= 0) return 'nicht geschätzt';
    final hours = value ~/ 60;
    final remainder = value % 60;
    return hours == 0
        ? '$remainder min'
        : remainder == 0
        ? '$hours h'
        : '$hours:$remainder${remainder < 10 ? '0' : ''} h';
  }

  static String groupSizes(TournamentStage stage) {
    if (stage.groupSizes.isEmpty) {
      return stage.groupCount == null
          ? 'Gruppenphase'
          : '${stage.groupCount} Gruppen';
    }
    final sizes = stage.groupSizes;
    final min = sizes.reduce((a, b) => a < b ? a : b);
    final max = sizes.reduce((a, b) => a > b ? a : b);
    return 'Gruppen je $min${min == max ? '' : '-$max'} Teilnehmer';
  }

  static String stageType(TournamentStage stage) {
    if (stage.isGroupStage) return 'Gruppenphase';
    return switch (stage.type) {
      'double_knockout' => 'Doppel-K.-o.',
      'triple_knockout' || 'kratzer' => 'Kratzer-Modus',
      _ => 'K.-o.-Phase',
    };
  }
}
