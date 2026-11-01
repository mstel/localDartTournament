class SecondScreenWidgetPlacement {
  const SecondScreenWidgetPlacement({
    required this.widgetId,
    this.widthUnits = 1,
    this.heightUnits = 1.0,
  });

  factory SecondScreenWidgetPlacement.fromJson(Map<String, dynamic> json) =>
      SecondScreenWidgetPlacement(
        widgetId: json['widgetId'] as String? ?? '',
        widthUnits: (json['widthUnits'] as int? ?? 1).clamp(1, 4),
        heightUnits: _heightUnitsFromJson(json['heightUnits']),
      );

  final String widgetId;
  final int widthUnits;
  final double heightUnits;

  Map<String, dynamic> toJson() => {
    'widgetId': widgetId,
    'widthUnits': widthUnits,
    'heightUnits': heightUnits,
  };

  static double _heightUnitsFromJson(Object? value) {
    final units = value is num ? value.toDouble() : 1.0;
    return (units.clamp(0.5, 3.0) * 2).round() / 2;
  }
}
