import 'dart:async';
import 'dart:io' show Platform, exit;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'theme_controller.dart';
import '../features/team_game/application/team_game_display_session_registry.dart';
import '../features/team_game/data/team_game_signal_repository.dart';
import '../features/team_game/domain/team_game_state.dart';
import '../features/team_game/presentation/team_game_display_view.dart';
import '../shared/widgets/arrow_key_dropdown_navigation.dart';

/// Vergleicht die serialisierte Signatur, damit der Monitor nur bei echten
/// Änderungen neu baut und die Animation nicht unnötig neu startet.
bool teamGameStateChanged(TeamGameState? current, TeamGameState? latest) =>
    current?.toJsonString() != latest?.toJsonString();

class TeamGameStandaloneApp extends StatefulWidget {
  const TeamGameStandaloneApp({
    super.key,
    TeamGameSignalRepository? repository,
    TeamGameDisplaySessionRegistry? registry,
  }) : _repository = repository,
       _registry = registry;

  final TeamGameSignalRepository? _repository;
  final TeamGameDisplaySessionRegistry? _registry;

  @override
  State<TeamGameStandaloneApp> createState() => _TeamGameStandaloneAppState();
}

class _TeamGameStandaloneAppState extends State<TeamGameStandaloneApp> {
  @override
  void initState() {
    super.initState();
    AppThemeController.instance.load();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: AppThemeController.instance.themeModeNotifier,
    builder: (context, themeMode, _) => ValueListenableBuilder<AppThemeStyle>(
      valueListenable: AppThemeController.instance.themeStyleNotifier,
      builder: (context, style, _) {
        final christmas = style == AppThemeStyle.christmas;
        return MaterialApp(
          title: 'Team Game Anzeige (Zweitbildschirm-Modus)',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: buildDartTournamentTheme(christmas: christmas),
          darkTheme: buildDartTournamentDarkTheme(christmas: christmas),
          builder: (context, child) => ArrowKeyDropdownNavigation(
            child: child ?? const SizedBox.shrink(),
          ),
          home: _TeamGameStandalonePage(
            repository: widget._repository,
            registry: widget._registry,
          ),
        );
      },
    ),
  );
}

class _TeamGameStandalonePage extends StatefulWidget {
  const _TeamGameStandalonePage({this.repository, this.registry});

  final TeamGameSignalRepository? repository;
  final TeamGameDisplaySessionRegistry? registry;

  @override
  State<_TeamGameStandalonePage> createState() =>
      _TeamGameStandalonePageState();
}

class _TeamGameStandalonePageState extends State<_TeamGameStandalonePage> {
  late final TeamGameSignalRepository _repository;
  late final TeamGameDisplaySessionRegistry _registry;
  TeamGameState? _state;
  bool _hasLoadError = false;
  bool _isLoading = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? TeamGameSignalRepository();
    _registry = widget.registry ?? TeamGameDisplaySessionRegistry();
    _load(silent: false);
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _load(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    unawaited(_registry.clear());
    super.dispose();
  }

  Future<void> _load({required bool silent}) async {
    if (_isLoading) return;
    _isLoading = true;
    try {
      final loaded = await _repository.load();
      if (mounted && teamGameStateChanged(_state, loaded)) {
        setState(() {
          _state = loaded;
          _hasLoadError = false;
        });
      } else if (mounted && silent && _hasLoadError) {
        setState(() => _hasLoadError = false);
      }
    } catch (_) {
      if (mounted && !silent && !_hasLoadError) {
        setState(() => _hasLoadError = true);
      }
    } finally {
      _isLoading = false;
      unawaited(_registry.heartbeat());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          TeamGameDisplayView(state: _state, onClose: _closeStandaloneWindow),
          if (_hasLoadError)
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Material(
                color: Colors.red.shade900,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'Aktualisierung fehlgeschlagen. Letzter Stand wird angezeigt.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _closeStandaloneWindow() {
    if (Platform.isAndroid || Platform.isIOS) {
      SystemNavigator.pop();
    } else {
      exit(0);
    }
  }
}
