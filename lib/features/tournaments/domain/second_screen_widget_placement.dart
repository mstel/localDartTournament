class SecondScreenWidgetPlacement {
  const SecondScreenWidgetPlacement({
    required this.widgetId,
    this.widthUnits = 1,
    this.heightUnits = 1.0,
    this.startsNewRow = false,
    this.columnIndex,
  });

  factory SecondScreenWidgetPlacement.fromJson(Map<String, dynamic> json) =>
      SecondScreenWidgetPlacement(
        widgetId: json['widgetId'] as String? ?? '',
        widthUnits: (json['widthUnits'] as int? ?? 1).clamp(1, 4),
        heightUnits: _heightUnitsFromJson(json['heightUnits']),
        startsNewRow: json['startsNewRow'] as bool? ?? false,
        columnIndex: (json['columnIndex'] as int?)?.clamp(0, 1),
      );

  final String widgetId;
  final int widthUnits;
  final double heightUnits;
  final bool startsNewRow;
  final int? columnIndex;

  Map<String, dynamic> toJson() => {
    'widgetId': widgetId,
    'widthUnits': widthUnits,
    'heightUnits': heightUnits,
    if (startsNewRow) 'startsNewRow': true,
    if (columnIndex != null) 'columnIndex': columnIndex,
  };

  static double _heightUnitsFromJson(Object? value) {
    final units = value is num ? value.toDouble() : 1.0;
    return (units.clamp(0.5, 3.0) * 2).round() / 2;
  }
}
