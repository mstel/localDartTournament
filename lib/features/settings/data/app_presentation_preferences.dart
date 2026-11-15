import 'package:shared_preferences/shared_preferences.dart';

class AppPresentationPreferences {
  const AppPresentationPreferences({
    this.dynamicDashboardEnabled = true,
    this.dashboardIntervalSeconds = 5,
    this.pdfShowDate = true,
    this.pdfShowSignatures = true,
    this.pdfShowAdvancement = true,
    this.pdfLandscape = true,
    this.pdfShowNotes = true,
    this.pdfShowBestPerformances = true,
  });

  final bool dynamicDashboardEnabled;
  final int dashboardIntervalSeconds;
  final bool pdfShowDate;
  final bool pdfShowSignatures;
  final bool pdfShowAdvancement;
  final bool pdfLandscape;
  final bool pdfShowNotes;
  final bool pdfShowBestPerformances;

  static const _prefix = 'app_presentation_';

  static Future<AppPresentationPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppPresentationPreferences(
      dynamicDashboardEnabled:
          prefs.getBool('${_prefix}dashboard_enabled') ?? true,
      dashboardIntervalSeconds:
          (prefs.getInt('${_prefix}dashboard_interval') ?? 5).clamp(1, 300),
      pdfShowDate: prefs.getBool('${_prefix}pdf_date') ?? true,
      pdfShowSignatures: prefs.getBool('${_prefix}pdf_signatures') ?? true,
      pdfShowAdvancement: prefs.getBool('${_prefix}pdf_advancement') ?? true,
      pdfLandscape: prefs.getBool('${_prefix}pdf_landscape') ?? true,
      pdfShowNotes: prefs.getBool('${_prefix}pdf_notes') ?? true,
      pdfShowBestPerformances:
          prefs.getBool('${_prefix}pdf_best_performances') ?? true,
    );
  }

  Future<void> save({
    bool? dynamicDashboardEnabled,
    int? dashboardIntervalSeconds,
    bool? pdfShowDate,
    bool? pdfShowSignatures,
    bool? pdfShowAdvancement,
    bool? pdfLandscape,
    bool? pdfShowNotes,
    bool? pdfShowBestPerformances,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (dynamicDashboardEnabled != null) {
      await prefs.setBool(
        '${_prefix}dashboard_enabled',
        dynamicDashboardEnabled,
      );
    }
    if (dashboardIntervalSeconds != null) {
      await prefs.setInt(
        '${_prefix}dashboard_interval',
        dashboardIntervalSeconds.clamp(1, 300),
      );
    }
    if (pdfShowDate != null) {
      await prefs.setBool('${_prefix}pdf_date', pdfShowDate);
    }
    if (pdfShowSignatures != null) {
      await prefs.setBool('${_prefix}pdf_signatures', pdfShowSignatures);
    }
    if (pdfShowAdvancement != null) {
      await prefs.setBool('${_prefix}pdf_advancement', pdfShowAdvancement);
    }
    if (pdfLandscape != null) {
      await prefs.setBool('${_prefix}pdf_landscape', pdfLandscape);
    }
    if (pdfShowNotes != null) {
      await prefs.setBool('${_prefix}pdf_notes', pdfShowNotes);
    }
    if (pdfShowBestPerformances != null) {
      await prefs.setBool(
        '${_prefix}pdf_best_performances',
        pdfShowBestPerformances,
      );
    }
  }
}
