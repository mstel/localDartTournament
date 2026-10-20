import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../tournament_workspace.dart';
import 'app_theme.dart';
import 'theme_controller.dart';
import '../features/backups/application/supabase_workspace_sync_service.dart';

class DartTournamentApp extends StatefulWidget {
  const DartTournamentApp({super.key});

  @override
  State<DartTournamentApp> createState() => _DartTournamentAppState();
}

class _DartTournamentAppState extends State<DartTournamentApp>
    with WidgetsBindingObserver {
  final _workspaceSync = SupabaseWorkspaceSyncService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _workspaceSync.start();
    AppThemeController.instance.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _workspaceSync.synchronize();
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: AppThemeController.instance.themeModeNotifier,
    builder: (context, themeMode, _) => MaterialApp(
      title: 'DartTournamentPro',
      scrollBehavior: const DartTournamentScrollBehavior(),
      themeMode: themeMode,
      theme: buildDartTournamentTheme(),
      darkTheme: buildDartTournamentDarkTheme(),
      home: const HomePage(),
    ),
  );
}

class DartTournamentScrollBehavior extends MaterialScrollBehavior {
  const DartTournamentScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}
