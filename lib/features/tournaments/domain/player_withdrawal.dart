enum WithdrawalResultMode { loseOpen, loseAll, ignoreOpen, ignoreAll }

class PlayerWithdrawal {
  const PlayerWithdrawal({
    required this.playerKey,
    required this.mode,
    required this.createdAt,
    this.stageIndex,
    this.countForRanking = false,
    this.countOpponentsForRanking = true,
  });
  final String playerKey;
  final WithdrawalResultMode mode;
  final DateTime createdAt;
  final int? stageIndex;
  final bool countForRanking, countOpponentsForRanking;
  bool get retroactive =>
      mode == WithdrawalResultMode.loseAll ||
      mode == WithdrawalResultMode.ignoreAll;
  bool get ignore =>
      mode == WithdrawalResultMode.ignoreAll ||
      mode == WithdrawalResultMode.ignoreOpen;
  Map<String, dynamic> toJson() => {
    'version': 2,
    'playerKey': playerKey,
    'mode': mode.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (stageIndex != null) 'stageIndex': stageIndex,
    'countForRanking': countForRanking,
    'countOpponentsForRanking': countOpponentsForRanking,
  };
  factory PlayerWithdrawal.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version != 1 && version != 2) {
      throw const FormatException('Unbekannte Ausstiegsversion');
    }
    return PlayerWithdrawal(
      playerKey: json['playerKey'] as String,
      mode: WithdrawalResultMode.values.byName(json['mode'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      stageIndex: json['stageIndex'] as int?,
      countForRanking: json['countForRanking'] == true,
      countOpponentsForRanking: json['countOpponentsForRanking'] != false,
    );
  }
}
