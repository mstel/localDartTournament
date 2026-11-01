class SecondScreenWidgetPlacement {
  const SecondScreenWidgetPlacement({
    required this.widgetId,
    this.widthUnits = 1,
    this.heightUnits = 1,
  });

  factory SecondScreenWidgetPlacement.fromJson(Map<String, dynamic> json) =>
      SecondScreenWidgetPlacement(
        widgetId: json['widgetId'] as String? ?? '',
        widthUnits: (json['widthUnits'] as int? ?? 1).clamp(1, 4),
        heightUnits: (json['heightUnits'] as int? ?? 1).clamp(1, 3),
      );

  final String widgetId;
  final int widthUnits;
  final int heightUnits;

  Map<String, dynamic> toJson() => {
    'widgetId': widgetId,
    'widthUnits': widthUnits,
    'heightUnits': heightUnits,
  };
}
