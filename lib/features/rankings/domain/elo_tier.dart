import 'package:flutter/material.dart';

class EloTier {
  const EloTier({
    required this.name,
    required this.minElo,
    required this.color,
    required this.icon,
  });

  final String name;
  final int minElo;
  final Color color;
  final IconData icon;

  static const diamant = EloTier(
    name: 'Diamant',
    minElo: 1200,
    color: Color(0xFF00BCD4),
    icon: Icons.diamond_outlined,
  );
  static const platin = EloTier(
    name: 'Platin',
    minElo: 1100,
    color: Color(0xFF90A4AE),
    icon: Icons.military_tech_outlined,
  );
  static const gold = EloTier(
    name: 'Gold',
    minElo: 1000,
    color: Color(0xFFFFD700),
    icon: Icons.emoji_events_outlined,
  );
  static const silber = EloTier(
    name: 'Silber',
    minElo: 900,
    color: Color(0xFFB0BEC5),
    icon: Icons.shield_outlined,
  );
  static const bronze = EloTier(
    name: 'Bronze',
    minElo: 0,
    color: Color(0xFFCD7F32),
    icon: Icons.shield,
  );

  static const values = [diamant, platin, gold, silber, bronze];

  static EloTier styled({
    required String name,
    required int minElo,
    required int index,
  }) {
    final style = values[index % values.length];
    return EloTier(
      name: name,
      minElo: minElo,
      color: style.color,
      icon: style.icon,
    );
  }

  static EloTier fromElo(int elo, {List<EloTier>? tiers}) {
    final sorted = (tiers ?? values).toList()
      ..sort((left, right) => right.minElo.compareTo(left.minElo));
    return sorted.firstWhere(
      (tier) => elo >= tier.minElo,
      orElse: () => sorted.last,
    );
  }

  Map<String, Object?> toJson() => {'name': name, 'minElo': minElo};

  factory EloTier.fromJson(Map<String, Object?> json, int index) => styled(
    name: json['name'] as String? ?? values[index % values.length].name,
    minElo: json['minElo'] as int? ?? 0,
    index: index,
  );

  @override
  bool operator ==(Object other) =>
      other is EloTier && other.name == name && other.minElo == minElo;

  @override
  int get hashCode => Object.hash(name, minElo);
}
