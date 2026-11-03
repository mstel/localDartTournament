class TournamentActivityEntry {
  const TournamentActivityEntry({
    required this.type,
    required this.message,
    required this.timestamp,
  });

  final String type;
  final String message;
  final DateTime timestamp;

  factory TournamentActivityEntry.fromJson(Map<String, dynamic> json) =>
      TournamentActivityEntry(
        type: json['type'] as String,
        message: json['message'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );

  Map<String, dynamic> toJson() => {
    'type': type,
    'message': message,
    'timestamp': timestamp.toUtc().toIso8601String(),
  };
}
