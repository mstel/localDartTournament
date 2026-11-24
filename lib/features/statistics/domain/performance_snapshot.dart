import 'dart:math';

/// Ein kumulierter Messpunkt aus der öffentlichen Scolia-Spielerstatistik.
///
/// Ab Oktober 2026 trägt der Nutzer nicht mehr die tatsächlichen Monatswerte
/// ein, sondern die aktuell angezeigten Gesamtwerte des Scolia-Fensters
/// (maximal 100 Legs). Aus zwei aufeinanderfolgenden Messpunkten werden die
/// Leistungen des neuen Zeitraums abgeleitet.
class PerformanceSnapshot {
  const PerformanceSnapshot({
    required this.id,
    required this.playerId,
    required this.year,
    required this.month,
    required this.windowLegs,
    this.matches = 0,
    this.scoring,
    this.average,
    this.checkoutRate,
    this.scoringTotal = 0,
    this.averageTotal = 0,
    this.checkoutTotal = 0,
    this.newLegsOverride,
    this.isEstimated = false,
    this.note = '',
    this.updatedAt,
  });

  factory PerformanceSnapshot.create({
    required String id,
    required String playerId,
    required int year,
    required int month,
    required int windowLegs,
    required int matches,
    double? scoring,
    double? average,
    double? checkoutRate,
    int? newLegsOverride,
    String note = '',
    DateTime? updatedAt,
  }) {
    return PerformanceSnapshot(
      id: id,
      playerId: playerId,
      year: year,
      month: month,
      windowLegs: windowLegs,
      matches: matches,
      scoring: scoring,
      average: average,
      checkoutRate: checkoutRate,
      // Die kumulierten Summen sind die eigentliche Berechnungsgrundlage.
      // Ein Average wird nie subtractiv, sondern über average * legs
      // zurückgerechnet.
      scoringTotal: _cumulated(scoring, windowLegs),
      averageTotal: _cumulated(average, windowLegs),
      checkoutTotal: _cumulated(checkoutRate, windowLegs),
      newLegsOverride: newLegsOverride,
      note: note,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  static double _cumulated(double? value, int legs) =>
      value == null ? 0 : value * legs;

  final String id;
  final String playerId;
  final int year;
  final int month;
  final int windowLegs;
  final int matches;
  final double? scoring;
  final double? average;
  final double? checkoutRate;
  final double scoringTotal;
  final double averageTotal;
  final double checkoutTotal;
  final int? newLegsOverride;
  final bool isEstimated;
  final String note;
  final DateTime? updatedAt;

  String get periodKey => '$year-${month.toString().padLeft(2, '0')}';

  PerformanceSnapshot copyWith({
    String? id,
    String? playerId,
    int? year,
    int? month,
    int? windowLegs,
    int? matches,
    double? scoring,
    double? average,
    double? checkoutRate,
    double? scoringTotal,
    double? averageTotal,
    double? checkoutTotal,
    int? newLegsOverride,
    bool? isEstimated,
    String? note,
    DateTime? updatedAt,
  }) {
    return PerformanceSnapshot(
      id: id ?? this.id,
      playerId: playerId ?? this.playerId,
      year: year ?? this.year,
      month: month ?? this.month,
      windowLegs: windowLegs ?? this.windowLegs,
      matches: matches ?? this.matches,
      scoring: scoring ?? this.scoring,
      average: average ?? this.average,
      checkoutRate: checkoutRate ?? this.checkoutRate,
      scoringTotal: scoringTotal ?? this.scoringTotal,
      averageTotal: averageTotal ?? this.averageTotal,
      checkoutTotal: checkoutTotal ?? this.checkoutTotal,
      newLegsOverride: newLegsOverride ?? this.newLegsOverride,
      isEstimated: isEstimated ?? this.isEstimated,
      note: note ?? this.note,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Ein aus kumulierten Messpunkten abgeleiteter, eigenständiger Monatswert.
class DerivedPerformanceMonth {
  const DerivedPerformanceMonth({
    required this.year,
    required this.month,
    required this.weightedLegs,
    required this.matches,
    this.scoring,
    this.average,
    this.checkoutRate,
    this.isEstimated = false,
    required this.sourcePeriod,
  });

  final int year;
  final int month;
  final int weightedLegs;
  final int matches;
  final double? scoring;
  final double? average;
  final double? checkoutRate;
  final bool isEstimated;
  final String sourcePeriod;

  String get periodKey => '$year-${month.toString().padLeft(2, '0')}';
}

class PerformanceSnapshotDerivation {
  const PerformanceSnapshotDerivation({
    required this.months,
    required this.warnings,
  });

  final List<DerivedPerformanceMonth> months;
  final List<String> warnings;

  DerivedPerformanceMonth? monthFor(String periodKey) {
    for (final month in months) {
      if (month.periodKey == periodKey) return month;
    }
    return null;
  }
}

enum _Metric { scoring, average, checkout }

class _WindowSegment {
  _WindowSegment({
    required this.legs,
    required this.matches,
    required this.scoringTotal,
    required this.averageTotal,
    required this.checkoutTotal,
    required this.available,
  });

  double legs;
  double matches;
  double scoringTotal;
  double averageTotal;
  double checkoutTotal;
  final Set<_Metric> available;

  factory _WindowSegment.fromDerived(DerivedPerformanceMonth month) =>
      _WindowSegment(
        legs: month.weightedLegs.toDouble(),
        matches: month.matches.toDouble(),
        scoringTotal: (month.scoring ?? 0) * month.weightedLegs,
        averageTotal: (month.average ?? 0) * month.weightedLegs,
        checkoutTotal: (month.checkoutRate ?? 0) * month.weightedLegs,
        available: {
          if (month.scoring != null) _Metric.scoring,
          if (month.average != null) _Metric.average,
          if (month.checkoutRate != null) _Metric.checkout,
        },
      );

  double totalOf(_Metric metric) => switch (metric) {
    _Metric.scoring => scoringTotal,
    _Metric.average => averageTotal,
    _Metric.checkout => checkoutTotal,
  };
}

/// Leitet eigenständige Monatswerte aus kumulierten Scolia-Messpunkten ab.
///
/// Der Oktober 2026 ist der erste Messpunkt und wird unverändert übernommen.
/// Bei späteren Messpunkten wird geprüft, ob das 100-Leg-Fenster bereits
/// überläuft. Ist die Trennung nicht mehr eindeutig, wird ein
/// [DerivedPerformanceMonth.isEstimated]-Monat erzeugt; ein im Messpunkt
/// gespeicherter [PerformanceSnapshot.newLegsOverride] macht ihn exakt.
PerformanceSnapshotDerivation derivePerformanceMonths(
  Iterable<PerformanceSnapshot> snapshots, {
  int windowLimit = 100,
}) {
  final ordered = snapshots.toList()
    ..sort((left, right) {
      final yearOrder = left.year.compareTo(right.year);
      return yearOrder != 0 ? yearOrder : left.month.compareTo(right.month);
    });

  final months = <DerivedPerformanceMonth>[];
  final warnings = <String>[];
  var window = <_WindowSegment>[];
  PerformanceSnapshot? previous;

  for (final snapshot in ordered) {
    var estimated = snapshot.isEstimated;
    var newLegs = 0;

    if (previous == null) {
      newLegs = snapshot.windowLegs;
    } else if (snapshot.windowLegs >= windowLimit ||
        snapshot.windowLegs < previous.windowLegs) {
      // Sobald das 100-Leg-Fenster voll ist, kann nicht mehr aus dem Zähler
      // allein unterschieden werden, wie viele alte Legs herausgefallen sind.
      final hasOverride = snapshot.newLegsOverride != null;
      estimated = !hasOverride;
      final recent = months.where((month) => month.weightedLegs > 0).toList()
        ..sort((left, right) {
          final yearOrder = right.year.compareTo(left.year);
          return yearOrder != 0 ? yearOrder : right.month.compareTo(left.month);
        });
      final averageRecentLegs = recent.isEmpty
          ? null
          : recent
                    .take(3)
                    .map((month) => month.weightedLegs)
                    .reduce((left, right) => left + right) /
                min(3, recent.length);
      final minimumFill = max(0, snapshot.windowLegs - previous.windowLegs);
      final suggestion = averageRecentLegs?.round() ?? minimumFill;
      newLegs =
          snapshot.newLegsOverride ?? max(1, max(minimumFill, suggestion));
      warnings.add(
        '${snapshot.periodKey}: Das $windowLimit-Leg-Fenster ist voll '
        'oder verkleinert. '
        '${hasOverride ? 'Bestätigt' : 'Geschätzt'} '
        '($newLegs neue Legs). '
        'Bitte „Neue Legs im Monat“ prüfen.',
      );
    } else if (snapshot.windowLegs > previous.windowLegs) {
      // Solange das Fenster nicht voll ist, ist die Differenz eindeutig.
      newLegs = snapshot.windowLegs - previous.windowLegs;
    }

    if (newLegs <= 0) {
      previous = snapshot;
      continue;
    }

    var dropped = previous == null
        ? 0
        : previous.windowLegs + newLegs - snapshot.windowLegs;
    if (dropped < 0) {
      estimated = true;
      dropped = 0;
      warnings.add(
        '${snapshot.periodKey}: Der Leg-Zähler ist kleiner als erwartet. '
        'Die Monatstrennung ist nur näherungsweise möglich.',
      );
    }
    final remaining = _dropOldest(window, dropped.toDouble());

    double? metricValue(_Metric metric, double currentTotal) {
      if (switch (metric) {
            _Metric.scoring => snapshot.scoring,
            _Metric.average => snapshot.average,
            _Metric.checkout => snapshot.checkoutRate,
          } ==
          null) {
        return null;
      }
      if (previous != null &&
          remaining.any((segment) => !segment.available.contains(metric))) {
        return null;
      }
      var periodTotal =
          currentTotal -
          remaining.fold(0.0, (sum, segment) => sum + segment.totalOf(metric));
      if (periodTotal < -0.01) {
        periodTotal = 0;
        estimated = true;
      }
      final value = periodTotal / newLegs;
      if (!value.isFinite) return null;
      return value < 0 ? 0 : value;
    }

    var periodMatches =
        snapshot.matches -
        remaining.fold(0.0, (sum, segment) => sum + segment.matches);
    if (periodMatches < 0) {
      periodMatches = 0;
      estimated = true;
    }

    final derived = DerivedPerformanceMonth(
      year: snapshot.year,
      month: snapshot.month,
      weightedLegs: newLegs,
      matches: periodMatches.round(),
      scoring: metricValue(_Metric.scoring, snapshot.scoringTotal),
      average: metricValue(_Metric.average, snapshot.averageTotal),
      checkoutRate: metricValue(_Metric.checkout, snapshot.checkoutTotal),
      isEstimated: estimated,
      sourcePeriod: snapshot.periodKey,
    );
    months.add(derived);
    window = [...remaining, _WindowSegment.fromDerived(derived)];
    previous = snapshot;
  }

  return PerformanceSnapshotDerivation(
    months: List.unmodifiable(months),
    warnings: List.unmodifiable(warnings),
  );
}

List<_WindowSegment> _dropOldest(List<_WindowSegment> segments, double amount) {
  var toDrop = amount;
  final result = <_WindowSegment>[];
  for (final segment in segments) {
    if (toDrop <= 0 || segment.legs <= 0) {
      result.add(segment);
      continue;
    }
    final taken = min(segment.legs, toDrop);
    final fraction = taken / segment.legs;
    segment.legs -= taken;
    segment.matches -= segment.matches * fraction;
    segment.scoringTotal -= segment.scoringTotal * fraction;
    segment.averageTotal -= segment.averageTotal * fraction;
    segment.checkoutTotal -= segment.checkoutTotal * fraction;
    toDrop -= taken;
    if (segment.legs > 0.0001) result.add(segment);
  }
  return result;
}
